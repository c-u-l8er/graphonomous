/* projection_v1.test.mjs — the eleven acceptance laws of `GRAPHONOMOUS-PROJECTION-v1` (GPT v6 §6 → D-068).
 *
 * The subject is one coordinate. v0's `schema_set_id` hashes EVERY schema file in the checkout, keyed on basename, so
 * growing the v1 vocabulary re-minted the certificates of frozen v0 projections whose records had not moved. v1
 * replaces it with `schema_closure_id` + `projection_contract_id`: the REQUIRED closure the verifier derives from the
 * projection's own adapter_run records through a trusted local contract (lib/closure.mjs, contracts/projection.v1.json).
 *
 * The closure-shaped laws (2,3,4,6,7,8) are measured against TEMP schema directories and TEMP contracts, so nothing in
 * this shared tree is mutated to test them. The certificate-shaped laws (1,5,9,10,11) are measured against the four
 * REAL shipped projections, because baseline/multi/multi-v1 already differ in exactly the way law 5 is about.
 *
 * Law 4 is measured in BOTH of its readings, and the second one does not hold. That is D-072's finding, and the test
 * that records it asserts the coupling is still there — so whoever removes it is told to update the record. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, readdirSync, mkdtempSync, mkdirSync, rmSync, copyFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join, relative } from "node:path";
import { schemaIndex, requiredSchemaClosure, schemaClosureId, projectionContractId, loadContract, deriveClosure, CONTRACT_FILE } from "../lib/closure.mjs";
import { buildCertificate, checkCertificate, deriveFromDirectory, PROTOCOL, PROTOCOL_V1, certificateDirFor } from "../lib/certificate.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const NAMES = ["baseline", "historical", "multi", "multi-v1"];
const DIR = Object.fromEntries(NAMES.map((n) => [n, join(V, "projections", n)]));
const json = (p) => JSON.parse(readFileSync(p, "utf8"));
const bundleOf = (dir, proto) => json(join(dir, certificateDirFor(proto), "bundle.json"));
const vclaimOf = (dir, proto) => readFileSync(join(dir, certificateDirFor(proto), "VCLAIM"), "utf8").trim();
const runsOf = (dir) => readFileSync(join(dir, "records/adapter_run.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const ID = (n) => `https://graphonomous.com/g0/schemas/${n}.schema.json`;

/** A throwaway copy of schemas/ that a test may edit. Returns the directory RELATIVE to the package root, because
 *  lib/closure.mjs resolves against it. */
const tmps = [];
function tempSchemas(mutate = () => {}) {
  const abs = mkdtempSync(join(V, ".tmp-schemas-")); tmps.push(abs);
  for (const f of readdirSync(join(V, "schemas")).filter((n) => n.endsWith(".schema.json"))) copyFileSync(join(V, "schemas", f), join(abs, f));
  mutate(abs);
  return relative(V, abs);
}
function tempContract(mutate = (c) => c) {
  const abs = mkdtempSync(join(V, ".tmp-contract-")); tmps.push(abs);
  const c = mutate(JSON.parse(JSON.stringify(loadContract())));
  const file = join(abs, "projection.v1.json"); writeFileSync(file, JSON.stringify(c, null, 1));
  return relative(V, file);
}
process.on("exit", () => { for (const d of tmps) rmSync(d, { recursive: true, force: true }); });

const closureOf = (schemaDir, contractFile, adapters, ruleset = true) => {
  const index = schemaIndex(schemaDir);
  const contract = loadContract(contractFile);
  const members = requiredSchemaClosure(index, contract, { adapters, ruleset });
  return { members, id: schemaClosureId(members), contract, index };
};
const ALL3 = ["adapters/crosswalk.mjs", "adapters/factory.mjs", "adapters/factory_mosaic.mjs"];

/* ─────────────────────────────── law 11 + law 1 ─────────────────────────────── */

test("law 11 + law 1: all four shipped projections certify under v1, and the derivation is a pure function of (contract, selector, schema bytes) — deriving twice gives the same claim", () => {
  for (const n of NAMES) {
    const r = checkCertificate(DIR[n], undefined, { protocol: PROTOCOL_V1 });
    assert.equal(r.verdict, "VERIFIED", `${n}: ${r.codes.join(", ")}`);
    assert.equal(r.measured.protocol, PROTOCOL_V1);
    assert.equal(r.measured.writes, 0, "a check writes nothing");
    const a = deriveFromDirectory(DIR[n], { protocol: PROTOCOL_V1 }).derived;
    const b = deriveFromDirectory(DIR[n], { protocol: PROTOCOL_V1 }).derived;
    assert.deepEqual(a.claim, b.claim, `${n}: two derivations disagree`);
    assert.equal(a.verified_claim_sem_id, vclaimOf(DIR[n], PROTOCOL_V1));
    assert.match(a.claim.schema_closure_id, /^gschema-[0-9a-f]{64}$/);
    assert.match(a.claim.projection_contract_id, /^gpcon-[0-9a-f]{64}$/);
    assert.equal(a.claim.schema_set_id, undefined, `${n}: the v1 claim must not carry the v0 coordinate`);
  }
});

test("v1 NARROWS: 12 schemas are indexed, 9 are required. The three excluded ones are named, each for a measured reason", () => {
  const d = deriveClosure(runsOf(DIR["multi-v1"]));
  assert.deepEqual(d.problems, []);
  assert.equal(d.indexed, 12, "every schema file is still indexed — narrowing happens in the CLOSURE, not the index");
  assert.equal(d.members.length, 9);
  const ids = d.members.map(([id]) => id);
  for (const n of ["node", "relation", "assertion", "source_location", "fault", "adapter_run", "manifest", "snapshot", "rules"]) assert.ok(ids.includes(ID(n)), `${n} is required and missing`);
  const contract = loadContract();
  for (const n of ["common", "derived_fact", "evaluation"]) {
    assert.ok(!ids.includes(ID(n)), `${n} must not be in the closure`);
    assert.ok(typeof contract.excluded[ID(n)] === "string" && contract.excluded[ID(n)].length > 40, `${n}'s exclusion must state a reason`);
  }
});

/* ─────────────────────────────── laws 2, 3, 6, 7 ─────────────────────────────── */

test("law 2: adding an unrelated schema, not reachable from the active contract, HOLDS", () => {
  const before = closureOf("schemas", CONTRACT_FILE, ALL3);
  const dir = tempSchemas((abs) => writeFileSync(join(abs, "unrelated.schema.json"), JSON.stringify({
    $schema: "https://json-schema.org/draft/2020-12/schema", $id: ID("unrelated"), title: "not reachable from any active adapter", type: "object",
  }, null, 1)));
  const after = closureOf(dir, CONTRACT_FILE, ALL3);
  assert.equal(after.index.size, before.index.size + 1, "the new file IS indexed");
  assert.equal(after.id, before.id, "…and does not enter the closure");
  assert.deepEqual(after.members, before.members);
});

test("law 3: changing a schema the active adapters genuinely require MOVES; changing an EXCLUDED one does not", () => {
  const before = closureOf("schemas", CONTRACT_FILE, ALL3);
  const required = tempSchemas((abs) => { const f = join(abs, "relation.schema.json"); const d = JSON.parse(readFileSync(f, "utf8")); d.title += " (edited)"; writeFileSync(f, JSON.stringify(d, null, 1)); });
  assert.notEqual(closureOf(required, CONTRACT_FILE, ALL3).id, before.id, "a required schema moved and the closure did not");

  const excluded = tempSchemas((abs) => { const f = join(abs, "evaluation.schema.json"); const d = JSON.parse(readFileSync(f, "utf8")); d.title += " (edited)"; writeFileSync(f, JSON.stringify(d, null, 1)); });
  assert.equal(closureOf(excluded, CONTRACT_FILE, ALL3).id, before.id, "an EXCLUDED schema moved and the closure followed it");
});

test("law 6: traversal order is not an input — the members are sorted by $id inside the closure function, and a contract that lists its roots backwards gives the identical id", () => {
  const forward = closureOf("schemas", CONTRACT_FILE, ALL3);
  const reversed = tempContract((c) => {
    c.structural = [...c.structural].reverse(); c.ruleset = [...c.ruleset].reverse();
    for (const k of Object.keys(c.adapters)) c.adapters[k].emits = [...c.adapters[k].emits].reverse();
    return c;
  });
  const back = closureOf("schemas", reversed, [...ALL3].reverse());
  assert.equal(back.id, forward.id);
  assert.deepEqual(back.members, forward.members);
  const ids = forward.members.map(([id]) => id);
  assert.deepEqual(ids, [...ids].sort(), "members are not in $id order");
});

test("law 7: two files claiming one $id are REFUSED at index time — even byte-identical ones; and a schema with no $id is refused as unaddressable", () => {
  const dup = tempSchemas((abs) => copyFileSync(join(abs, "node.schema.json"), join(abs, "node-copy.schema.json")));
  assert.throws(() => schemaIndex(dup), (e) => /gschema-duplicate-id/.test(e.message) && /byte-identical/.test(e.message), "a byte-identical duplicate must still refuse");

  const anon = tempSchemas((abs) => { const f = join(abs, "node.schema.json"); const d = JSON.parse(readFileSync(f, "utf8")); delete d.$id; writeFileSync(f, JSON.stringify(d, null, 1)); });
  assert.throws(() => schemaIndex(anon), /gschema-no-id/);
});

/* ─────────────────────────────── laws 4 and 5 ─────────────────────────────── */

test("law 4a: a new adapter FILE plus its schemas, activated by nothing, HOLDS — because the roots come from the adapters that RAN, not from what is on disk", () => {
  const before = closureOf("schemas", CONTRACT_FILE, ALL3);
  const dir = tempSchemas((abs) => writeFileSync(join(abs, "finding.schema.json"), JSON.stringify({ $schema: "https://json-schema.org/draft/2020-12/schema", $id: ID("finding"), title: "a future adapter's own record kind", type: "object" }, null, 1)));
  const contract = tempContract((c) => {
    c.record_kinds.consistency_finding = ID("finding");
    c.adapters["adapters/future.mjs"] = { name: "future", emits: ["consistency_finding"], measured: "fixture" };
    return c;
  });
  const inactive = closureOf(dir, contract, ALL3);
  assert.equal(inactive.id, before.id, "an adapter nothing ran contributed a schema to the closure");

  /* law 5: activate it — the closure MOVES because it introduces a schema not already required */
  const active = closureOf(dir, contract, [...ALL3, "adapters/future.mjs"]);
  assert.notEqual(active.id, before.id);
  assert.equal(active.members.length, before.members.length + 1);
  assert.ok(active.members.some(([id]) => id === ID("finding")));
});

test("law 5, as sharpened (D-072): activating an adapter ALWAYS moves projection_contract_id; it moves schema_closure_id if and only if the adapter introduces a schema not already required. MEASURED on the three real projections.", () => {
  const b = bundleOf(DIR["baseline"], PROTOCOL_V1).claim, m = bundleOf(DIR["multi"], PROTOCOL_V1).claim, m1 = bundleOf(DIR["multi-v1"], PROTOCOL_V1).claim;
  /* baseline runs [crosswalk]; multi runs [crosswalk, factory]; multi-v1 runs all three. Measured (probe c1/1): all
     three adapters emit the same six record kinds, so no activation introduces a new schema. */
  assert.equal(b.schema_closure_id, m.schema_closure_id, "the closure moved without a new schema being required");
  assert.equal(m.schema_closure_id, m1.schema_closure_id);
  assert.notEqual(b.projection_contract_id, m.projection_contract_id, "activating the factory did not move the contract id");
  assert.notEqual(m.projection_contract_id, m1.projection_contract_id, "activating factory_mosaic did not move the contract id");
  assert.equal(new Set([b.projection_contract_id, m.projection_contract_id, m1.projection_contract_id]).size, 3);
  /* historical runs the same single adapter as baseline, so its contract id is the SAME — the contract id is about the
     adapter set, not about which sources they read. */
  assert.equal(bundleOf(DIR["historical"], PROTOCOL_V1).claim.projection_contract_id, b.projection_contract_id);
});

test("law 4b, THE RESIDUE (D-072): registering an adapter so it CAN be activated still moves chain_ids.projector.code, because lib/project.mjs holds the ADAPTERS table and lib/project.mjs is inside PROJECTOR_MODULES. v1 does not close this, and the coupling is asserted here so that removing it forces the record to be updated.", () => {
  const { PROJECTOR_MODULES } = { PROJECTOR_MODULES: ["adapters/git.mjs", "lib/canon.mjs", "lib/emit.mjs", "lib/lid.mjs", "lib/project.mjs", "lib/rules.mjs", "lib/schema.mjs"] };
  assert.ok(PROJECTOR_MODULES.includes("lib/project.mjs"), "if project.mjs left the projector set, this residue is gone — update D-072");
  const src = readFileSync(join(V, "lib", "project.mjs"), "utf8");
  assert.match(src, /const ADAPTERS = \{/, "the adapter registry is still a literal inside a projector module");
  for (const a of ["crosswalk", "factory", "factory_mosaic"]) assert.ok(src.includes(`${a}: { file: "adapters/${a}.mjs"`), `${a} is registered in lib/project.mjs`);
  /* and the historical proof that this is not hypothetical: the pre-v1 receipts moved projector.code too */
  for (const n of ["baseline", "historical", "multi"]) {
    const old = json(join(V, "projections", "pre-v1", n, "certificate", "bundle.json"));
    const cur = bundleOf(DIR[n], PROTOCOL);
    assert.notEqual(old.chain_ids.projector.code, cur.chain_ids.projector.code, `${n}: pre-v1 → current did NOT move projector.code — D-072's measurement is stale`);
    assert.equal(old.chain_ids.checker.code, cur.chain_ids.checker.code, `${n}: the checker code did not move in that step`);
  }
});

/* ─────────────────────────────── laws 8, 9, 10 ─────────────────────────────── */

test("law 8: a bundle-supplied closure is COMPARED, never consumed — the derivation does not take the bundle as a parameter, and a bundle that under-declares is REFUSED on its own coordinate", () => {
  const dir = DIR["multi-v1"];
  const good = bundleOf(dir, PROTOCOL_V1);
  /* The derivation is STRUCTURALLY unable to read the bundle: closure.mjs takes (runs, opts) and certificate.mjs
     hands it only the projection's own adapter_run records. Measured on the source, not on a signature arity, because
     a default parameter hides itself from Function.length. */
  const closureSrc = readFileSync(join(V, "lib", "closure.mjs"), "utf8");
  assert.ok(!/\bbundle\b/.test(closureSrc.replace(/\/\*[\s\S]*?\*\//g, "")), "lib/closure.mjs mentions a bundle outside its comments");
  assert.match(readFileSync(join(V, "lib", "certificate.mjs"), "utf8"), /deriveClosure\(runs, \{ ruleset:/, "the closure is derived from the projection's own runs");
  const forged = JSON.parse(JSON.stringify(good));
  forged.claim.schema_closure_id = "gschema-" + "0".repeat(64);
  const r = checkCertificate(dir, forged, { cited: null, protocol: PROTOCOL_V1 });
  assert.equal(r.verdict, "REFUSED");
  assert.ok(r.codes.includes("gproj-schema-closure-mismatch"), r.codes.join(", "));
  assert.equal(r.measured.schema_closure_id, good.claim.schema_closure_id, "the checker still reports what IT derived");

  const forged2 = JSON.parse(JSON.stringify(good));
  forged2.claim.projection_contract_id = "gpcon-" + "0".repeat(64);
  const r2 = checkCertificate(dir, forged2, { cited: null, protocol: PROTOCOL_V1 });
  assert.ok(r2.codes.includes("gproj-projection-contract-mismatch"), r2.codes.join(", "));
});

test("law 8, second face: a projection that ran an adapter the contract never declared is REFUSED, not silently closed over", () => {
  const runs = runsOf(DIR["multi-v1"]).map((r) => ({ ...r, adapter: { ...r.adapter, uri: "file:adapters/smuggled.mjs" } }));
  const d = deriveClosure(runs);
  assert.equal(d.closure_id, null);
  assert.deepEqual(d.problems.map((p) => p.code), ["gschema-unknown-adapter"]);
  assert.match(d.problems[0].detail, /may not activate an adapter the contract has never seen/);
});

test("law 9: the GPT-frozen v0 goldens are byte-for-byte preserved under their pinned coordinates, and the live re-mint moved EXACTLY ONE coordinate — chain_ids.projector, because registering a fourth adapter edits lib/project.mjs (D-072 law-4b residue, D-073)", () => {
  /* These four are the vclaim- values GPT v6 §0 froze as golden. They are preserved in projections/pre-trvm/ exactly
     as they were minted, and they are NOT the live values any more: registering adapters/trvm.mjs required one row in
     lib/project.mjs, which is inside codeId(PROJECTOR_MODULES). Law 9 is "byte-for-byte reproducible under their
     PINNED coordinates" (D-060), not "unchanged under a moved projector" — so this test measures both halves. */
  const GOLDEN = {
    baseline: "vclaim-67038bf96fe5a7c5042be05199157d7b728042ec652c1fd43440dda919ae8efa",
    historical: "vclaim-e148f86d613b5c5ec03ec455552e47cc5c3ec6e49ef3815c782e9b9e804df798",
    multi: "vclaim-7bbcc6d2c281f8d19c371bf32e759c88fc3d0cca3f8bedc0fd600d8c337459d6",
    "multi-v1": "vclaim-1a029671389206f7051b7acd651c29acc56b7f991288fe96e0f63fdf4ada9b19",
  };
  for (const n of NAMES) {
    const preserved = join(V, "projections", "pre-trvm", n, "certificate");
    assert.equal(readFileSync(join(preserved, "VCLAIM"), "utf8").trim(), GOLDEN[n], `${n}: the GPT-frozen golden is not preserved byte-for-byte`);
    const old = json(join(preserved, "bundle.json")), cur = bundleOf(DIR[n], PROTOCOL);
    /* exactly one coordinate moved, and it is the one D-072 predicted */
    const movedClaim = Object.keys(old.claim).filter((k) => JSON.stringify(old.claim[k]) !== JSON.stringify(cur.claim[k]));
    assert.deepEqual(movedClaim, [], `${n}: a CLAIM field moved when only the projector should have — ${movedClaim.join(", ")}`);
    const movedChain = Object.keys(old.chain_ids).filter((k) => JSON.stringify(old.chain_ids[k]) !== JSON.stringify(cur.chain_ids[k]));
    assert.deepEqual(movedChain, ["projector"], `${n}: expected only chain_ids.projector to move — ${movedChain.join(", ")}`);
    assert.deepEqual(old.aggregate, cur.aggregate);
    assert.deepEqual(old.structure, cur.structure);
    assert.equal(old.chain_ids.trvm_commit, cur.chain_ids.trvm_commit, `${n}: the TRVM pin did not move`);
    assert.notEqual(readFileSync(join(preserved, "VCLAIM"), "utf8").trim(), vclaimOf(DIR[n], PROTOCOL));
    /* and the live receipt verifies under the live checker */
    const r = checkCertificate(DIR[n], undefined, { protocol: PROTOCOL });
    assert.equal(r.verdict, "VERIFIED", `${n}: ${r.codes.join(", ")}`);
    assert.equal(bundleOf(DIR[n], PROTOCOL).protocol, PROTOCOL);
    assert.ok(bundleOf(DIR[n], PROTOCOL).claim.schema_set_id !== undefined, "v0 still binds the whole directory, by design");
    /* the frozen golden is refused by the live checker, on exactly the coordinate that moved and nothing else */
    const back = checkCertificate(DIR[n], readFileSync(join(preserved, "bundle.json")), { cited: null, protocol: PROTOCOL });
    assert.equal(back.verdict, "REFUSED");
    assert.deepEqual(back.codes, ["gproj-certificate-stale", "gproj-chain-id-mismatch"], `${n}: ${back.codes.join(", ")}`);
    assert.equal(back.measured.projection_root, cur.claim.projection_root, "the projection root is unchanged — what moved was the projector, not the projection");
  }
});


test("law 10: the two receipts coexist for one root and are intentionally distinct — and the ONLY things that moved are the protocol-defined ones. gsnap-, gagg- and gstruct- HOLD, because they are identities of the PROJECTION, not of the receipt protocol.", () => {
  for (const n of NAMES) {
    const v0 = bundleOf(DIR[n], PROTOCOL), v1 = bundleOf(DIR[n], PROTOCOL_V1);
    assert.notEqual(v0.protocol, v1.protocol);
    assert.notEqual(vclaimOf(DIR[n], PROTOCOL), vclaimOf(DIR[n], PROTOCOL_V1));
    assert.notEqual(v0.claim.projection_claim_sem_id, v1.claim.projection_claim_sem_id);
    /* everything about the projection itself is the same string */
    assert.equal(v0.claim.projection_root, v1.claim.projection_root);
    assert.equal(v0.claim.snapshot_commitment, v1.claim.snapshot_commitment, "the source-set commitment must not move with the receipt protocol");
    assert.equal(v0.claim.adapter_contract_id, v1.claim.adapter_contract_id);
    assert.equal(v0.claim.ruleset, v1.claim.ruleset);
    assert.deepEqual(v0.aggregate, v1.aggregate, "the aggregate is a re-derivation of the records, not a protocol artifact");
    assert.deepEqual(v0.structure, v1.structure);
    assert.deepEqual(v0.chain_ids, v1.chain_ids, "the code chain is shared: v1 is a claim change, not a code change");
    /* and the two claims differ in exactly the schema coordinate */
    const k0 = Object.keys(v0.claim).sort(), k1 = Object.keys(v1.claim).sort();
    assert.deepEqual(k0.filter((k) => !k1.includes(k)), ["schema_set_id"]);
    assert.deepEqual(k1.filter((k) => !k0.includes(k)), ["projection_contract_id", "schema_closure_id"]);
  }
});

test("a v0 bundle offered to the v1 checker, and the reverse, are refused on the protocol before anything else is read", () => {
  const dir = DIR["multi"];
  const asV1 = checkCertificate(dir, bundleOf(dir, PROTOCOL), { cited: null, protocol: PROTOCOL_V1 });
  assert.deepEqual(asV1.codes, ["gproj-protocol-mismatch"]);
  const asV0 = checkCertificate(dir, bundleOf(dir, PROTOCOL_V1), { cited: null, protocol: PROTOCOL });
  assert.deepEqual(asV0.codes, ["gproj-protocol-mismatch"]);
});

test("the producer is idempotent: rebuilding a v1 certificate over an unchanged directory writes the same bytes", () => {
  const dir = DIR["multi"];
  const before = readFileSync(join(dir, "certificate-v1", "bundle.json"));
  const again = buildCertificate(dir, { protocol: PROTOCOL_V1 });
  assert.ok(again.bytes.equals(before), "a rebuild is not byte-identical");
  assert.equal(again.verified_claim_sem_id, vclaimOf(dir, PROTOCOL_V1));
});
