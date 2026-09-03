/* rules.mjs — the G0 rule set as data: load, validate, stratify, and mint the content-bound rule ids.
 * `rule_sem_id = "g0rule-" + sha256("G0-RULESET-v1|" + canonical bytes of the rule set)` — the `programSemId`
 * discipline (id = hash of the canonical program, never a name) without impersonating TRVM's `psem-` prefix. The
 * evaluator that runs these rules is G0-E; this module is what G0-A freezes: the program and its identity. */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { createHash } from "node:crypto";
import { canonicalBytesG0, G0Error } from "./canon.mjs";
import { compile } from "./schema.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const RULES_PATH = resolve(HERE, "../rules/g0.rules.json");
const rulesSchema = compile(JSON.parse(readFileSync(resolve(HERE, "../schemas/rules.schema.json"), "utf8")));

export function loadRules(path = RULES_PATH) {
  const doc = JSON.parse(readFileSync(path, "utf8"));
  const errors = rulesSchema(doc);
  if (errors.length) throw new G0Error("RULES_SCHEMA", errors.map((e) => `${e.instancePath} ${e.message}`).join("; "));
  const names = new Set();
  for (const r of doc.rules) { if (names.has(r.name)) throw new G0Error("RULES_DUPLICATE_NAME", r.name); names.add(r.name); }
  checkStratification(doc);
  checkSafety(doc);
  const bytes = canonicalBytesG0(doc);
  const rule_sem_id = "g0rule-" + createHash("sha256").update(Buffer.concat([Buffer.from("G0-RULESET-v1|", "utf8"), bytes])).digest("hex");
  return { doc, rule_sem_id, rule_ids: Object.fromEntries(doc.rules.map((r) => [r.name, `${rule_sem_id}#${r.name}`])), bytes };
}

/** A negated body atom must refer to a relation defined only in a strictly lower stratum (or a base fact);
 *  a positive atom may refer to the same stratum. Refuses on violation — never "undefined semantics". */
export function checkStratification(doc) {
  const stratumOf = new Map();
  for (const r of doc.rules) { const s = stratumOf.get(r.head.rel); if (s !== undefined && s !== r.stratum) throw new G0Error("RULES_STRATUM_CONFLICT", `${r.head.rel} defined in strata ${s} and ${r.stratum}`); stratumOf.set(r.head.rel, r.stratum); }
  for (const r of doc.rules) for (const a of r.body) {
    const base = a.rel in doc.facts; const s = stratumOf.get(a.rel);
    if (!base && s === undefined) throw new G0Error("RULES_UNDEFINED_RELATION", `${r.name} uses ${a.rel}, defined nowhere`);
    if (a.neg && !base && !(s < r.stratum)) throw new G0Error("RULES_NEGATION_NOT_STRATIFIED", `${r.name} negates ${a.rel} (stratum ${s}) from stratum ${r.stratum}`);
    if (!a.neg && !base && s > r.stratum) throw new G0Error("RULES_FORWARD_REFERENCE", `${r.name} (stratum ${r.stratum}) uses ${a.rel} from stratum ${s}`);
    const arity = base ? doc.facts[a.rel].arity : doc.rules.find((x) => x.head.rel === a.rel).head.args.length;
    if (a.args.length !== arity) throw new G0Error("RULES_ARITY", `${r.name}: ${a.rel}/${a.args.length} vs declared ${arity}`);
  }
}
/** A VARIABLE is an initial capital followed by lowercase letters, digits or underscores (`C`, `W`, `Var1`); every other
 *  string is a constant — so the ALL-CAPS tokens of the domain (`WITNESSES`, `RECEIPT`, `TESTED`) are never mistaken for
 *  variables. (Until 2026-09-03 the regex accepted any capitalised token; positive atoms hid it, a negated `WITNESSES`
 *  constant exposed it.) */
export const isVar = (x) => typeof x === "string" && /^[A-Z][a-z0-9_]*$/.test(x);
/** Range restriction: every head variable and every variable of a negated atom appears in a positive body atom. */
export function checkSafety(doc) {
  for (const r of doc.rules) {
    const bound = new Set(); for (const a of r.body) if (!a.neg) for (const x of a.args) if (isVar(x) && x !== "_") bound.add(x);
    for (const x of r.head.args) if (isVar(x) && !bound.has(x)) throw new G0Error("RULES_UNSAFE", `${r.name}: head variable ${x} not bound positively`);
    for (const a of r.body) if (a.neg) for (const x of a.args) if (isVar(x) && x !== "_" && !bound.has(x)) throw new G0Error("RULES_UNSAFE", `${r.name}: negated variable ${x} not bound positively`);
  }
}
