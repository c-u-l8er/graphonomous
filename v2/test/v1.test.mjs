/* v1.test.mjs — `graphonomous.semantic.v1` as built (D-062/D-064, GPT v5 §7).
 *
 * The claims this file pins are the ones a successor profile has to earn:
 *   1. v0 DID NOT MOVE — three golden worlds reproduce, at a WRL commit that gained a row.
 *   2. the v1 projection is a strict SUPERSET of the v0 multi projection, record for record;
 *   3. the delta is EXACTLY the audit's 3 roles / 1 kind / 10 pairs, with the measured counts;
 *   4. the DEFERRED targets are deferred — attributes, no edge — and the reason is in the record;
 *   5. a statement's REVISION identity is world-independent while its ALLOCATION is world-scoped;
 *   6. the two worlds' snapshot commitment is byte-identical and the claim still moves.
 *
 * Everything here reads the SHIPPED artifacts. Nothing re-projects. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { loadProjection } from "../lib/evaluation.mjs";
import { loadProfile, sealProjection, WRL_PIN } from "../lib/wrl_world.mjs";
import * as V2 from "../../../WRL/relation-v2.js";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const P = (n) => resolve(V, "projections", n);
const j = (f) => JSON.parse(readFileSync(f, "utf8"));
const ids = (n) => j(join(P(n), "world/identities.json"));
const bundle = (n) => j(join(P(n), "certificate/bundle.json"));
const V0_GOLDEN = {
  baseline: "sem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be",
  historical: "sem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23",
  multi: "sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea",
};

test("(1) v0 did not move: the three golden worlds reproduce at a WRL commit that GAINED a profile row", async () => {
  assert.equal(WRL_PIN.commit, "53e5e8995913995189f7017d2a94351ff69d5b31");
  for (const [name, sem] of Object.entries(V0_GOLDEN)) {
    const sealed = await sealProjection(loadProjection(P(name)));   // no profile argument: the v0 default
    assert.equal(sealed.sem, sem, `${name}: the frozen v0 world`);
    assert.equal(sealed.profile_id, "graphonomous.semantic.v0");
    assert.equal(readFileSync(join(P(name), "world/SEM"), "utf8").trim(), sem, "and the shipped SEM says the same");
  }
  const row = V2.V2_PROFILES["graphonomous.semantic.v0"];
  assert.equal(Object.keys(row.roles).length, 21);
  assert.equal(Object.keys(row.endpoints).length, 31);
  assert.equal(Object.values(row.endpoints).reduce((n, v) => n + v.length, 0), 92, "21/31/92 is the frozen contract");
});

test("(2) the v1 projection is a STRICT SUPERSET of the v0 multi projection — every lid present, no kind changed", () => {
  const v0 = loadProjection(P("multi")), v1 = loadProjection(P("multi-v1"));
  const n0 = new Map(v0.nodes.map((n) => [n.lid, n])), n1 = new Map(v1.nodes.map((n) => [n.lid, n]));
  const r0 = new Map(v0.relations.map((r) => [r.lid, r])), r1 = new Map(v1.relations.map((r) => [r.lid, r]));
  for (const [lid, n] of n0) { assert.ok(n1.has(lid), `node ${lid} vanished`); assert.equal(n1.get(lid).kind, n.kind, lid); }
  for (const [lid, r] of r0) {
    assert.ok(r1.has(lid), `relation ${lid} vanished`);
    assert.equal(r1.get(lid).kind, r.kind); assert.equal(r1.get(lid).source, r.source); assert.equal(r1.get(lid).target, r.target);
  }
  assert.equal(n0.size, 778); assert.equal(n1.size, 932);
  assert.equal(r0.size, 1574); assert.equal(r1.size, 2007);
  /* and the new layer introduced no new fault: the same 86, code for code */
  const codes = (p) => Object.fromEntries(Object.entries(p.faults.reduce((a, f) => ((a[f.code] = (a[f.code] || 0) + 1), a), {})).sort());
  assert.equal(v1.faults.length, 86);
  assert.deepEqual(codes(v1), codes(v0), "every reference in the argument/defeater layer resolved");
});

test("(3) the delta is exactly the audit's 3 roles / 1 kind / 10 pairs, with its measured counts", () => {
  const v0 = loadProjection(P("multi")), v1 = loadProjection(P("multi-v1"));
  const known = new Set(v0.nodes.map((n) => n.lid));
  const newNodes = v1.nodes.filter((n) => !known.has(n.lid));
  const byRole = newNodes.reduce((a, n) => ((a[n.kind] = (a[n.kind] || 0) + 1), a), {});
  assert.deepEqual(byRole, { ARGUMENT: 27, DEFEATER: 68, FINDING: 46, INSTRUMENT: 12, WITNESS: 1 },
    "27 arguments, 68 defeaters, 12 instruments, 46 incidents-as-FINDING, and the ONE witness node no claim happened to mint (G0F_V1_AUDIT §3)");

  const knownR = new Set(v0.relations.map((r) => r.lid));
  const newRels = v1.relations.filter((r) => !knownR.has(r.lid));
  const kindOf = new Map(v1.nodes.map((n) => [n.lid, n.kind]));
  const pair = (r) => `${r.kind} [${kindOf.get(r.source)}, ${kindOf.get(r.target)}]`;
  const pairs = newRels.reduce((a, r) => ((a[pair(r)] = (a[pair(r)] || 0) + 1), a), {});

  /* the ten pairs v1 declares, each with the count the audit measured */
  assert.equal(pairs["SUPPORTS [ARGUMENT, CLAIM]"], 25);
  assert.equal(pairs["WITNESSES [WITNESS, ARGUMENT]"], 24);
  assert.equal(pairs["ASSUMES [ARGUMENT, ASSUMPTION]"], 23);
  assert.equal(pairs["ASSUMES [INSTRUMENT, ASSUMPTION]"], 17);
  assert.equal(pairs["ATTACKS [DEFEATER, CLAIM]"], 3);
  assert.equal(pairs["ATTACKS [DEFEATER, ARGUMENT]"], 12);
  assert.equal(pairs["ATTACKS [DEFEATER, ASSUMPTION]"], 6);
  assert.equal(pairs["ATTACKS [DEFEATER, INSTRUMENT]"], 5);
  assert.equal(pairs["ATTACKS [DEFEATER, RECEIPT]"], 5);
  assert.equal(pairs["DISCHARGED_BY [ASSUMPTION, CLAIM]"], 2, "gated on the source's own discharge status");
  assert.equal(newRels.filter((r) => r.kind === "ATTACKS").length, 31, "3+12+6+5+5 — and nothing else");

  /* the pairs reached for free, because v0 already declares them */
  assert.equal(pairs["OPENS [ROUND, FINDING]"], 46);
  assert.equal(pairs["CLOSES [ROUND, FINDING]"], 46);
  const v1row = V2.V2_PROFILES["graphonomous.semantic.v1"];
  assert.equal(Object.keys(v1row.roles).length, 24);
  assert.equal(Object.keys(v1row.endpoints).length, 32);
  assert.equal(Object.values(v1row.endpoints).reduce((n, v) => n + v.length, 0), 102, "92 + 10");
});

test("(4) the DEFERRED defeater targets are deferred: attributes and a stated reason, and NO edge", () => {
  const v1 = loadProjection(P("multi-v1"));
  const defeaters = v1.nodes.filter((n) => n.kind === "DEFEATER");
  assert.equal(defeaters.length, 68);
  const byTarget = defeaters.reduce((a, n) => ((a[n.attrs.target_type] = (a[n.attrs.target_type] || 0) + 1), a), {});
  assert.deepEqual(byTarget, { argument: 12, assumption: 6, claim: 3, claim_evidence: 3, consumption_rule: 34, evidence: 5, receipt: 5 });

  const attacks = new Set(v1.relations.filter((r) => r.kind === "ATTACKS").map((r) => r.source));
  for (const n of defeaters) {
    const deferred = ["consumption_rule", "claim_evidence"].includes(n.attrs.target_type);
    assert.equal(attacks.has(n.lid), !deferred, `${n.lid} (${n.attrs.target_type})`);
    if (!deferred) continue;
    assert.ok(n.attrs.deferred_target_reason, `${n.lid} must SAY why it has no edge`);
    if (n.attrs.target_type === "consumption_rule") {
      /* the code coordinates are kept verbatim — the evidence survives the deferral */
      assert.ok(n.attrs.target_file && n.attrs.target_revision && n.attrs.target_digest && n.attrs.target_digest_bits, n.lid);
      assert.ok(n.attrs.target_symbol || n.attrs.target_section, n.lid);
      assert.match(n.attrs.deferred_target_reason, /no rule identity/);
    } else {
      assert.ok(n.attrs.target_ref, n.lid);
      assert.match(n.attrs.deferred_target_reason, /attacks the SUPPORT/);
    }
  }
  /* and no role was invented to make the counts fit */
  const roles = new Set(v1.nodes.map((n) => n.kind));
  for (const forbidden of ["CONSUMPTION_RULE", "RULE", "TARGET"]) assert.ok(!roles.has(forbidden), forbidden);
  assert.ok(!v1.relations.some((r) => r.kind === "ATTACKS" && r.target.startsWith("loc:")), "no ATTACKS aims at a SOURCE_LOCATION");
});

test("(5) a statement's REVISION identity is world-independent; its ALLOCATION is world-scoped", () => {
  const a = ids("multi"), b = ids("multi-v1");
  assert.equal(a.profile_id, "graphonomous.semantic.v0");
  assert.equal(b.profile_id, "graphonomous.semantic.v1");
  assert.notEqual(a.sem, b.sem, "a different profile is a different world");
  const A = new Map(a.relations.map((r) => [r.relation_name, r])), B = new Map(b.relations.map((r) => [r.relation_name, r]));
  const shared = [...A.keys()].filter((n) => B.has(n));
  assert.equal(shared.length, 1574, "every v0 statement lid reappears in v1 — lids do not carry the profile");
  assert.equal(shared.filter((n) => A.get(n).rev === B.get(n).rev).length, 1574, "same statement, same revision, in both worlds");
  assert.equal(shared.filter((n) => A.get(n).rel === B.get(n).rel).length, 0, "and a different allocation in each");
  assert.equal(b.relations.length - shared.length, 433);
  for (const r of b.relations) { assert.match(r.rel, /^rel-[0-9a-f]{64}$/); assert.match(r.rev, /^rev-[0-9a-f]{64}$/); assert.equal(r.minted_by, "wrl-kernel@53e5e89"); }
});

test("(6) the two multi worlds commit to the SAME source bytes, and the claim still moves", () => {
  const v0 = bundle("multi").claim, v1 = bundle("multi-v1").claim;
  assert.equal(v0.snapshot_commitment, v1.snapshot_commitment, "same six sources, same 101 files: gsnap- is byte-identical");
  assert.equal(v0.snapshot_commitment, "gsnap-2e5252881fc3192a912d95b0b8ccf010be619ece8cb9a3dc6ccb0ddfd35a944e");
  assert.notEqual(v0.snapshot_id, v1.snapshot_id);
  assert.notEqual(v0.projection_root, v1.projection_root, "a third adapter ran");
  assert.notEqual(v0.adapter_contract_id, v1.adapter_contract_id, "and the claim names which adapters ran");
  assert.notEqual(v0.projection_claim_sem_id, v1.projection_claim_sem_id);
  /* the point: a claim binds MORE than the source bytes */
  assert.equal(v0.schema_set_id, v1.schema_set_id, "both were built under the same code");
  for (const c of [v0, v1]) assert.deepEqual(c.scope, {
    kind: "PROJECTION_RECONSTRUCTION_IDENTITY", quantifier: "OVER_THE_PINNED_SOURCE_SET",
    truth_claimed: false, evidence_sufficiency_claimed: false, state_promoted: false,
    registry_written: false, trvm_derivation: false,
  });
});

test("(7) the submitted v1 declaration and WRL's admitted row agree facet for facet", () => {
  const sub = loadProfile("graphonomous.semantic.v1"), row = V2.V2_PROFILES["graphonomous.semantic.v1"];
  assert.deepEqual(Object.keys(row.roles), sub.roles.kinds);
  assert.deepEqual(Object.keys(row.endpoints).sort(), [...sub.relation_signatures.kinds].sort());
  const theirs = Object.fromEntries(Object.entries(sub.endpoint_constraints).filter(([k]) => k !== "note"));
  const norm = (o) => JSON.stringify(Object.keys(o).sort().map((k) => [k, o[k].map((p) => p.join(">")).sort()]));
  assert.equal(norm(row.endpoints), norm(theirs));
  assert.equal(row.rulepack_id, sub.semantic_policies.rulepack_id);
  assert.equal(row.domain, sub.relation_signatures.domain);
  /* v1 admits everything v0 admits — the superset is declared, not hoped for */
  const v0row = V2.V2_PROFILES["graphonomous.semantic.v0"];
  for (const [k, ps] of Object.entries(v0row.endpoints))
    for (const p of ps) assert.ok((row.endpoints[k] ?? []).some((q) => q[0] === p[0] && q[1] === p[1]), `${k} ${p.join(">")}`);
});
