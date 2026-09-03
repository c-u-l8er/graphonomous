/* factory_certificate.test.mjs — G0-F certificate sensitivity (D-054 §G0-F): adding a second authoritative source moves the
 * snapshot commitment, the projection root and the certificate; the baseline certificate keeps verifying beside the new
 * one; the baseline bundle is refused against the multi directory; dropping the factory source cannot alias the
 * two-source certificate; reordering sources changes nothing bound; and the pre-G0-F bundles (preserved under
 * projections/pre-g0f/) refuse on CODE identity only — never on root or snapshot — which is the measured face of "old
 * certificates stay checkable after a later snapshot, and re-mint when the projector or a schema changes". Every id is
 * read from the shipped bundles and re-derived by the checker. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync, rmSync, cpSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { buildCertificate, checkCertificate, checkGraphonomousChild, snapshotCommitment, claimSemId, deriveFromDirectory, adapterContractId, PROTOCOL, CLAIM_FIELD } from "../lib/certificate.mjs";
import { artifactRoot, canonicalWireBytes, putArtifact } from "../../../TRVM/governance/cas.mjs";
import { RELATION_KINDS, KIND_PREFIX } from "../lib/lid.mjs";
const NODE_KINDS = Object.keys(KIND_PREFIX);

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DIR = { baseline: resolve(V, "projections/baseline"), historical: resolve(V, "projections/historical"), multi: resolve(V, "projections/multi") };
const PRE = { baseline: resolve(V, "projections/pre-g0f/baseline"), historical: resolve(V, "projections/pre-g0f/historical") };
const PRE_P01 = { baseline: resolve(V, "projections/pre-trvmp01/baseline"), historical: resolve(V, "projections/pre-trvmp01/historical"), multi: resolve(V, "projections/pre-trvmp01/multi") };
const PRE_V1 = { baseline: resolve(V, "projections/pre-v1/baseline"), historical: resolve(V, "projections/pre-v1/historical"), multi: resolve(V, "projections/pre-v1/multi") };
const bundleOf = (dir) => ({ bytes: readFileSync(join(dir, "certificate/bundle.json")), bundle: JSON.parse(readFileSync(join(dir, "certificate/bundle.json"), "utf8")), vclaim: readFileSync(join(dir, "certificate/VCLAIM"), "utf8").trim() });
const S = { baseline: bundleOf(DIR.baseline), historical: bundleOf(DIR.historical), multi: bundleOf(DIR.multi) };
const snapOf = (dir) => JSON.parse(readFileSync(join(dir, "snapshot.json"), "utf8"));
const clone = (o) => JSON.parse(JSON.stringify(o));
const FROZEN = { baseline: "root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85", historical: "root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87" };
const tmp = mkdtempSync(join(tmpdir(), "g0-fcert-")); process.on("exit", () => rmSync(tmp, { recursive: true, force: true }));
const copy = (name, of) => { const d = join(tmp, name); cpSync(DIR[of], d, { recursive: true }); return d; };
const rewriteSnapshot = (dir, mutate) => { const snap = snapOf(dir); const old = artifactRoot(snap); const next = mutate(snap) ?? snap; writeFileSync(join(dir, "snapshot.json"), canonicalWireBytes(next)); const root = putArtifact(join(dir, "cas"), next); if (root !== old && existsSync(join(dir, "cas", old + ".json"))) unlinkSync(join(dir, "cas", old + ".json")); return next; };

test("the multi snapshot commitment, projection root, claim id and certificate all differ from the baseline's; the baseline's snapshot commitment, root and evidence aggregate are UNCHANGED by G0-F (only its code-bound claim/certificate re-minted); the multi certificate VERIFIES", () => {
  const B = S.baseline.bundle, M = S.multi.bundle;
  assert.notEqual(M.claim.snapshot_commitment, B.claim.snapshot_commitment); assert.notEqual(M.claim.projection_root, B.claim.projection_root); assert.notEqual(M.claim[CLAIM_FIELD], B.claim[CLAIM_FIELD]); assert.notEqual(S.multi.vclaim, S.baseline.vclaim);
  assert.equal(M.claim.snapshot_id, "snapshot:g0:multi-ba4e625-d217ee2"); assert.equal(M.claim.projection_root, readFileSync(join(DIR.multi, "ROOT"), "utf8").trim());
  assert.equal(B.claim.projection_root, FROZEN.baseline); assert.equal(B.claim.snapshot_commitment, "gsnap-d67431565fa32b7de8a19b9bdda5e30adfcd74e54ce2eca2b97d41820b05146b", "R13 §7.2 [2]: the baseline commitment did not move");
  assert.equal(B.aggregate.aggregate_id, "gagg-02ce97b7b9d9f1664cce6862b8529c6f57a579d5af513976cafcb9960d334548", "the baseline evidence aggregate did not move");
  assert.equal(M.claim.snapshot_commitment, snapshotCommitment(snapOf(DIR.multi))); assert.equal(B.claim.snapshot_commitment, snapshotCommitment(snapOf(DIR.baseline)));
  // the two commitments differ ONLY because the factory source's identity differs (66 files vs 3): swap it and they meet
  const b = clone(snapOf(DIR.baseline)), m = clone(snapOf(DIR.multi)); b.sources = b.sources.map((s) => (s.namespace === "factory" ? m.sources.find((x) => x.namespace === "factory") : s));
  assert.equal(snapshotCommitment(b), M.claim.snapshot_commitment, "the multi commitment is the baseline set with the factory source widened to every file the adapter reads");
  assert.equal(M.claim.schema_set_id, B.claim.schema_set_id); assert.equal(M.claim.ruleset, B.claim.ruleset); assert.deepEqual(M.chain_ids, B.chain_ids, "same code, same chain");
  assert.notEqual(M.claim.adapter_contract_id, B.claim.adapter_contract_id, "two adapters ran for multi, one for the baseline");
  assert.deepEqual(adapterContractId(readFileSync(join(DIR.multi, "records/adapter_run.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l))).pairs.map((p) => p[0]), ["adapters/crosswalk.mjs", "adapters/factory.mjs"]);
  const r = checkCertificate(DIR.multi); assert.equal(r.verdict, "VERIFIED"); assert.deepEqual(r.codes, []); assert.equal(r.measured.verified_claim_sem_id, S.multi.vclaim); assert.equal(r.measured.entries_checked, M.aggregate.count); assert.equal(r.measured.sources, 6); assert.equal(r.measured.files_pinned, 101);
});

test("the baseline (and historical) certificate STILL VERIFIES against its own directory after multi exists, and the child check locates each of the three projections by its cited root among the directories the verifier holds", () => {
  for (const name of ["baseline", "historical", "multi"]) { const r = checkCertificate(DIR[name]); assert.equal(r.verdict, "VERIFIED", name); assert.equal(r.measured.verified_claim_sem_id, S[name].vclaim); }
  const dirs = Object.values(DIR); for (const name of ["baseline", "historical", "multi"]) assert.equal(checkGraphonomousChild(S[name].bundle, { dirs }).verdict, "VERIFIED", name);
  assert.deepEqual(checkGraphonomousChild(S.multi.bundle, { dirs: [DIR.baseline, DIR.historical] }).codes, ["gproj-root-mismatch"], "a verifier that does not hold the multi projection cannot verify its certificate");
});

test("the baseline bundle checked against projections/multi is REFUSED (gproj-root-mismatch, gproj-snapshot-commitment-mismatch, gproj-adapter-contract-mismatch, gproj-certificate-stale) and the multi bundle against the baseline directory likewise — neither can stand in for the other", () => {
  const r = checkCertificate(DIR.multi, S.baseline.bytes); assert.equal(r.verdict, "REFUSED");
  for (const c of ["gproj-root-mismatch", "gproj-snapshot-commitment-mismatch", "gproj-adapter-contract-mismatch", "gproj-certificate-stale"]) assert.ok(r.codes.includes(c), `${c} in [${r.codes}]`);
  const s = checkCertificate(DIR.baseline, S.multi.bytes); assert.equal(s.verdict, "REFUSED"); for (const c of ["gproj-root-mismatch", "gproj-snapshot-commitment-mismatch", "gproj-certificate-stale"]) assert.ok(s.codes.includes(c), c);
  const cited = checkCertificate(DIR.multi, S.multi.bundle, { cited: { verified_claim_sem_id: S.baseline.vclaim, protocol: PROTOCOL, claim_sem_id: S.baseline.bundle.claim[CLAIM_FIELD], aggregate_id: S.baseline.bundle.aggregate.aggregate_id } });
  assert.deepEqual(cited.codes, ["gproj-certificate-stale", "gproj-citation-cross-wired"], "the right bundle under the other snapshot's citation");
});

test("dropping the factory source from the multi snapshot cannot verify as the two-source snapshot: the commitment differs and the checker refuses gproj-snapshot-commitment-mismatch; narrowing the factory source back to the baseline's 3 files is the same refusal (a source's FILE SET is part of its identity)", () => {
  const d = copy("drop", "multi"); rewriteSnapshot(d, (s) => { s.sources = s.sources.filter((x) => x.namespace !== "factory"); });
  assert.notEqual(snapshotCommitment(snapOf(d)), S.multi.bundle.claim.snapshot_commitment);
  const r = checkCertificate(d, S.multi.bytes); assert.equal(r.verdict, "REFUSED"); assert.ok(r.codes.includes("gproj-snapshot-commitment-mismatch"), r.codes.join()); assert.ok(!r.codes.includes("gproj-root-mismatch"), "the records did not change, only the pinned set");
  const n = copy("narrow", "multi"); rewriteSnapshot(n, (s) => { const f = s.sources.find((x) => x.namespace === "factory"); f.files = f.files.filter((x) => ["CLAIM_LEDGER.json", "mosaic/embodiment.json", "scripts/emb-support.mjs"].includes(x.path)); });
  assert.equal(snapshotCommitment({ sources: snapOf(n).sources.map((s) => ({ ...s })) }), snapshotCommitment({ sources: snapOf(DIR.baseline).sources }), "narrowed, the source SET equals the baseline's set (the adapters differ, not the pins)");
  const rn = checkCertificate(n, S.multi.bytes); assert.equal(rn.verdict, "REFUSED"); assert.ok(rn.codes.includes("gproj-snapshot-commitment-mismatch"));
  // and a producer over the narrowed copy mints a certificate that is NOT the shipped one (it binds the baseline's commitment to the multi root)
  const c = buildCertificate(n); assert.notEqual(c.verified_claim_sem_id, S.multi.vclaim); assert.equal(c.bundle.claim.snapshot_commitment, S.baseline.bundle.claim.snapshot_commitment); assert.equal(c.bundle.claim.projection_root, S.multi.bundle.claim.projection_root);
});

test("reordering the sources (and every file list) in the multi snapshot gives the same commitment and the SAME certificate; only the transport-plane snapshot record root moves", () => {
  const d = copy("reorder", "multi"); const before = snapOf(d);
  rewriteSnapshot(d, (s) => { s.sources = s.sources.slice().reverse(); s.sources.forEach((x) => { x.files = x.files.slice().reverse(); }); });
  assert.notDeepEqual(snapOf(d).sources.map((s) => s.namespace), before.sources.map((s) => s.namespace));
  assert.equal(snapshotCommitment(snapOf(d)), S.multi.bundle.claim.snapshot_commitment);
  const c = buildCertificate(d); assert.equal(c.verified_claim_sem_id, S.multi.vclaim); assert.deepEqual(c.bundle.claim, S.multi.bundle.claim); assert.deepEqual(c.bundle.aggregate, S.multi.bundle.aggregate);
  assert.notEqual(c.bundle.references.operands[1].artifact_root, S.multi.bundle.references.operands[1].artifact_root, "the snapshot record is a different artifact");
  const r = checkCertificate(d, S.multi.bytes); assert.deepEqual(r.codes, ["gproj-reference-mismatch"]); assert.equal(r.measured.stated_verified_claim_sem_id, r.measured.verified_claim_sem_id);
  // the adapter list is data too: its order in params does not enter the commitment (params is not a source identity) — but it IS the label the manifest binds
  const p = copy("adapters-order", "multi"); rewriteSnapshot(p, (s) => { s.params.adapters = s.params.adapters.slice().reverse(); });
  assert.equal(snapshotCommitment(snapOf(p)), S.multi.bundle.claim.snapshot_commitment); assert.deepEqual(checkCertificate(p, S.multi.bytes).codes, ["gproj-reference-mismatch"]);
});

test("pre-G0-F receipts (projections/pre-g0f/): the certificates minted before the second adapter existed refuse against the SAME unchanged baseline/historical directories on CODE identity only — gproj-chain-id-mismatch (the projector gained an adapter table; the checker re-pinned TRVM from fd0df4c to 9e91c96 for TRVM-P0 and again to 8816e59 for TRVM-P0.1; the five pinned TRVM blobs held) + gproj-schema-set-mismatch (two fault codes entered the enum) + gproj-certificate-stale — and never on root, snapshot commitment, adapter contract or aggregate: what moved was the projector, not the frozen projection", () => {
  for (const name of ["baseline", "historical"]) {
    const old = bundleOf(PRE[name]); const cur = S[name];
    assert.notEqual(old.vclaim, cur.vclaim); assert.equal(old.bundle.claim.projection_root, cur.bundle.claim.projection_root); assert.equal(old.bundle.claim.projection_root, FROZEN[name]);
    assert.equal(old.bundle.claim.snapshot_commitment, cur.bundle.claim.snapshot_commitment); assert.equal(old.bundle.claim.adapter_contract_id, cur.bundle.claim.adapter_contract_id, "crosswalk.mjs is byte-identical"); assert.equal(old.bundle.claim.ruleset, cur.bundle.claim.ruleset);
    assert.deepEqual(old.bundle.aggregate, cur.bundle.aggregate); assert.deepEqual(old.bundle.structure, cur.bundle.structure); assert.deepEqual(old.bundle.references, cur.bundle.references);
    assert.notEqual(old.bundle.claim.schema_set_id, cur.bundle.claim.schema_set_id); assert.notEqual(old.bundle.chain_ids.projector.code, cur.bundle.chain_ids.projector.code, "the projector gained an adapter table"); assert.notEqual(old.bundle.chain_ids.checker.code, cur.bundle.chain_ids.checker.code, "lib/canon.mjs re-pinned TRVM (TRVM-P0), and canon.mjs is in the checker code id"); assert.equal(old.bundle.chain_ids.trvm_commit, "fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873"); assert.equal(cur.bundle.chain_ids.trvm_commit, "8816e59055322fc608c9bc7dae9723c02d8402b7", "TRVM-P0.1"); assert.deepEqual(old.bundle.chain_ids.trvm_blobs, cur.bundle.chain_ids.trvm_blobs, "the five pinned TRVM blobs did not move under TRVM-P0 and did not move under TRVM-P0.1 either");
    const r = checkCertificate(DIR[name], old.bytes); assert.equal(r.verdict, "REFUSED");
    assert.deepEqual(r.codes, ["gproj-certificate-stale", "gproj-chain-id-mismatch", "gproj-schema-set-mismatch"], `${name}: exactly the code-identity refusals`);
    assert.equal(old.vclaim, "vclaim-" + { baseline: "897ec409c49c189b769310966b0c85a25df9fc933fafa066d227a6c8aa6017c4", historical: "a6ba3b33cbc1732e8bfc79e189d7e6a0ced3669caf8d0c6e884ad08632867a7c" }[name], "the G0-D vector as minted on 2026-09-03");
  }
  const ev = readFileSync(resolve(V, "projections/pre-g0f/EVIDENCE.md"), "utf8"); assert.ok(ev.includes("vclaim-897ec409") && ev.includes("vclaim-a6ba3b33") && /re-minted/i.test(ev));
});

/* TRVM-P0.1 is the SHARPEST re-mint this lane has: exactly ONE coordinate moved. The owning layer issued spec
   revision 2 (28 refusal codes → 30, plus an enlarged spec_agreement) at TRVM 8816e59, and not one of the five
   blobs Graphonomous pins changed a byte. So `assertTrvmPinned` — which reads blobs — would have said nothing,
   the projector did not move, the schema set did not move, and the claim did not move: the projection root, the
   snapshot commitment, the `gclaim-`, the aggregate and the structure are all identical on both sides. Only the
   certificate moved, because the certificate is the one thing that names WHICH CODE reconstructed the projection.
   This is D-060's re-mint semantics with every other variable held still. */
test("pre-TRVM-P0.1 receipts (projections/pre-trvmp01/): the owning layer's release moved and NOTHING ELSE did — same root, same commitment, same gclaim, same aggregate, same schema set, same adapter contract, same five TRVM blobs (the projector and checker code ids move with it, because lib/canon.mjs holds the pin); a different vclaim, refused on exactly gproj-chain-id-mismatch + gproj-certificate-stale", () => {
  for (const name of ["baseline", "historical", "multi"]) {
    /* COMPARED AGAINST pre-v1, NOT against the current certificate. Two re-mints happened in this round and each
       moved ONE coordinate; comparing against `current` would blur them into one. This test owns the first. */
    const old = bundleOf(PRE_P01[name]); const cur = bundleOf(PRE_V1[name]);

    /* the CLAIM is untouched, field for field — this is the whole point */
    assert.deepEqual(old.bundle.claim, cur.bundle.claim, `${name}: the claim did not move`);
    assert.deepEqual(old.bundle.aggregate, cur.bundle.aggregate);
    assert.deepEqual(old.bundle.structure, cur.bundle.structure);
    assert.deepEqual(old.bundle.references, cur.bundle.references);
    /* the projector code id DOES move, and the honest reason is worth stating: `lib/canon.mjs` is where TRVM_PIN
       lives AND is a projector module, so re-pinning moves the projector id as well as the checker id. What did not
       move is everything the projector PRODUCED — the manifest, the records, the root. */
    assert.notEqual(old.bundle.chain_ids.projector.code, cur.bundle.chain_ids.projector.code, "lib/canon.mjs carries the pin and is a projector module");
    assert.equal(old.bundle.claim.adapter_contract_id, cur.bundle.claim.adapter_contract_id, "no adapter changed a byte");
    assert.equal(old.bundle.claim.schema_set_id, cur.bundle.claim.schema_set_id, "no schema changed");
    assert.deepEqual(old.bundle.chain_ids.trvm_blobs, cur.bundle.chain_ids.trvm_blobs, "not one pinned TRVM blob moved");

    /* exactly two things moved: the commit in the chain, and (because lib/canon.mjs holds it) the checker code id */
    assert.equal(old.bundle.chain_ids.trvm_commit, "9e91c96f2d50f3c3bd143fc94ec4267a6b03195a", "TRVM-P0");
    assert.equal(cur.bundle.chain_ids.trvm_commit, "8816e59055322fc608c9bc7dae9723c02d8402b7", "TRVM-P0.1");
    assert.notEqual(old.bundle.chain_ids.checker.code, cur.bundle.chain_ids.checker.code, "the pin lives in lib/canon.mjs, which the checker code id covers");
    assert.notEqual(old.vclaim, cur.vclaim, "so the certificate moved");

    /* and the old receipt verifies under ITS pinned verifier coordinates while the CURRENT checker names the moved
       one — never the root, the commitment, the claim or the aggregate (D-060). */
    const r = checkCertificate(DIR[name], old.bytes);
    assert.equal(r.verdict, "REFUSED");
    assert.ok(r.codes.includes("gproj-chain-id-mismatch") && r.codes.includes("gproj-certificate-stale"), `${name}: the moved coordinate is named`);
    assert.ok(!r.codes.some((c) => ["gproj-root-mismatch", "gproj-snapshot-commitment-mismatch", "gproj-aggregate-mismatch", "gproj-adapter-contract-mismatch"].includes(c)), `${name}: never the root, the commitment, the aggregate or the adapter contract — ${r.codes.join(", ")}`);
    assert.equal(r.measured.projection_root, cur.bundle.claim.projection_root, "the checker still reconstructs the same root from the same bytes");
    assert.equal(r.measured.snapshot_commitment, cur.bundle.claim.snapshot_commitment);
    assert.equal(r.measured.writes, 0, "a checker writes nothing, refusing or not");
  }

  /* the three TRVM-P0 vectors GPT froze as golden (D-060) are exactly the bytes preserved here */
  assert.equal(bundleOf(PRE_P01.baseline).vclaim, "vclaim-c90547a6de6d46e5a79750ca897a58f3f4305971c300c567cab712436b7bd851");
  assert.equal(bundleOf(PRE_P01.historical).vclaim, "vclaim-bf81cc6d8deaa393638f0d13028cf4a6c9f737b7bf4a7c7869bd651fa880e0cf");
  assert.equal(bundleOf(PRE_P01.multi).vclaim, "vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2");
});

/* THE SECOND ISOLATED MOVEMENT of this round, and the one with a cost worth naming. Opening
   `graphonomous.semantic.v1` added three node roles and one relation kind to the vocabulary, and the vocabulary lives
   in the schema files — whose set identity `schemaSetId()` computes over EVERY schemas/*.schema.json in the repo. So
   growing v1 moves `schema_set_id` for the frozen v0 projections too, and their claims move with it. That is a real
   coupling: v0's claim identity is not independent of v1's evolution. It is recorded rather than fixed, because the
   fix would be a profile-scoped schema set, and `schema_set_id`'s meaning is part of GRAPHONOMOUS-PROJECTION-v0, whose
   semantics D-060 froze — narrowing it is a protocol change, not a refactor. Precedent: G0-F moved the same field for
   the same reason ("two fault codes entered the enum") and GPT v5 §3 called that the expected diagnostic. */
test("pre-v1 receipts (projections/pre-v1/): opening semantic.v1 moved the SCHEMA SET and therefore the v0 claims — root, commitment, aggregate and adapter contract all held, and the TRVM pin did not move at all", () => {
  for (const name of ["baseline", "historical", "multi"]) {
    const old = bundleOf(PRE_V1[name]); const cur = S[name];

    /* exactly one substantive claim field moved, and the claim id that is a function of it */
    const moved = Object.keys(old.bundle.claim).filter((k) => JSON.stringify(old.bundle.claim[k]) !== JSON.stringify(cur.bundle.claim[k]));
    assert.deepEqual(moved.sort(), ["projection_claim_sem_id", "schema_set_id"], `${name}: only the schema set and the claim id it feeds`);
    assert.equal(old.bundle.claim.projection_root, cur.bundle.claim.projection_root, "the records did not change");
    assert.equal(old.bundle.claim.snapshot_commitment, cur.bundle.claim.snapshot_commitment, "the sources did not change");
    assert.equal(old.bundle.claim.adapter_contract_id, cur.bundle.claim.adapter_contract_id, "no adapter that RAN here changed a byte");
    assert.deepEqual(old.bundle.aggregate, cur.bundle.aggregate);
    assert.deepEqual(old.bundle.structure, cur.bundle.structure);

    /* the owning layer is NOT involved this time — the same TRVM, blob for blob and commit for commit */
    assert.equal(old.bundle.chain_ids.trvm_commit, cur.bundle.chain_ids.trvm_commit, "TRVM did not move");
    assert.deepEqual(old.bundle.chain_ids.trvm_blobs, cur.bundle.chain_ids.trvm_blobs);
    assert.notEqual(old.vclaim, cur.vclaim);

    const r = checkCertificate(DIR[name], old.bytes);
    assert.equal(r.verdict, "REFUSED");
    assert.ok(r.codes.includes("gproj-schema-set-mismatch"), `${name}: the checker names the schema set — ${r.codes.join(", ")}`);
    assert.ok(!r.codes.some((c) => ["gproj-root-mismatch", "gproj-snapshot-commitment-mismatch", "gproj-aggregate-mismatch", "gproj-adapter-contract-mismatch"].includes(c)), `${name}: never the root, the commitment, the aggregate or the adapter contract`);
    assert.equal(r.measured.projection_root, cur.bundle.claim.projection_root);
    assert.equal(r.measured.writes, 0);
  }
  /* and the vocabulary really did grow by exactly four names */
  assert.equal(NODE_KINDS.filter((k) => ["ARGUMENT", "DEFEATER", "INSTRUMENT"].includes(k)).length, 3);
  assert.ok(RELATION_KINDS.includes("DISCHARGED_BY"));
});

test("the derived record of the multi directory equals the shipped bundle plane for plane, and the claim id is a pure function of the claim record", () => {
  const { refusals, derived } = deriveFromDirectory(DIR.multi); assert.deepEqual(refusals, []);
  assert.deepEqual(derived.claim, S.multi.bundle.claim); assert.deepEqual(derived.aggregate, S.multi.bundle.aggregate); assert.deepEqual(derived.structure, S.multi.bundle.structure); assert.equal(derived.verified_claim_sem_id, S.multi.vclaim);
  assert.equal(claimSemId(S.multi.bundle.claim), S.multi.bundle.claim[CLAIM_FIELD]);
  assert.equal(derived.structure.cas_objects, S.multi.bundle.aggregate.count + 2, "entries + manifest + the snapshot record beside it");
});
