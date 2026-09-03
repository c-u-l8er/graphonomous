/* eval.mjs — the G0-E evaluator: a stratified, semi-naive Datalog fixpoint over ground JSON terms, recording a
 * JTMS-shaped derivation for every derived fact (spec §10.2–10.3; D-011 build-don't-adopt; D-007/D-019: this is
 * Graphonomous's own evaluation, `trvm_derivation: false`, never a TRVM receipt).
 *
 * WHY THIS SHAPE. Terms are arbitrary G0 values and two terms are equal iff their canonical bytes are equal — so the
 * whole evaluator is keyed by canonical bytes and nothing depends on Map insertion order: facts are visited in sorted
 * key order, rules in program order, and the result is a pure function of (program, fact set). Derivations are
 * collected exhaustively (every ground rule instantiation whose premises hold — a finite set) and only then ranked by
 * (depth, bytes) and capped at `maxAlt`, so the kept alternatives cannot depend on the iteration schedule. Depth is
 * recomputed to a fixpoint at the end (1 + max premise depth; base = 0), so a shallower proof found late still wins.
 * Negation is read only against completed lower strata + base facts (rules.mjs refuses anything else at load). */
import { canonicalBytesG0, sha256Hex } from "./canon.mjs";

export const EVALUATOR_ID = "graphonomous.g0.eval.v0";
const key = (v) => canonicalBytesG0(v).toString("utf8");
const isVar = (x) => typeof x === "string" && /^[A-Z][a-z0-9_]*$/.test(x); // rules.mjs: capital + lowercase/digits; ALL-CAPS = constant
const isWild = (x) => x === "_";
const cmpKey = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/** Facts by relation, with an index on every (position, constant) pair for joins. */
class Table {
  constructor() { this.byKey = new Map(); this.byRel = new Map(); this.idx = new Map(); }
  add(f) {
    const k = key([f.rel, ...f.args]); if (this.byKey.has(k)) return false;
    this.byKey.set(k, f);
    if (!this.byRel.has(f.rel)) this.byRel.set(f.rel, new Map()); this.byRel.get(f.rel).set(k, f);
    f.args.forEach((a, i) => { const ik = `${f.rel}|${i}|${key(a)}`; if (!this.idx.has(ik)) this.idx.set(ik, new Map()); this.idx.get(ik).set(k, f); });
    return true;
  }
  /** Candidates for a partially bound pattern: the smallest index among its bound positions, else the whole relation. */
  candidates(rel, pattern) {
    let best = null;
    pattern.forEach((t, i) => { if (isVar(t) || isWild(t)) return; const m = this.idx.get(`${rel}|${i}|${key(t)}`) || new Map(); if (!best || m.size < best.size) best = m; });
    return best || this.byRel.get(rel) || new Map();
  }
  /** Does any fact match the ground-or-wild pattern? (negation) */
  matches(rel, pattern) { for (const f of this.candidates(rel, pattern).values()) if (unify(pattern, f.args, {})) return true; return false; }
}

/** Unify a pattern (constants, variables, wildcards) against ground args under `env`; returns the extended env or null. */
function unify(pattern, args, env) {
  if (pattern.length !== args.length) return null;
  let e = env;
  for (let i = 0; i < pattern.length; i++) {
    const t = pattern[i], a = args[i];
    if (isWild(t)) continue;
    if (isVar(t)) { if (t in e) { if (key(e[t]) !== key(a)) return null; } else { e = { ...e, [t]: a }; } continue; }
    if (key(t) !== key(a)) return null;
  }
  return e;
}
const subst = (pattern, env) => pattern.map((t) => (isVar(t) && t in env ? env[t] : t));

/** Evaluate `rulesDoc` (already validated by rules.mjs) over `baseFacts` [{rel, args}]. */
export function evaluate(rulesDoc, ruleSemId, baseFacts, { maxAlt = 4 } = {}) {
  const T = new Table();
  const sorted = baseFacts.slice().sort((a, b) => cmpKey(key([a.rel, ...a.args]), key([b.rel, ...b.args])));
  for (const f of sorted) T.add({ rel: f.rel, args: f.args, basis: "base" });
  const derivations = new Map(); // fact key -> Map(derivation id -> derivation)
  const strata = [...new Set(rulesDoc.rules.map((r) => r.stratum))].sort((a, b) => a - b);
  const stratumOf = new Map(rulesDoc.rules.map((r) => [r.head.rel, r.stratum]));

  /** All ground instantiations of `rule` where body atom `pin` (if given) ranges over `deltaFacts` only. */
  const fire = (rule, pin, deltaFacts, sink) => {
    const rec = (i, env, prem) => {
      if (i === rule.body.length) { sink(rule, env, prem); return; }
      const atom = rule.body[i]; const pattern = subst(atom.args, env);
      if (atom.neg) {
        for (const t of pattern) if (isVar(t)) throw new Error(`unsafe negation in ${rule.name}: ${t} unbound`);
        if (!T.matches(atom.rel, pattern)) rec(i + 1, env, [...prem, { absent: [atom.rel, ...pattern] }]);
        return;
      }
      const source = i === pin ? deltaFacts : [...T.candidates(atom.rel, pattern).values()];
      const cands = source.filter((f) => f.rel === atom.rel).sort((a, b) => cmpKey(key([a.rel, ...a.args]), key([b.rel, ...b.args])));
      for (const f of cands) { const e2 = unify(pattern, f.args, env); if (e2) rec(i + 1, e2, [...prem, [f.rel, ...f.args]]); }
    };
    rec(0, {}, []);
  };
  const record = (rule, env, premises) => {
    const conclusion = [rule.head.rel, ...subst(rule.head.args, env)];
    const k = key(conclusion);
    const vars = new Set(); for (const a of [...rule.head.args, ...rule.body.flatMap((b) => b.args)]) if (isVar(a)) vars.add(a);
    const bindings = Object.fromEntries([...vars].sort().filter((v) => v in env).map((v) => [v, env[v]]));
    const id = "sha256:" + sha256Hex(canonicalBytesG0({ rule: `${ruleSemId}#${rule.name}`, conclusion, premises }));
    if (!derivations.has(k)) derivations.set(k, new Map());
    const d = derivations.get(k); if (!d.has(id)) d.set(id, { id, rule: `${ruleSemId}#${rule.name}`, conclusion, premises, bindings, depth: 0 });
    return { conclusion, k };
  };

  for (const s of strata) {
    const rules = rulesDoc.rules.filter((r) => r.stratum === s);
    const recursive = new Set(rules.map((r) => r.head.rel));
    // round 0: full join over everything present (base + lower strata; this stratum's relations are still empty)
    let delta = [];
    const sink = (rule, env, prem) => { const { conclusion } = record(rule, env, prem); const f = { rel: conclusion[0], args: conclusion.slice(1), basis: "derived" }; if (T.add(f)) delta.push(f); };
    for (const r of rules) fire(r, -1, null, sink);
    // semi-naive rounds: one body position of this stratum bound to the last delta, the rest to the full table
    while (delta.length) {
      const last = delta.slice().sort((a, b) => cmpKey(key([a.rel, ...a.args]), key([b.rel, ...b.args]))); delta = [];
      for (const r of rules) r.body.forEach((atom, i) => { if (!atom.neg && recursive.has(atom.rel)) fire(r, i, last, sink); });
    }
  }
  // depth to a fixpoint: base 0; derived = min over derivations of 1 + max positive-premise depth
  const depth = new Map(); for (const [k, f] of T.byKey) if (f.basis === "base") depth.set(k, 0);
  const depthOf = (atom) => depth.get(key(atom));
  let changed = true;
  while (changed) {
    changed = false;
    for (const [k, ds] of derivations) {
      let best = depth.has(k) ? depth.get(k) : Infinity;
      for (const d of ds.values()) { let m = 0, ok = true; for (const p of d.premises) { if (p && typeof p === "object" && !Array.isArray(p)) continue; const pd = depthOf(p); if (pd === undefined) { ok = false; break; } m = Math.max(m, pd); } if (ok) { d.depth = 1 + m; if (d.depth < best) best = d.depth; } }
      if (best !== (depth.has(k) ? depth.get(k) : Infinity)) { depth.set(k, best); changed = true; }
    }
  }
  const facts = new Map(); const derived = []; const by_rule = {}; const ids = [];
  for (const k of [...T.byKey.keys()].sort(cmpKey)) {
    const f = T.byKey.get(k);
    if (f.basis === "base") { facts.set(k, { rel: f.rel, args: f.args, basis: "base", depth: 0, derivations: [] }); continue; }
    const all = [...(derivations.get(k) || new Map()).values()].filter((d) => d.depth > 0).sort((a, b) => a.depth - b.depth || Buffer.compare(canonicalBytesG0(a), canonicalBytesG0(b)));
    const kept = all.slice(0, maxAlt);
    const entry = { rel: f.rel, args: f.args, basis: "derived", depth: depth.get(k), derivations: kept };
    facts.set(k, entry); derived.push(entry); by_rule[f.rel] = (by_rule[f.rel] || 0) + 1; for (const d of kept) ids.push(d.id);
  }
  const digest = "sha256:" + sha256Hex(canonicalBytesG0(ids.slice().sort(cmpKey)));
  return { facts, derived, digest, by_rule, evaluator: EVALUATOR_ID, trvm_derivation: false, strata: strata.length };
}
