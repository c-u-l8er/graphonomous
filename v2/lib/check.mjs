/* check.mjs — the INDEPENDENT derivation checker (spec §10.4): shares no logic with eval.mjs. Given a stored
 * derivation it re-does only what a reader could do by hand — substitute the recorded bindings into the named rule,
 * confirm each positive premise is a fact strictly shallower than the conclusion, each `{absent}` premise has no
 * matching fact, the instantiated head is the conclusion, and the id recomputes — and refuses otherwise with a
 * precise reason. It imports canonical bytes and sha256 from canon.mjs (the substrate), nothing from the evaluator. */
import { canonicalBytesG0, sha256Hex } from "./canon.mjs";

const key = (v) => canonicalBytesG0(v).toString("utf8");
const isVar = (x) => typeof x === "string" && /^[A-Z][a-z0-9_]*$/.test(x); // the rules.mjs convention: ALL-CAPS tokens are constants
const same = (a, b) => key(a) === key(b);
const substitute = (args, bindings, where, problems) => args.map((t) => { if (t === "_") return "_"; if (isVar(t)) { if (!(t in bindings)) problems.push(`${where}: variable ${t} has no binding`); return bindings[t]; } return t; });
/** ground-or-wild pattern vs ground atom: same relation, same arity, every non-wild position equal. */
const covers = (pattern, atom) => pattern.length === atom.length && pattern.every((t, i) => t === "_" || same(t, atom[i]));

/** A fact store over the evaluator's `facts` Map (or any Map key → {rel, args, depth}). */
export function makeFactStore(factsMap) {
  const byRel = new Map();
  for (const f of factsMap.values()) { if (!byRel.has(f.rel)) byRel.set(f.rel, []); byRel.get(f.rel).push([f.rel, ...f.args]); }
  return {
    has: (k) => factsMap.has(k),
    depthOf: (k) => factsMap.get(k)?.depth,
    matches: (pattern) => (byRel.get(pattern[0]) || []).some((atom) => covers(pattern, atom)),
  };
}

export function checkDerivation(rulesDoc, ruleSemId, d, store) {
  const problems = [];
  const hash = d.rule.split("#")[0], name = d.rule.split("#")[1];
  if (hash !== ruleSemId) problems.push(`rule id ${hash} is not the program ${ruleSemId}`);
  const rule = rulesDoc.rules.find((r) => r.name === name);
  if (!rule) return { ok: false, problems: [...problems, `no rule named ${name}`] };
  if (!d.bindings || typeof d.bindings !== "object") return { ok: false, problems: [...problems, "bindings missing"] };
  const head = [rule.head.rel, ...substitute(rule.head.args, d.bindings, "head", problems)];
  if (!same(head, d.conclusion)) problems.push(`head ${JSON.stringify(head)} != conclusion ${JSON.stringify(d.conclusion)}`);
  if (!Array.isArray(d.premises) || d.premises.length !== rule.body.length) problems.push(`${d.premises?.length} premises for a body of ${rule.body.length}`);
  let maxDepth = 0;
  rule.body.forEach((atom, i) => {
    const prem = d.premises?.[i]; if (prem === undefined) return;
    const pattern = [atom.rel, ...substitute(atom.args, d.bindings, `body[${i}]`, problems)];
    if (atom.neg) {
      if (!prem || Array.isArray(prem) || typeof prem !== "object" || !Array.isArray(prem.absent)) { problems.push(`body[${i}] is negated but premise is not {absent}`); return; }
      if (!same(prem.absent, pattern)) problems.push(`body[${i}]: absent atom ${JSON.stringify(prem.absent)} != ${JSON.stringify(pattern)}`);
      if (store.matches(pattern)) problems.push(`body[${i}]: a fact matches ${JSON.stringify(pattern)}, so it is not absent`);
      return;
    }
    if (!Array.isArray(prem)) { problems.push(`body[${i}] is positive but premise is not an atom`); return; }
    if (!covers(pattern, prem)) problems.push(`body[${i}]: premise ${JSON.stringify(prem)} does not match ${JSON.stringify(pattern)}`);
    const k = key(prem);
    if (!store.has(k)) problems.push(`body[${i}]: premise ${JSON.stringify(prem)} is not a fact`);
    else { const pd = store.depthOf(k); if (pd === undefined || !(pd < d.depth)) problems.push(`body[${i}]: premise depth ${pd} is not below ${d.depth}`); else maxDepth = Math.max(maxDepth, pd); }
  });
  if (problems.length === 0 && d.depth !== 1 + maxDepth) problems.push(`depth ${d.depth} != 1 + max premise depth ${maxDepth}`);
  const id = "sha256:" + sha256Hex(canonicalBytesG0({ rule: d.rule, conclusion: d.conclusion, premises: d.premises }));
  if (id !== d.id) problems.push(`id ${d.id} does not recompute (${id})`);
  return { ok: problems.length === 0, problems };
}

/** Check every derivation of every derived fact in an evaluation result. */
export function checkAll(rulesDoc, ruleSemId, evaluation) {
  const store = makeFactStore(evaluation.facts); const failures = []; let checked = 0;
  for (const f of evaluation.derived) for (const d of f.derivations) { checked++; const r = checkDerivation(rulesDoc, ruleSemId, d, store); if (!r.ok) failures.push({ key: key([f.rel, ...f.args]), problem: r.problems.join("; ") }); }
  return { checked, ok: failures.length === 0, failures };
}
