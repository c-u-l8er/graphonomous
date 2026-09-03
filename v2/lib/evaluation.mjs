/* evaluation.mjs — G0-E: run the rule program over a BUILT projection and publish the derived facts as their own
 * content-addressed artifact beside it (`<projection>/derived/`), never inside the observed projection root.
 *
 * WHY A SEPARATE ROOT. The observed root binds what the registries said (basis: observed). Derived facts are a
 * function of (that root, the rule program); folding them into the same manifest would let a rule change move the
 * evidence root, and would let a reader mistake a derivation for an observation. So the evaluation manifest names the
 * projection root it was computed from, the ruleset id, the evaluator, and `trvm_derivation: false` (spec §8.4,
 * D-007, D-019): this is Graphonomous's rule evaluation, recorded as labelled provenance, not a TRVM derivation.
 *
 * INDEPENDENT REPLAY. `verifyEvaluation` rebuilds the base facts from the projection records on disk, loads the stored
 * derived facts, and hands every stored derivation to lib/check.mjs — code that shares nothing with the evaluator —
 * so a tampered derivation is refused from the stored artifact, not only in memory. */
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { canonicalBytesG0, hashRecord, hashOfBytes, sha256Hex, sortSet, G0Error, artifactRoot } from "./canon.mjs";
import { putArtifact, resolveArtifact, directoryStore } from "../../../TRVM/governance/cas.mjs";
import { compile } from "./schema.mjs";
import { loadRules } from "./rules.mjs";
import { evaluate } from "./eval.mjs";
import { checkAll, checkDerivation, makeFactStore } from "./check.mjs";
import { factsFromRecords } from "./facts.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(HERE, "..");
const SPEC_ID = "G0_G1_SPEC.md@2026-09-02";
export const EVALUATOR = "graphonomous.g0.eval.v0";
const schema = Object.fromEntries(["derived_fact", "evaluation"].map((n) => [n, compile(JSON.parse(readFileSync(resolve(ROOT_DIR, "schemas", n + ".schema.json"), "utf8")))]));
const readLines = (dir, kind) => readFileSync(join(dir, `records/${kind}.jsonl`), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const factKey = (rel, args) => canonicalBytesG0([rel, ...args]).toString("utf8");
export const factKeyHash = (rel, args) => "sha256:" + sha256Hex(canonicalBytesG0([rel, ...args]));

/** Load a built projection directory into memory (records, root, snapshot). */
export function loadProjection(dir) {
  if (!existsSync(join(dir, "ROOT"))) throw new G0Error("NO_PROJECTION", `${dir} has no ROOT`);
  const root = readFileSync(join(dir, "ROOT"), "utf8").trim();
  const manifest = JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  const p = { dir, root, manifest, snapshot: manifest.snapshot, nodes: readLines(dir, "node"), relations: readLines(dir, "relation"), assertions: readLines(dir, "assertion"), locations: readLines(dir, "source_location"), faults: readLines(dir, "fault") };
  p.byLid = new Map([...p.nodes, ...p.relations, ...p.assertions, ...p.locations].map((r) => [r.lid, r]));
  p.derived = existsSync(join(dir, "derived", "manifest.json")) ? loadEvaluation(join(dir, "derived")) : null;
  return p;
}
export function loadEvaluation(evalDir) {
  const manifest = JSON.parse(readFileSync(join(evalDir, "manifest.json"), "utf8"));
  const facts = readFileSync(join(evalDir, "facts.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  return { dir: evalDir, root: readFileSync(join(evalDir, "ROOT"), "utf8").trim(), manifest, facts, byKey: new Map(facts.map((f) => [factKey(f.rel, f.args), f])) };
}
export const baseFactsOf = (p) => factsFromRecords({ nodes: p.nodes, relations: p.relations, assertions: p.assertions });

/** Evaluate the rule program over a projection and write `derived/`. Deterministic: records sorted by fact key. */
export function runEvaluation(dir, { out = join(dir, "derived"), maxAlt = 4, quiet = true } = {}) {
  const p = loadProjection(dir);
  const rules = loadRules();
  if (p.manifest.ruleset !== rules.rule_sem_id) throw new G0Error("RULESET_MISMATCH", `projection was built under ${p.manifest.ruleset}, the loaded program is ${rules.rule_sem_id}: rebuild the projection or pin the program`);
  const base = baseFactsOf(p);
  const ev = evaluate(rules.doc, rules.rule_sem_id, base, { maxAlt });
  const check = checkAll(rules.doc, rules.rule_sem_id, ev);
  if (!check.ok) throw new G0Error("DERIVATION_REJECTED", `${check.failures.length} derivation(s) refused by the independent checker: ${JSON.stringify(check.failures.slice(0, 3))}`);
  const records = ev.derived.map((f) => ({ key: factKeyHash(f.rel, f.args), rel: f.rel, args: f.args, basis: "derived", depth: f.depth, derivations: f.derivations, snapshot: p.snapshot, inputs: [p.root], evaluator: EVALUATOR, trvm_derivation: false }));
  const prepared = records.map((r) => ({ r, hash: hashRecord(r).hash })).sort((a, b) => a.r.key < b.r.key ? -1 : a.r.key > b.r.key ? 1 : 0);
  const schemaFaults = []; for (const { r } of prepared) { const errs = schema.derived_fact(r); if (errs.length) schemaFaults.push({ key: r.key, errors: errs.slice(0, 3) }); }
  if (schemaFaults.length) throw new G0Error("RECORD_SCHEMA", JSON.stringify(schemaFaults.slice(0, 3), null, 1));
  const lines = prepared.map(({ r }) => canonicalBytesG0(r).toString("utf8"));
  const manifest = { kind: "graphonomous.rule-evaluation", spec: SPEC_ID, snapshot: p.snapshot, projection_root: p.root, ruleset: rules.rule_sem_id, evaluator: EVALUATOR, trvm_derivation: false, count: prepared.length, by_rule: Object.fromEntries(Object.entries(ev.by_rule).sort()), digest: ev.digest, entries: prepared.map(({ r, hash }) => [r.key, hash]), checker: { checked: check.checked, ok: check.ok, failures: check.failures.length } };
  const merrs = schema.evaluation(manifest); if (merrs.length) throw new G0Error("MANIFEST_SCHEMA", merrs.map((e) => `${e.instancePath} ${e.message}`).join("; "));
  const root = artifactRoot(manifest);
  rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "facts.jsonl"), Buffer.from(lines.join("\n"), "utf8"));
  writeFileSync(join(out, "manifest.json"), canonicalBytesG0(manifest));
  writeFileSync(join(out, "ROOT"), root + "\n");
  for (const { r } of prepared) putArtifact(join(out, "cas"), r);
  putArtifact(join(out, "cas"), manifest);
  return { root, manifest, evaluation: ev, check, records: prepared.length };
}

/** Replay a stored evaluation independently: CAS resolution, root, digest, and every stored derivation through the
 *  checker against base facts rebuilt from the projection records. Returns {problems: []} when clean. */
export function verifyEvaluation(dir, evalDir = join(dir, "derived")) {
  const p = loadProjection(dir); const e = loadEvaluation(evalDir); const problems = [];
  const rules = loadRules();
  if (e.manifest.projection_root !== p.root) problems.push(`evaluation names projection root ${e.manifest.projection_root}, projection is ${p.root}`);
  if (e.manifest.ruleset !== rules.rule_sem_id) problems.push(`evaluation ruleset ${e.manifest.ruleset} != loaded program ${rules.rule_sem_id}`);
  if (e.manifest.trvm_derivation !== false) problems.push("an evaluation may never claim a TRVM derivation");
  if (artifactRoot(e.manifest) !== e.root) problems.push(`ROOT ${e.root} != manifest root ${artifactRoot(e.manifest)}`);
  const store = directoryStore(join(evalDir, "cas"));
  if (resolveArtifact(store, e.root).outcome !== "ok") problems.push("evaluation manifest does not resolve through the CAS");
  const lines = readFileSync(join(evalDir, "facts.jsonl"), "utf8").split("\n").filter(Boolean);
  if (lines.length !== e.manifest.count || e.manifest.entries.length !== lines.length) problems.push(`count ${e.manifest.count} vs ${lines.length} stored facts`);
  lines.forEach((line, i) => { const [key, hash] = e.manifest.entries[i] || []; const rec = JSON.parse(line); if (rec.key !== key) problems.push(`entry ${i}: key ${key} vs record ${rec.key}`); if (hashOfBytes(Buffer.from(line, "utf8")) !== hash) problems.push(`${key}: stored bytes hash differently than the manifest`); if (resolveArtifact(store, artifactRoot(rec)).outcome !== "ok") problems.push(`${key}: CAS ${resolveArtifact(store, artifactRoot(rec)).outcome}`); if (rec.basis !== "derived" || rec.trvm_derivation !== false) problems.push(`${key}: basis/trvm_derivation labels wrong`); if (!rec.inputs.includes(p.root)) problems.push(`${key}: does not name the projection root as input`); });
  // the independent replay: base facts from the projection, derived facts from the stored records
  const facts = new Map(); for (const f of baseFactsOf(p)) facts.set(factKey(f.rel, f.args), { rel: f.rel, args: f.args, basis: "base", depth: 0, derivations: [] });
  for (const f of e.facts) facts.set(factKey(f.rel, f.args), { rel: f.rel, args: f.args, basis: "derived", depth: f.depth, derivations: f.derivations });
  const fs = makeFactStore(facts); let checked = 0; const ids = [];
  for (const f of e.facts) for (const d of f.derivations) { checked++; ids.push(d.id); const r = checkDerivation(rules.doc, rules.rule_sem_id, d, fs); if (!r.ok) problems.push(`${factKey(f.rel, f.args)}: ${r.problems.join("; ")}`); }
  const digest = "sha256:" + sha256Hex(canonicalBytesG0(sortSet(ids)));
  if (digest !== e.manifest.digest) problems.push(`derivation-set digest ${digest} != manifest ${e.manifest.digest}`);
  return { root: e.root, projection_root: p.root, facts: e.facts.length, derivations_checked: checked, problems };
}
