/* eval.test.mjs — the evaluator and the independent checker on a SYNTHETIC program and fact set (no projections, no git). */
import { test } from "node:test";
import assert from "node:assert/strict";
import { evaluate } from "../lib/eval.mjs";
import { checkAll, checkDerivation, makeFactStore } from "../lib/check.mjs";
import { factsFromRecords } from "../lib/facts.mjs";
import { checkStratification, checkSafety } from "../lib/rules.mjs";
import { canonicalBytesG0 } from "../lib/canon.mjs";

const key = (v) => canonicalBytesG0(v).toString("utf8");
const RULESET = "g0rule-" + "ab".repeat(32);
const doc = {
  ruleset: "G0-RULESET-v1", version: 2,
  facts: { node: { arity: 2, doc: "" }, attr: { arity: 3, doc: "" }, rel: { arity: 4, doc: "" }, rattr: { arity: 3, doc: "" }, asrt: { arity: 3, doc: "" }, aattr: { arity: 3, doc: "" } },
  rules: [
    { name: "r2_direct", stratum: 0, head: { rel: "reduces_to", args: ["A", "B"] }, body: [{ rel: "rel", args: ["_", "REDUCES_TO", "A", "B"] }] },
    { name: "r2_trans", stratum: 0, head: { rel: "reduces_to", args: ["A", "C"] }, body: [{ rel: "reduces_to", args: ["A", "B"] }, { rel: "rel", args: ["_", "REDUCES_TO", "B", "C"] }] },
    { name: "not_primitive", stratum: 0, head: { rel: "not_primitive", args: ["S"] }, body: [{ rel: "reduces_to", args: ["S", "_"] }] },
    { name: "superseded", stratum: 0, head: { rel: "superseded", args: ["X"] }, body: [{ rel: "rel", args: ["_", "SUPERSEDES", "_", "X"] }] },
    { name: "supports", stratum: 0, head: { rel: "supports", args: ["W", "C"] }, body: [{ rel: "rel", args: ["R", "WITNESSES", "W", "C"] }, { rel: "asrt", args: ["A", "R", "_"] }, { rel: "aattr", args: ["A", "outcome", "pass"] }] },
    { name: "has_exec", stratum: 0, head: { rel: "has_exec", args: ["C"] }, body: [{ rel: "rel", args: ["R", "WITNESSES", "W", "C"] }, { rel: "node", args: ["W", "RECEIPT"] }, { rel: "attr", args: ["W", "verified", true] }, { rel: "asrt", args: ["A", "R", "_"] }, { rel: "aattr", args: ["A", "executed", true] }] },
    { name: "current", stratum: 1, head: { rel: "current", args: ["X"] }, body: [{ rel: "node", args: ["X", "_"] }, { rel: "superseded", args: ["X"], neg: true }] },
    { name: "unwitnessed", stratum: 1, head: { rel: "unwitnessed", args: ["X"] }, body: [{ rel: "node", args: ["X", "CLAIM"] }, { rel: "rel", args: ["_", "WITNESSES", "_", "X"], neg: true }] },
  ],
};
checkStratification(doc); checkSafety(doc);
const nodes = [
  { lid: "obligation:t:a", kind: "OBLIGATION", attrs: {} }, { lid: "obligation:t:b", kind: "OBLIGATION", attrs: {} }, { lid: "obligation:t:c", kind: "OBLIGATION", attrs: {} },
  { lid: "claim:t:c1", kind: "CLAIM", attrs: { token_family: "TESTED" } }, { lid: "claim:t:c2", kind: "CLAIM", attrs: {} },
  { lid: "receipt:t:w1", kind: "RECEIPT", attrs: { verified: true } }, { lid: "transition:t:t1", kind: "EVIDENCE_STATE_TRANSITION", attrs: {} },
];
const relations = [
  { lid: "rel:g0:REDUCES_TO:obligation:t:a:obligation:t:b", kind: "REDUCES_TO", source: "obligation:t:a", target: "obligation:t:b", attrs: {} },
  { lid: "rel:g0:REDUCES_TO:obligation:t:b:obligation:t:c", kind: "REDUCES_TO", source: "obligation:t:b", target: "obligation:t:c", attrs: {} },
  { lid: "rel:g0:REDUCES_TO:obligation:t:c:obligation:t:a", kind: "REDUCES_TO", source: "obligation:t:c", target: "obligation:t:a", attrs: {} },
  { lid: "rel:g0:WITNESSES:receipt:t:w1:claim:t:c1", kind: "WITNESSES", source: "receipt:t:w1", target: "claim:t:c1", attrs: {} },
  // D-037: SUPERSEDES holds between comparable kinds only — a synthetic claim → claim replacement (c1 supersedes c2)
  { lid: "rel:g0:SUPERSEDES:claim:t:c1:claim:t:c2", kind: "SUPERSEDES", source: "claim:t:c1", target: "claim:t:c2", attrs: {} },
  { lid: "rel:g0:STATE_TRANSITION_OF:transition:t:t1:claim:t:c2", kind: "STATE_TRANSITION_OF", source: "transition:t:t1", target: "claim:t:c2", attrs: { typed: true } },
];
const assertions = [
  { lid: "asrt:g0:rel:g0:WITNESSES:receipt:t:w1:claim:t:c1:loc:t:x:p1", subject: "rel:g0:WITNESSES:receipt:t:w1:claim:t:c1", location: "loc:t:x:p1", attrs: { role: "sensitivity", outcome: "pass", executed: true } },
  { lid: "asrt:g0:rel:g0:WITNESSES:receipt:t:w1:claim:t:c1:loc:t:x:p2", subject: "rel:g0:WITNESSES:receipt:t:w1:claim:t:c1", location: "loc:t:x:p2", attrs: { role: "repair", outcome: "pass", executed: false } },
];
const base = factsFromRecords({ nodes, relations, assertions });
const shuffled = (arr, seed) => { const a = arr.slice(); let s = (seed >>> 0) || 1; for (let i = a.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) >>> 0; const j = s % (i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const ev = evaluate(doc, RULESET, base);
const get = (rel, ...args) => ev.facts.get(key([rel, ...args]));

test("facts: records project to sorted, deduplicated base facts with asrt/aattr", () => {
  assert.ok(base.some((f) => f.rel === "asrt" && f.args[1] === "rel:g0:WITNESSES:receipt:t:w1:claim:t:c1"));
  assert.ok(base.some((f) => f.rel === "aattr" && f.args[1] === "outcome" && f.args[2] === "pass"));
  assert.deepEqual(base.map((f) => key([f.rel, ...f.args])), base.map((f) => key([f.rel, ...f.args])).slice().sort());
  assert.equal(factsFromRecords({ nodes: [nodes[0], nodes[0]] }).length, 1);
});

test("determinism: a seeded shuffle of the base facts gives the identical digest and derivations", () => {
  for (const seed of [7, 987654321, 42]) { const e2 = evaluate(doc, RULESET, shuffled(base, seed)); assert.equal(e2.digest, ev.digest); assert.deepEqual(e2.derived, ev.derived); }
});

test("termination and closure over a cycle: every pair is reachable, including each node to itself; not_primitive covers all three", () => {
  for (const x of ["a", "b", "c"]) for (const y of ["a", "b", "c"]) assert.ok(get("reduces_to", `obligation:t:${x}`, `obligation:t:${y}`), `${x}→${y}`);
  assert.equal(ev.by_rule.reduces_to, 9); assert.equal(ev.by_rule.not_primitive, 3);
  const aa = get("reduces_to", "obligation:t:a", "obligation:t:a"); assert.equal(aa.depth, 3, "a→b (1), a→c (2), a→a (3)");
});

test("stratified negation: current excludes exactly the superseded node and records an {absent} premise; wildcard negation works", () => {
  const cur = ev.derived.filter((f) => f.rel === "current").map((f) => f.args[0]);
  assert.ok(!cur.includes("claim:t:c2") && cur.includes("claim:t:c1") && cur.length === nodes.length - 1);
  const d = get("current", "claim:t:c1").derivations[0];
  assert.deepEqual(d.premises[1], { absent: ["superseded", "claim:t:c1"] });
  const un = ev.derived.filter((f) => f.rel === "unwitnessed").map((f) => f.args[0]); assert.deepEqual(un, ["claim:t:c2"]);
  assert.deepEqual(get("unwitnessed", "claim:t:c2").derivations[0].premises[1], { absent: ["rel", "_", "WITNESSES", "_", "claim:t:c2"] });
});

test("two assertions on one relation: ONE derived fact with TWO derivations whose premises name different assertions", () => {
  const s = get("supports", "receipt:t:w1", "claim:t:c1");
  assert.ok(s); assert.equal(s.derivations.length, 2); assert.equal(ev.by_rule.supports, 1);
  const asrts = s.derivations.map((d) => d.premises[1][1]).sort(); assert.deepEqual(asrts, [assertions[0].lid, assertions[1].lid]);
  assert.notEqual(s.derivations[0].id, s.derivations[1].id);
  // has_exec joins a boolean constant on the RECEIPT node and `executed: true` on the assertion — only the first assertion qualifies
  const h = get("has_exec", "claim:t:c1"); assert.equal(h.derivations.length, 1); assert.equal(h.derivations[0].premises[3][1], assertions[0].lid);
});

test("maxAlt caps the alternatives, minimal depth first, ties by bytes", () => {
  const e1 = evaluate(doc, RULESET, base, { maxAlt: 1 });
  const aa = e1.facts.get(key(["reduces_to", "obligation:t:a", "obligation:t:a"]));
  assert.equal(aa.derivations.length, 1); assert.equal(aa.derivations[0].depth, aa.depth);
  const full = get("reduces_to", "obligation:t:a", "obligation:t:a").derivations;
  assert.ok(full.length >= 1 && full.length <= 4);
  for (let i = 1; i < full.length; i++) assert.ok(full[i - 1].depth < full[i].depth || (full[i - 1].depth === full[i].depth && Buffer.compare(canonicalBytesG0(full[i - 1]), canonicalBytesG0(full[i])) < 0));
  assert.notEqual(e1.digest, ev.digest, "the digest covers the kept derivations");
});

test("checkAll accepts the whole evaluation; every derived fact is basis derived and the result says trvm_derivation false", () => {
  const c = checkAll(doc, RULESET, ev); assert.equal(c.ok, true); assert.deepEqual(c.failures, []); assert.ok(c.checked >= ev.derived.length);
  assert.equal(ev.trvm_derivation, false); assert.equal(ev.evaluator, "graphonomous.g0.eval.v0");
  for (const f of ev.derived) { assert.equal(f.basis, "derived"); assert.ok(f.depth >= 1); assert.ok(f.derivations.length >= 1); }
});

test("tampering is refused: conclusion, premise, binding, rule name, forged absence, depth, id", () => {
  const store = makeFactStore(ev.facts);
  const good = get("supports", "receipt:t:w1", "claim:t:c1").derivations[0];
  assert.equal(checkDerivation(doc, RULESET, good, store).ok, true);
  const mut = (f) => { const d = JSON.parse(JSON.stringify(good)); f(d); return checkDerivation(doc, RULESET, d, store); };
  let r = mut((d) => { d.conclusion[2] = "claim:t:c2"; }); assert.equal(r.ok, false); assert.match(r.problems.join(), /head .* != conclusion|id .* does not recompute/);
  r = mut((d) => { d.premises[0] = ["rel", "rel:g0:WITNESSES:receipt:t:w1:claim:t:c9", "WITNESSES", "receipt:t:w1", "claim:t:c1"]; }); assert.equal(r.ok, false); assert.match(r.problems.join(), /is not a fact/);
  r = mut((d) => { d.bindings.C = "claim:t:c2"; }); assert.equal(r.ok, false); assert.match(r.problems.join(), /head .* != conclusion/);
  r = mut((d) => { d.rule = RULESET + "#has_exec"; }); assert.equal(r.ok, false);
  r = mut((d) => { d.rule = "g0rule-" + "00".repeat(32) + "#supports"; }); assert.equal(r.ok, false); assert.match(r.problems.join(), /not the program/);
  r = mut((d) => { d.depth = 7; }); assert.equal(r.ok, false); assert.match(r.problems.join(), /depth/);
  r = mut((d) => { d.id = "sha256:" + "00".repeat(32); }); assert.equal(r.ok, false); assert.match(r.problems.join(), /does not recompute/);
  // a forged absence: claim the WITNESSES relation is absent for c1, which IS witnessed
  const cur = get("current", "claim:t:c1").derivations[0];
  const forged = JSON.parse(JSON.stringify(cur)); forged.rule = RULESET + "#unwitnessed"; forged.conclusion = ["unwitnessed", "claim:t:c1"]; forged.premises = [["node", "claim:t:c1", "CLAIM"], { absent: ["rel", "_", "WITNESSES", "_", "claim:t:c1"] }];
  forged.id = "sha256:" + require_id(forged);
  const fr = checkDerivation(doc, RULESET, forged, store); assert.equal(fr.ok, false); assert.match(fr.problems.join(), /so it is not absent/);
});
import { sha256Hex } from "../lib/canon.mjs";
function require_id(d) { return sha256Hex(canonicalBytesG0({ rule: d.rule, conclusion: d.conclusion, premises: d.premises })); }

test("the derivation id binds exactly {rule, conclusion, premises}", () => {
  const d = get("not_primitive", "obligation:t:a").derivations[0];
  assert.equal(d.id, "sha256:" + require_id(d));
  const e2 = evaluate(doc, RULESET, base, { maxAlt: 1 });
  assert.equal(e2.facts.get(key(["not_primitive", "obligation:t:a"])).derivations[0].id, d.id, "the same proof has the same id under another cap");
});
