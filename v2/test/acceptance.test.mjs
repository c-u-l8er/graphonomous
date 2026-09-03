/* acceptance.test.mjs — the A1–A7 the G0.5 page shows are the A1–A7 a test asserts.
 *
 * GPT v5 §10.7 requires the seven acceptance questions to be reachable from the read-only UI, and §10.5 forbids the
 * screen from showing an answer that is not the deterministic one. `lib/acceptance.mjs` is the single definition; the
 * page renders what it returned in Node, `g0 acceptance` prints it, and this file pins the answers. If someone edits a
 * question to make the demo prettier, these numbers move and the build fails. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { Projections } from "../lib/query.mjs";
import { runAcceptance, QUESTIONS, leaves, S6, S5, R08, R085, R086 } from "../lib/acceptance.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const P = new Projections([resolve(V, "projections/baseline"), resolve(V, "projections/historical")]);
const b = P.as_of("snapshot:g0:baseline-ba4e625"), h = P.as_of("snapshot:g0:historical-699fbc2");
const byId = (rs, id) => rs.find((r) => r.id === id);
const stepValue = (r, i) => r.steps[i].value;

test("acceptance: all seven questions answer on baseline+historical, and each is one of the six query functions", () => {
  const rs = runAcceptance({ primary: b, compare: h });
  assert.equal(rs.length, 7);
  assert.deepEqual(rs.map((r) => r.id), ["A1", "A2", "A3", "A4", "A5", "A6", "A7"]);
  for (const r of rs) assert.ok(r.answered, `${r.id}: ${r.reason}`);
  for (const r of rs) for (const s of r.steps) assert.match(s.call, /^(node|neighbors|path|facts|explain|as_of|leaves|for each|—)/, `${r.id}: ${s.call}`);
  for (const r of rs) assert.equal(r.snapshot, b.snapshot, "every answer names the root it came from");
});

test("acceptance: a question that needs two pins is NOT answered from one — it refuses, it does not guess", () => {
  const one = runAcceptance({ primary: b });
  assert.equal(byId(one, "A2").answered, false);
  assert.equal(byId(one, "A4").answered, false);
  assert.match(byId(one, "A2").reason, /needs a compare snapshot/);
  for (const id of ["A1", "A3", "A5", "A6", "A7"]) assert.ok(byId(one, id).answered, id);
});

test("A1 answers exactly what test/query.test.mjs asserts: one not_primitive, depth 2, bottoming out in the resolved_candidates pointer", () => {
  const r = byId(runAcceptance({ primary: b, compare: h }), "A1");
  assert.deepEqual(stepValue(r, 0).map((f) => f.args[0]), [S6]);
  const ex = stepValue(r, 1);
  assert.equal(ex.basis, "derived"); assert.equal(ex.trvm_derivation, false); assert.equal(ex.depth, 2);
  assert.deepEqual(stepValue(r, 2), ["obligation:inv:S1"]);
  const locs = stepValue(r, 3);
  assert.ok(locs.some((l) => l.location.fragment === "/resolved_candidates/S6?" && l.location.precision === "pointer"));
  assert.ok(leaves(ex).every((l) => l.basis === "base"), "a positive derivation, never failure-to-find");
});

test("A2 is snapshot-relative: 1 OPENS at the baseline, 5 at the historical pin, and the one relation carries both registries", () => {
  const r = byId(runAcceptance({ primary: b, compare: h }), "A2");
  assert.equal(stepValue(r, 0).length, 1);
  assert.equal(stepValue(r, 1).length, 5);
  assert.deepEqual(stepValue(r, 2).map((l) => l.split(":").pop()).sort(), ["F36", "F37"]);
  assert.deepEqual(stepValue(r, 3).assertions.map((a) => a.asserted_by.split(":")[1]).sort(), ["crosswalk", "evstate"]);
  const flipped = byId(runAcceptance({ primary: h, compare: b }), "A2");
  assert.equal(stepValue(flipped, 0).length, 5, "asking at the other pin gives the other pin's answer, not a merge");
});

test("A3 finds E-48's executed, hash-verified receipt through the assertion's executed flag", () => {
  const r = byId(runAcceptance({ primary: b, compare: h }), "A3");
  const kinds = Object.fromEntries(stepValue(r, 0).map((e) => [e.other.split(":").pop(), e.kind]));
  assert.equal(kinds["E-48"], "IMPLEMENTS"); assert.equal(kinds["E-50a"], "DERIVES_FROM");
  assert.deepEqual(stepValue(r, 1).map((f) => f.args[0].split(":").pop()).sort(), ["E-13b", "E-14", "E-15", "E-48"]);
  const d = stepValue(r, 2).derivations[0];
  assert.deepEqual(d.premises[4].fact.slice(2), ["executed", true]);
  assert.equal(d.premises[4].source.attrs.sensitivity_type, "pre-fix-fail");
});

test("A4 shows the witness moving between pins without deleting the old answer", () => {
  const r = byId(runAcceptance({ primary: b, compare: h }), "A4");
  assert.deepEqual(stepValue(r, 0), ["claim:crosswalk:E-14"]);
  assert.deepEqual(stepValue(r, 1), ["claim:crosswalk:E-13b", "claim:crosswalk:E-14"]);
  assert.deepEqual(stepValue(r, 2), ["claim:crosswalk:E-13b"]);
  assert.deepEqual(stepValue(r, 3).assertions.map((a) => a.attrs.role).sort(), ["repair", "sensitivity"]);
});

test("A5: two MECHANISM nodes, 8 mechanism_of, each mechanism located at a `symbol`-precision source location", () => {
  const r = byId(runAcceptance({ primary: b, compare: h }), "A5");
  assert.deepEqual(stepValue(r, 0), ["mechanism:computedriven:LifecycleAdmission", "mechanism:computedriven:reconstruct"]);
  assert.equal(stepValue(r, 1).length, 8);
  for (const m of stepValue(r, 2)) assert.equal(m.location.precision, "symbol", m.mechanism);
});

test("A6: the three-way partition is 4 / 0 / 18 over 22 tested claims, and the undecidable one names its absence", () => {
  const r = byId(runAcceptance({ primary: b, compare: h }), "A6");
  assert.equal(stepValue(r, 0).length, 4);
  assert.equal(stepValue(r, 1).length, 0, "no crosswalk record types its receipts: absence is never decidable here");
  assert.equal(stepValue(r, 2).length, 18);
  assert.equal(stepValue(r, 3).length, 22);
  assert.equal(stepValue(r, 5).length, 1);
  assert.equal(stepValue(r, 5)[0][0], "has_exec_receipt");
});

test("A7 is exhaustive and holds: every relation and every derived fact bottoms out in a pinned source location", () => {
  for (const [g, rels, facts] of [[b, 588, 404], [h, 566, 393]]) {
    const r = byId(runAcceptance({ primary: g }), "A7");
    assert.equal(stepValue(r, 0).relations, rels);
    assert.equal(stepValue(r, 0).assertions_without_a_pinned_location, 0);
    assert.equal(stepValue(r, 2).facts, facts);
    assert.equal(stepValue(r, 2).base_leaves_without_a_source, 0);
    assert.match(stepValue(r, 3), /^every relation and every derived fact bottoms out/);
  }
});

test("every question declares what it proves, and no question mutates the graph it is given", () => {
  for (const q of QUESTIONS) { assert.ok(q.proves.length > 20, q.id); assert.ok(q.question.endsWith("?"), q.id); }
  const before = [b.nodes.size, b.relations.size, b.assertions.size, b.faults.length, b.derived.facts.length];
  runAcceptance({ primary: b, compare: h });
  assert.deepEqual([b.nodes.size, b.relations.size, b.assertions.size, b.faults.length, b.derived.facts.length], before, "read-only");
});
