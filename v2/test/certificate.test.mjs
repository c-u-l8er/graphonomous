/* certificate.test.mjs — G0-D: the eight D-054 acceptance items and the seven refusal families for
 * `GRAPHONOMOUS-PROJECTION-v0`, measured over the SHIPPED projections (read-only) and temp copies (mutated). Every id
 * compared here is re-derived — the `vclaim-` by hand from the preimage bytes, the `gclaim-`/`gagg-` from their canonical
 * preimages — so nothing is trusted because lib/certificate.mjs said it. TRVM at the pin in lib/canon.mjs (9e91c96 after TRVM-P0). */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync, rmSync, cpSync, readdirSync, statSync, existsSync, unlinkSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join, relative } from "node:path";
import { verifiedClaimSemId, certificateOf, CERTIFICATE_PROTOCOL } from "../../../TRVM/governance/certificate.mjs";
import { canonicalBytes as trvmCanonicalBytes } from "../../../TRVM/governance/derive_protocol.mjs";
import { memoryStore, resolveArtifact, artifactRoot, canonicalWireBytes, putArtifact } from "../../../TRVM/governance/cas.mjs";
import { buildCertificate, checkCertificate, checkGraphonomousChild, childProtocolEntry, deriveFromDirectory, snapshotCommitment, claimSemId, aggregateId, structureSemId, certificatePreimage, liveChainIds, schemaSetId,
  PROTOCOL, CLAIM_FIELD, CHECKER_ID, GRAMMAR, IMPLEMENTED_SCOPE, REFUSAL_CODES } from "../lib/certificate.mjs";
import { canonicalBytesG0, hashOfBytes, sortSet, TRVM_PIN, G0Error } from "../lib/canon.mjs";
import { project } from "../lib/project.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SHIPPED = { baseline: resolve(V, "projections/baseline"), historical: resolve(V, "projections/historical") };
const sha = (b) => createHash("sha256").update(b).digest("hex");
const readBundle = (dir) => ({ bytes: readFileSync(join(dir, "certificate/bundle.json")), vclaim: readFileSync(join(dir, "certificate/VCLAIM"), "utf8").trim() });
const parse = (bytes) => JSON.parse(bytes.toString("utf8"));
const clone = (o) => JSON.parse(JSON.stringify(o));
const shuffled = (arr, seed) => { const a = arr.slice(); let s = (seed >>> 0) || 1; for (let i = a.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) >>> 0; const j = s % (i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
/** Re-seal a mutated bundle the way a forger who knows the id rules would: every derived id recomputed over the record beside it. */
const reseal = (b) => { b.claim[CLAIM_FIELD] = claimSemId(b.claim); b.aggregate.aggregate_id = aggregateId(b.aggregate); b.structure.structure_sem_id = structureSemId(b.structure); return b; };
/** A digest of a whole directory (names + bytes), for "the checker writes nothing". */
const dirDigest = (dir) => { const out = []; const walk = (d) => { for (const e of readdirSync(d).sort()) { const p = join(d, e); if (statSync(p).isDirectory()) walk(p); else out.push(relative(dir, p) + ":" + sha(readFileSync(p))); } }; walk(dir); return sha(out.join("\n")); };
const SEEN = new Set(); const check = (dir, bundle, opts) => { const r = checkCertificate(dir, bundle, opts); for (const c of r.codes) SEEN.add(c); return r; };
const S = { baseline: readBundle(SHIPPED.baseline), historical: readBundle(SHIPPED.historical) };
const B0 = parse(S.baseline.bytes);

const tmp = mkdtempSync(join(tmpdir(), "g0-cert-")); process.on("exit", () => rmSync(tmp, { recursive: true, force: true }));
const copy = (name, of = "baseline") => { const d = join(tmp, name); cpSync(SHIPPED[of], d, { recursive: true }); return d; };
/** Rewrite the snapshot record of a copy (canonical bytes) and file it in the CAS, as a producer would. */
const rewriteSnapshot = (dir, mutate) => { const snap = parse(readFileSync(join(dir, "snapshot.json"))); const old = artifactRoot(snap); const next = mutate(snap) ?? snap; writeFileSync(join(dir, "snapshot.json"), canonicalWireBytes(next)); const root = putArtifact(join(dir, "cas"), next); if (root !== old && existsSync(join(dir, "cas", old + ".json"))) unlinkSync(join(dir, "cas", old + ".json")); return next; };
/** Edit ONE record on disk and re-seal the projection around it (line, CAS object, manifest entry, per-kind digest, ROOT) —
 *  the on-disk face of "a record edit moves the root". */
function editRecordOnDisk(dir, kind, lid, mutate) {
  const file = join(dir, `records/${kind}.jsonl`); const lines = readFileSync(file, "utf8").split("\n");
  const i = lines.findIndex((l) => l && JSON.parse(l).lid === lid); assert.ok(i >= 0, `${lid} is on disk`);
  const rec = JSON.parse(lines[i]); mutate(rec); lines[i] = canonicalBytesG0(rec).toString("utf8"); const bytes = Buffer.from(lines.join("\n"), "utf8"); writeFileSync(file, bytes); putArtifact(join(dir, "cas"), rec);
  const m = parse(readFileSync(join(dir, "manifest.json")));
  m.entries = m.entries.map(([l, h]) => (l === lid ? [l, hashOfBytes(Buffer.from(lines[i], "utf8"))] : [l, h])); m.per_kind = m.per_kind.map(([k, h]) => (k === kind ? [k, hashOfBytes(bytes)] : [k, h]));
  writeFileSync(join(dir, "manifest.json"), canonicalBytesG0(m)); const root = putArtifact(join(dir, "cas"), m); writeFileSync(join(dir, "ROOT"), root + "\n"); return root;
}

test("(1) same pinned snapshot + same projection ⇒ same certificate: a temp copy certifies twice to the SHIPPED bytes and VCLAIM; vclaim- re-derived by hand from the 3-plane preimage; gclaim-/gagg- re-derived from their preimages; the shipped certificate VERIFIES with zero refusals and cas_objects = entries + manifest + snapshot record", () => {
  const d = copy("det"); const c1 = buildCertificate(d), c2 = buildCertificate(d);
  assert.ok(c1.bytes.equals(c2.bytes)); assert.ok(c1.bytes.equals(S.baseline.bytes), "the copy certifies to the shipped bytes"); assert.equal(c1.verified_claim_sem_id, S.baseline.vclaim);
  const own = certificateOf(B0, CLAIM_FIELD); const pre = certificatePreimage(own);
  assert.equal("vclaim-" + sha(pre), S.baseline.vclaim, "hand-derived from the preimage bytes"); assert.equal(verifiedClaimSemId(own), S.baseline.vclaim);
  assert.ok(pre.toString("utf8").startsWith(CERTIFICATE_PROTOCOL + "|{\"aggregate_id\":\"gagg-")); assert.ok(pre.length > 500);
  const { [CLAIM_FIELD]: id, ...body } = B0.claim; assert.equal("gclaim-" + sha(Buffer.concat([Buffer.from(PROTOCOL + "|"), canonicalBytesG0({ protocol: PROTOCOL, ...body })])), id);
  const { aggregate_id, ...agg } = B0.aggregate; assert.equal("gagg-" + sha(Buffer.concat([Buffer.from(PROTOCOL + "|"), canonicalBytesG0(agg)])), aggregate_id);
  const r = check(SHIPPED.baseline); assert.equal(r.verdict, "VERIFIED"); assert.equal(r.ok, true); assert.deepEqual(r.codes, []); assert.equal(r.measured.verified_claim_sem_id, S.baseline.vclaim);
  assert.equal(r.measured.entries_checked, B0.aggregate.count); assert.equal(r.measured.cas_objects, B0.aggregate.count + 2); assert.equal(B0.structure.cas_objects, B0.aggregate.count + 2);
  assert.equal(B0.claim.projection_root, "root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85", "D-049: the frozen baseline root");
  assert.equal(B0.claim.snapshot_commitment, "gsnap-d67431565fa32b7de8a19b9bdda5e30adfcd74e54ce2eca2b97d41820b05146b", "R13 §7.2 [2] measured commitment");
  assert.deepEqual(B0.claim.scope, IMPLEMENTED_SCOPE); assert.equal(B0.chain_ids.trvm_commit, TRVM_PIN.commit); assert.equal(B0.chain_ids.trvm_blobs.length, Object.keys(TRVM_PIN.blobs).length);
});

test("(2) shuffled input traversal ⇒ same certificate: the snapshot commitment is order-independent over a seeded shuffle of sources and of every file list; a bundle whose keys are inserted in shuffled order canonicalises to the same bytes and checks identically", () => {
  const snap = parse(readFileSync(join(SHIPPED.baseline, "snapshot.json"))); const c0 = snapshotCommitment(snap);
  for (const seed of [3, 11, 42]) { const s = clone(snap); s.sources = shuffled(s.sources, seed).map((x) => ({ ...x, files: shuffled(x.files, seed + 1) })); assert.equal(snapshotCommitment(s), c0, `seed ${seed}`); }
  const shuffleKeys = (v, seed) => (Array.isArray(v) ? v.map((x) => shuffleKeys(x, seed)) : v && typeof v === "object" ? Object.fromEntries(shuffled(Object.entries(v), seed).map(([k, x]) => [k, shuffleKeys(x, seed + 1)])) : v);
  const sh = shuffleKeys(B0, 5); assert.notDeepEqual(Object.keys(sh), Object.keys(B0), "the object really is in a different order"); assert.ok(canonicalBytesG0(sh).equals(S.baseline.bytes));
  const r = check(SHIPPED.baseline, sh); assert.equal(r.verdict, "VERIFIED"); assert.equal(r.measured.stated_verified_claim_sem_id, S.baseline.vclaim);
});

test("(2b) A8 machinery: a projection REBUILT from the pinned registries with a seeded shuffle + reversed adapters certifies to the shipped VCLAIM and the shipped bundle bytes (needs the real tree; skipped from the zip)", (t) => {
  const d = join(tmp, "rebuilt");
  try { project(resolve(V, "snapshots/baseline.json"), { out: d, shuffleSeed: 7, reverseAdapters: true }); } catch (e) { t.skip("the pinned registries are not reachable here: " + e.message); return; }
  const c = buildCertificate(d); assert.equal(c.verified_claim_sem_id, S.baseline.vclaim); assert.ok(c.bytes.equals(S.baseline.bytes), "structure included — witness.json is outside every plane");
  assert.equal(check(d).verdict, "VERIFIED");
});

test("(3) an assertion (provenance) record edit that moves the projection root moves the certificate — in memory (root → claim → vclaim) and on disk (the edited copy re-certifies to a different VCLAIM; the shipped bundle against it is gproj-root-mismatch + gproj-certificate-stale, never VERIFIED)", () => {
  const d = copy("edit"); const a = readFileSync(join(d, "records/assertion.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)).find((x) => x.attrs && x.attrs.role);
  // in memory: the manifest entry alone moves the root (as wrl_world.test (3) measures), and the root moves the claim and the certificate
  const m = parse(readFileSync(join(d, "manifest.json"))); const edited = { ...a, attrs: { ...a.attrs, role: a.attrs.role + "-edited" } };
  const m2 = { ...m, entries: m.entries.map(([l, h]) => (l === a.lid ? [l, hashOfBytes(canonicalBytesG0(edited))] : [l, h])) }; const root2 = artifactRoot(m2); assert.notEqual(root2, B0.claim.projection_root);
  const vclaimFor = (root) => { const claim = reseal({ claim: { ...B0.claim, projection_root: root }, aggregate: clone(B0.aggregate), structure: clone(B0.structure) }).claim; assert.notEqual(claim[CLAIM_FIELD], B0.claim[CLAIM_FIELD]); return verifiedClaimSemId({ protocol: PROTOCOL, claim_sem_id: claim[CLAIM_FIELD], aggregate_id: B0.aggregate.aggregate_id, chain_ids: B0.chain_ids }); };
  assert.notEqual(vclaimFor(root2), S.baseline.vclaim);
  // on disk: the full re-seal (entry + per-kind digest) gives a third root; the certificate the copy mints is exactly the one that root implies
  const root3 = editRecordOnDisk(d, "assertion", a.lid, (r) => { r.attrs.role += "-edited"; }); assert.notEqual(root3, B0.claim.projection_root); assert.notEqual(root3, root2, "per_kind is in the manifest too");
  const c = buildCertificate(d); assert.equal(c.bundle.claim.projection_root, root3); assert.notEqual(c.verified_claim_sem_id, S.baseline.vclaim);
  assert.notEqual(c.bundle.aggregate.aggregate_id, B0.aggregate.aggregate_id, "the evidence aggregate moved too (per_kind carries the assertion file digest)"); assert.equal(c.bundle.claim[CLAIM_FIELD], claimSemId({ ...B0.claim, projection_root: root3 }));
  assert.equal(c.verified_claim_sem_id, verifiedClaimSemId({ protocol: PROTOCOL, claim_sem_id: c.bundle.claim[CLAIM_FIELD], aggregate_id: c.bundle.aggregate.aggregate_id, chain_ids: B0.chain_ids }), "the certificate is exactly what the moved root and moved aggregate imply under the unchanged chain");
  assert.equal(check(d).verdict, "VERIFIED", "the edited copy verifies under its own certificate");
  const r = check(d, S.baseline.bytes); assert.equal(r.verdict, "REFUSED"); assert.ok(r.codes.includes("gproj-root-mismatch") && r.codes.includes("gproj-certificate-stale"), r.codes.join());
});

test("(4) documentation-only / unbound edits hold: witness.json rewritten, a README added, an extra file dropped in, annotations reworded (and a new prose annotation) — the checker says VERIFIED with the same stated vclaim, and a rebuild certifies to the same VCLAIM", () => {
  const d = copy("prose"); writeFileSync(join(d, "witness.json"), JSON.stringify({ started_at: "1970-01-01T00:00:00Z", host: "elsewhere", head_drift: [{ repo: "x" }] }, null, 1)); writeFileSync(join(d, "README.md"), "# not bound\n"); writeFileSync(join(d, "NOTES.txt"), "prose");
  const c = buildCertificate(d); assert.equal(c.verified_claim_sem_id, S.baseline.vclaim); assert.ok(c.bytes.equals(S.baseline.bytes));
  const b = clone(B0); b.annotations.note = "reworded"; b.annotations.statement = "anything"; b.annotations.reviewer = ["a", "list", "of", "prose"]; delete b.annotations.generator;
  const r = check(d, b); assert.equal(r.verdict, "VERIFIED"); assert.equal(r.measured.stated_verified_claim_sem_id, S.baseline.vclaim);
  const noAnn = clone(B0); delete noAnn.annotations; delete noAnn.type; delete noAnn.version; assert.equal(check(d, noAnn).verdict, "VERIFIED", "type/version/annotations are optional and unread");
  assert.equal(verifiedClaimSemId(certificateOf(b, CLAIM_FIELD)), S.baseline.vclaim);
});

/** The field sweep (field_audit style): every grammar field classified and mutated. Re-sealed mutations (ids recomputed by
 *  the forger) must still be refused by the field's OWN code; NON_AUTHORITATIVE fields must hold. */
const SWEEP = [
  ["protocol", "CHECKED", (b) => { b.protocol = "GRAPHONOMOUS-PROJECTION-v1"; }, "gproj-protocol-mismatch"],
  ["protocol (any other string)", "CHECKED", (b) => { b.protocol = "TRVM-BOUNDED-PROOF-v1"; }, "gproj-protocol-mismatch"],
  ["type", "NON_AUTHORITATIVE", (b) => { b.type = "Warrant"; }, null],
  ["version", "NON_AUTHORITATIVE", (b) => { b.version = "9.9.9"; }, null],
  ["bundle.<extra>", "CHECKED", (b) => { b.warrant = true; }, "gproj-vocabulary-unknown"],
  ["claim.projection_root", "DERIVED", (b) => { b.claim.projection_root = "root-" + "0".repeat(64); }, "gproj-root-mismatch"],
  ["claim.snapshot_id", "DERIVED", (b) => { b.claim.snapshot_id = "snapshot:g0:other"; }, "gproj-snapshot-commitment-mismatch"],
  ["claim.snapshot_commitment", "DERIVED", (b) => { b.claim.snapshot_commitment = "gsnap-" + "1".repeat(64); }, "gproj-snapshot-commitment-mismatch"],
  ["claim.spec", "DERIVED", (b) => { b.claim.spec = "G0_G1_SPEC.md@2099-01-01"; }, "gproj-spec-mismatch"],
  ["claim.ruleset (absent)", "DERIVED", (b) => { delete b.claim.ruleset; }, "gproj-ruleset-missing"],
  ["claim.ruleset (other program)", "DERIVED", (b) => { b.claim.ruleset = "g0rule-" + "2".repeat(64); }, "gproj-ruleset-mismatch"],
  ["claim.schema_set_id", "DERIVED", (b) => { b.claim.schema_set_id = "gschema-" + "3".repeat(64); }, "gproj-schema-set-mismatch"],
  ["claim.adapter_contract_id", "DERIVED", (b) => { b.claim.adapter_contract_id = "gadapt-" + "4".repeat(64); }, "gproj-adapter-contract-mismatch"],
  ["claim.scope.kind", "CHECKED", (b) => { b.claim.scope.kind = "PROJECTION_TRUTH"; }, "gproj-scope-mismatch"],
  ["claim.scope.quantifier", "CHECKED", (b) => { b.claim.scope.quantifier = "OVER_ALL_SOURCES"; }, "gproj-scope-mismatch"],
  ["claim.scope.truth_claimed", "CHECKED", (b) => { b.claim.scope.truth_claimed = true; }, "gproj-scope-mismatch"],
  ["claim.scope.evidence_sufficiency_claimed", "CHECKED", (b) => { b.claim.scope.evidence_sufficiency_claimed = true; }, "gproj-scope-mismatch"],
  ["claim.scope.state_promoted", "CHECKED", (b) => { b.claim.scope.state_promoted = true; }, "gproj-scope-mismatch"],
  ["claim.scope.registry_written", "CHECKED", (b) => { b.claim.scope.registry_written = true; }, "gproj-scope-mismatch"],
  ["claim.scope.trvm_derivation", "CHECKED", (b) => { b.claim.scope.trvm_derivation = true; }, "gproj-scope-mismatch"],
  ["claim.scope.<extra>", "CHECKED", (b) => { b.claim.scope.proves_all_claims = true; }, "gproj-vocabulary-unknown"],
  ["claim.projection_claim_sem_id", "DERIVED", (b) => { b.claim[CLAIM_FIELD] = "gclaim-" + "5".repeat(64); }, "gproj-claim-id-mismatch", { noReseal: true }],
  ["claim.<extra>", "CHECKED", (b) => { b.claim.entails = "EVERYTHING"; }, "gproj-vocabulary-unknown"],
  ["chain_ids.trvm_commit", "CHECKED", (b) => { b.chain_ids.trvm_commit = "deadbeef".repeat(5); }, "gproj-chain-id-mismatch"],
  ["chain_ids.trvm_blobs", "CHECKED", (b) => { b.chain_ids.trvm_blobs = b.chain_ids.trvm_blobs.slice(1); }, "gproj-chain-id-mismatch"],
  ["chain_ids.trvm_blobs[].blob", "CHECKED", (b) => { b.chain_ids.trvm_blobs[0].blob = "0".repeat(40); }, "gproj-chain-id-mismatch"],
  ["chain_ids.trvm_blobs[].<extra>", "CHECKED", (b) => { b.chain_ids.trvm_blobs[0].verified = true; }, "gproj-vocabulary-unknown"],
  ["chain_ids.projector.id", "CHECKED", (b) => { b.chain_ids.projector.id = "graphonomous.g0.project.v9"; }, "gproj-chain-id-mismatch"],
  ["chain_ids.projector.code", "CHECKED", (b) => { b.chain_ids.projector.code = "gcode-" + "6".repeat(64); }, "gproj-chain-id-mismatch"],
  ["chain_ids.checker.id", "CHECKED", (b) => { b.chain_ids.checker.id = "someone.else"; }, "gproj-chain-id-mismatch"],
  ["chain_ids.checker.code", "CHECKED", (b) => { b.chain_ids.checker.code = "gcode-" + "7".repeat(64); }, "gproj-chain-id-mismatch"],
  ["chain_ids.<extra>", "CHECKED", (b) => { b.chain_ids.signer = "me"; }, "gproj-vocabulary-unknown"],
  ["references.contract.resolution", "CHECKED", (b) => { b.references.contract.resolution = "BY_NAME"; }, "gproj-reference-contract-mismatch"],
  ["references.contract.wire", "CHECKED", (b) => { b.references.contract.wire = "PRETTY"; }, "gproj-reference-contract-mismatch"],
  ["references.contract.address_is_a_warrant", "CHECKED", (b) => { b.references.contract.address_is_a_warrant = true; }, "gproj-reference-contract-mismatch"],
  ["references.operands[manifest].artifact_root", "DERIVED", (b) => { b.references.operands[0].artifact_root = "root-" + "8".repeat(64); }, "gproj-root-mismatch"],
  ["references.operands[snapshot].artifact_root", "DERIVED", (b) => { b.references.operands[1].artifact_root = "root-" + "9".repeat(64); }, "gproj-reference-mismatch"],
  ["references.operands[].role", "DERIVED", (b) => { b.references.operands[1].role = "derived"; }, "gproj-reference-mismatch"],
  ["references.operands (duplicate role)", "DERIVED", (b) => { b.references.operands.push({ ...b.references.operands[0] }); }, "gproj-reference-mismatch"],
  ["references.operands[].<extra>", "CHECKED", (b) => { b.references.operands[0].trusted = true; }, "gproj-vocabulary-unknown"],
  ["aggregate.count", "DERIVED", (b) => { b.aggregate.count += 1; }, "gproj-count-inconsistent"],
  ["aggregate.per_kind", "DERIVED", (b) => { b.aggregate.per_kind[0][1] = "sha256:" + "a".repeat(64); }, "gproj-count-inconsistent"],
  ["aggregate.faults.count", "DERIVED", (b) => { b.aggregate.faults.count = 0; }, "gproj-count-inconsistent"],
  ["aggregate.faults.digest", "DERIVED", (b) => { b.aggregate.faults.digest = "sha256:" + "b".repeat(64); }, "gproj-count-inconsistent"],
  ["aggregate.faults.by_code", "DERIVED", (b) => { b.aggregate.faults.by_code = []; }, "gproj-count-inconsistent"],
  ["aggregate.faults.<extra>", "CHECKED", (b) => { b.aggregate.faults.severity = "none"; }, "gproj-vocabulary-unknown"],
  ["aggregate.adapter_runs", "DERIVED", (b) => { b.aggregate.adapter_runs = []; }, "gproj-count-inconsistent"],
  ["aggregate.aggregate_id", "DERIVED", (b) => { b.aggregate.aggregate_id = "gagg-" + "c".repeat(64); }, "gproj-count-inconsistent", { noReseal: true }],
  ["aggregate.<extra>", "CHECKED", (b) => { b.aggregate.verdict = "VERIFIED"; }, "gproj-vocabulary-unknown"],
  ["structure.kinds", "DERIVED", (b) => { b.structure.kinds[0][1] += 1; }, "gproj-structure-mismatch"],
  ["structure.cas_objects", "DERIVED", (b) => { b.structure.cas_objects -= 1; }, "gproj-structure-mismatch"],
  ["structure.manifest_bytes", "DERIVED", (b) => { b.structure.manifest_bytes += 1; }, "gproj-structure-mismatch"],
  ["structure.structure_sem_id", "DERIVED", (b) => { b.structure.structure_sem_id = "gstruct-" + "d".repeat(64); }, "gproj-structure-mismatch", { noReseal: true }],
  ["structure.<extra>", "CHECKED", (b) => { b.structure.height = 1; }, "gproj-vocabulary-unknown"],
  ["annotations.note", "NON_AUTHORITATIVE", (b) => { b.annotations.note = "this certificate is a warrant"; }, null],
  ["annotations.<new prose>", "NON_AUTHORITATIVE", (b) => { b.annotations.ok = "true"; }, null],
  ["annotations.<non-prose>", "CHECKED", (b) => { b.annotations.ok = true; }, "gproj-vocabulary-unknown"],
];

test("(5a) field sweep over the shipped baseline — every grammar field classified DERIVED / CHECKED / NON_AUTHORITATIVE and mutated (re-sealed by the forger where an id sits beside it): each bound field refuses with its OWN code, NON_AUTHORITATIVE fields HOLD; the sweep covers every required field of every grammar record", () => {
  const covered = new Set(); const measured = [];
  for (const [field, cls, mutate, code, opts = {}] of SWEEP) {
    const b = clone(B0); mutate(b); if (!opts.noReseal) reseal(b);
    const r = check(SHIPPED.baseline, b); measured.push([field, cls, r.codes.join(",")]);
    if (code === null) { assert.equal(r.verdict, "VERIFIED", `${field} (${cls}) must HOLD: ${r.codes}`); assert.equal(r.measured.stated_verified_claim_sem_id, S.baseline.vclaim, `${field}: the certificate id held`); }
    else { assert.equal(r.verdict, "REFUSED", `${field} must be refused`); assert.ok(r.codes.includes(code), `${field}: expected ${code}, got [${r.codes}]`); }
    covered.add(field.replace(/ \(.*\)$/, "").replace(/\[.*?\]/g, "[]"));
  }
  // denominator from the checker's own vocabulary
  const required = [...GRAMMAR.bundle.required, ...GRAMMAR.bundle.optional, ...GRAMMAR.claim.required.map((k) => "claim." + k), ...GRAMMAR.scope.required.map((k) => "claim.scope." + k), ...GRAMMAR.chain_ids.required.map((k) => "chain_ids." + k),
    ...GRAMMAR.references.required.map((k) => "references." + k), ...GRAMMAR.reference_contract.required.map((k) => "references.contract." + k), ...GRAMMAR.aggregate.required.map((k) => "aggregate." + k), ...GRAMMAR.faults.required.map((k) => "aggregate.faults." + k), ...GRAMMAR.structure.required.map((k) => "structure." + k)];
  const hit = (f) => [...covered].some((c) => c === f || c.startsWith(f + ".") || c.startsWith(f + "["));
  const missing = required.filter((f) => !hit(f)); assert.deepEqual(missing, [], `every grammar field is swept; missing ${missing}`);
  assert.ok(new Set(measured.map((m) => m[2])).size > 8, "the codes are distinct per family, not one blanket refusal");
});

test("(5b) directory-level forgeries on temp copies — dropped source, added source, duplicate source, reordered sources (commitment and certificate HOLD; only the transport-plane reference moves), unpinned source, a wrong/absent/pretty-printed/invalid-UTF-8/garbage CAS object, an edited record line, a missing snapshot record, a relabelled snapshot, an adapter that is not the one that ran, and a directory that is not a projection (gproj-checker-threw): each refuses with the named code", () => {
  const snapOf = (d) => parse(readFileSync(join(d, "snapshot.json")));
  const codesOn = (name, mutate) => { const d = copy(name); mutate(d); const r = check(d, S.baseline.bytes); assert.equal(r.verdict, "REFUSED", name); return r.codes; };
  const has = (codes, c, what) => assert.ok(codes.includes(c), `${what}: expected ${c}, got [${codes}]`);
  has(codesOn("drop", (d) => rewriteSnapshot(d, (s) => { s.sources = s.sources.filter((x) => x.namespace !== "trvm"); })), "gproj-snapshot-commitment-mismatch", "dropped source");
  has(codesOn("add", (d) => rewriteSnapshot(d, (s) => { s.sources.push({ ...s.sources[0], namespace: "extra", registry: "registry:extra:x@000000000000" }); })), "gproj-snapshot-commitment-mismatch", "added source");
  has(codesOn("dup", (d) => rewriteSnapshot(d, (s) => { s.sources.push(clone(s.sources[0])); })), "gproj-snapshot-commitment-mismatch", "duplicate source");
  assert.throws(() => snapshotCommitment({ sources: [snapOf(SHIPPED.baseline).sources[0], snapOf(SHIPPED.baseline).sources[0]] }), (e) => e.code === "G0_SET_DUPLICATE");
  // reorder: the commitment, the claim and the certificate HOLD; the snapshot record's bytes (and so its root) differ
  const ro = copy("reorder"); const before = snapOf(ro); rewriteSnapshot(ro, (s) => { s.sources = s.sources.slice().reverse(); s.sources.forEach((x) => { x.files = x.files.slice().reverse(); }); });
  assert.notDeepEqual(snapOf(ro).sources.map((s) => s.namespace), before.sources.map((s) => s.namespace)); assert.equal(snapshotCommitment(snapOf(ro)), B0.claim.snapshot_commitment);
  const cro = buildCertificate(ro); assert.equal(cro.verified_claim_sem_id, S.baseline.vclaim, "reordered sources: the certificate HOLDS"); assert.deepEqual(cro.bundle.claim, B0.claim); assert.notEqual(cro.bundle.references.operands[1].artifact_root, B0.references.operands[1].artifact_root, "the snapshot record is a different artifact");
  const rro = check(ro, S.baseline.bytes); assert.deepEqual(rro.codes, ["gproj-reference-mismatch"], "the old bundle against the reordered copy fails ONLY on the transport plane"); assert.equal(rro.measured.stated_verified_claim_sem_id, rro.measured.verified_claim_sem_id);
  has(codesOn("unpinned", (d) => rewriteSnapshot(d, (s) => { delete s.sources[0].files[0].blob; })), "gproj-source-unpinned", "unpinned file");
  has(codesOn("untree", (d) => rewriteSnapshot(d, (s) => { s.sources[1].tree = "not-an-oid"; })), "gproj-source-unpinned", "unpinned tree");
  has(codesOn("relabel", (d) => rewriteSnapshot(d, (s) => { s.id = "snapshot:g0:relabelled"; })), "gproj-snapshot-commitment-mismatch", "relabelled snapshot record");
  const rec0 = JSON.parse(readFileSync(join(SHIPPED.baseline, "records/node.jsonl"), "utf8").split("\n")[0]); const root0 = artifactRoot(rec0);
  has(codesOn("cas-missing", (d) => unlinkSync(join(d, "cas", root0 + ".json"))), "gproj-artifact-unresolvable", "absent CAS object");
  has(codesOn("cas-pretty", (d) => writeFileSync(join(d, "cas", root0 + ".json"), JSON.stringify(rec0, null, 1))), "gproj-artifact-non-canonical", "pretty-printed CAS object");
  has(codesOn("cas-utf8", (d) => writeFileSync(join(d, "cas", root0 + ".json"), Buffer.from([0x7b, 0x22, 0xff, 0x22, 0x7d]))), "gproj-artifact-invalid-utf8", "invalid UTF-8 CAS object");
  has(codesOn("cas-wrong", (d) => writeFileSync(join(d, "cas", root0 + ".json"), canonicalWireBytes({ ...rec0, kind: "FORGED" }))), "gproj-artifact-root-mismatch", "wrong bytes under a root");
  has(codesOn("cas-garbage", (d) => writeFileSync(join(d, "cas", root0 + ".json"), "not json")), "gproj-artifact-malformed", "garbage CAS object");
  has(codesOn("line", (d) => { const f = join(d, "records/node.jsonl"); const ls = readFileSync(f, "utf8").split("\n"); ls[0] = ls[0].replace(/"kind":"/, "\"kind\":\"X"); writeFileSync(f, ls.join("\n")); }), "gproj-entry-mismatch", "edited record line");
  has(codesOn("snap-missing", (d) => unlinkSync(join(d, "cas", artifactRoot(snapOf(d)) + ".json"))), "gproj-artifact-unresolvable", "snapshot record not in the CAS");
  has(codesOn("adapter", (d) => { const f = join(d, "records/adapter_run.jsonl"); const r = parse(readFileSync(f)); r.adapter.digest.gitBlob = "0".repeat(40); writeFileSync(f, canonicalBytesG0(r)); }), "gproj-adapter-contract-mismatch", "adapter run record names a blob that is not on disk");
  const rt = check(join(tmp, "nowhere"), S.baseline.bytes); assert.deepEqual(rt.codes, ["gproj-checker-threw"]); assert.equal(rt.verdict, "REFUSED");
  const rm = check(SHIPPED.baseline, Buffer.from("{}")); assert.deepEqual(rm.codes, ["gproj-protocol-mismatch"], "a canonical empty object is a protocol mismatch, not a crash");
});

test("(6) baseline and historical certificates coexist: each VERIFIES against its own directory, each refuses the other's bundle (gproj-root-mismatch + gproj-certificate-stale) and the other's VCLAIM as a citation (gproj-certificate-stale + gproj-citation-cross-wired); the child check locates a projection by its cited root among the directories the verifier holds — the G0-F precondition that an older certificate stays checkable beside a newer one", () => {
  const H0 = parse(S.historical.bytes); assert.notEqual(S.historical.vclaim, S.baseline.vclaim); assert.equal(H0.claim.projection_root, "root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87", "D-049: the frozen historical root");
  for (const name of ["baseline", "historical"]) { const r = check(SHIPPED[name]); assert.equal(r.verdict, "VERIFIED", name); assert.equal(r.measured.verified_claim_sem_id, S[name].vclaim); }
  assert.equal(H0.claim.ruleset, B0.claim.ruleset); assert.equal(H0.claim.schema_set_id, B0.claim.schema_set_id); assert.equal(H0.claim.adapter_contract_id, B0.claim.adapter_contract_id); assert.deepEqual(H0.chain_ids, B0.chain_ids); assert.notEqual(H0.claim.snapshot_commitment, B0.claim.snapshot_commitment);
  for (const [dir, other] of [[SHIPPED.baseline, "historical"], [SHIPPED.historical, "baseline"]]) {
    const r = check(dir, S[other].bytes); assert.equal(r.verdict, "REFUSED"); for (const c of ["gproj-root-mismatch", "gproj-certificate-stale", "gproj-snapshot-commitment-mismatch"]) assert.ok(r.codes.includes(c), `${other} bundle vs ${dir}: ${c} in [${r.codes}]`);
    const own = parse(S[other === "baseline" ? "historical" : "baseline"].bytes); const rc = check(dir, own, { cited: { verified_claim_sem_id: S[other].vclaim, protocol: PROTOCOL, claim_sem_id: parse(S[other].bytes).claim[CLAIM_FIELD], aggregate_id: parse(S[other].bytes).aggregate.aggregate_id } });
    assert.deepEqual(rc.codes, ["gproj-certificate-stale", "gproj-citation-cross-wired"], "the right bundle under the wrong citation");
  }
  const dirs = Object.values(SHIPPED); assert.equal(checkGraphonomousChild(H0, { dirs }).verdict, "VERIFIED"); assert.equal(checkGraphonomousChild(B0, { dirs }).verdict, "VERIFIED");
  const none = checkGraphonomousChild(H0, { dirs: [SHIPPED.baseline] }); assert.deepEqual(none.codes, ["gproj-root-mismatch"]);
  const entry = childProtocolEntry(dirs); assert.deepEqual({ claim_field: entry.claim_field, composed: entry.composed, checker_id: entry.checker_id }, { claim_field: CLAIM_FIELD, composed: false, checker_id: CHECKER_ID }); assert.equal(entry.check(B0).verdict, "VERIFIED");
});

test("(7) not a warrant: a check writes nothing (directory digest identical before/after, measured.writes = 0); a forged annotations.ok = true is refused as vocabulary and mints no VERIFIED; a getter that lies on its second read is severed by ownership (the verdict is about the one canonical read); possession of a vclaim confers nothing — there is no registry to consult", () => {
  const before = dirDigest(SHIPPED.baseline);
  const r = check(SHIPPED.baseline); const forged = clone(B0); forged.annotations.ok = true; const rf = check(SHIPPED.baseline, forged);
  assert.equal(dirDigest(SHIPPED.baseline), before); assert.equal(r.measured.writes, 0); assert.equal(rf.verdict, "REFUSED"); assert.deepEqual(rf.codes, ["gproj-vocabulary-unknown"]);
  assert.ok(!existsSync(join(SHIPPED.baseline, "certificate", "ACCEPTED")) && !readdirSync(V).some((f) => /registry|accepted/i.test(f)), "no registry of accepted certificates exists");
  let reads = 0; const lying = clone(B0); Object.defineProperty(lying.references.contract, "address_is_a_warrant", { enumerable: true, get() { return reads++ === 0 ? false : true; } });
  const rl = check(SHIPPED.baseline, lying); assert.equal(rl.verdict, "VERIFIED"); assert.equal(lying.references.contract.address_is_a_warrant, true, "the object now says true; the verdict was about the single canonical read");
  assert.equal(dirDigest(SHIPPED.baseline), before);
});

test("(8) the bundle bytes are canonical G0 bytes = TRVM canonical wire bytes; stored through the TRVM CAS they resolve `ok` under the artifact root; pretty-printed bytes are refused at ingress (gproj-ingress-refused) and by the CAS (non-canonical-wire); a non-canonical object is taken into ownership and judged on its canonical form", () => {
  for (const name of ["baseline", "historical"]) {
    const { bytes } = S[name]; const obj = parse(bytes);
    assert.ok(canonicalBytesG0(obj).equals(bytes)); assert.ok(canonicalWireBytes(obj).equals(bytes)); assert.equal(Buffer.from(trvmCanonicalBytes(obj), "utf8").length, bytes.length);
    const store = memoryStore(new Map()); const root = store.put(obj); assert.equal(root, artifactRoot(obj)); assert.equal(resolveArtifact(store, root).outcome, "ok");
    const pretty = Buffer.from(JSON.stringify(obj, null, 2), "utf8"); assert.deepEqual(check(SHIPPED[name], pretty).codes, ["gproj-ingress-refused"]);
    store.entries.set(root, pretty); assert.equal(resolveArtifact(store, root).outcome, "non-canonical-wire");
    assert.deepEqual(check(SHIPPED[name], Buffer.from([0xff, 0xfe])).codes, ["gproj-ingress-refused"]); assert.deepEqual(check(SHIPPED[name], "a string").codes, ["gproj-ingress-refused"]);
  }
});

test("chain: the bundle's chain_ids equal the LIVE pin table + code identities (never read from the bundle); schema_set_id is over the 12 schemas; the derived record from the directory equals the shipped bundle plane for plane", () => {
  assert.deepEqual(B0.chain_ids, liveChainIds()); assert.equal(schemaSetId().files.length, 12); assert.equal(B0.claim.schema_set_id, schemaSetId().id);
  const { refusals, derived } = deriveFromDirectory(SHIPPED.baseline); assert.deepEqual(refusals, []);
  assert.deepEqual(derived.claim, B0.claim); assert.deepEqual(derived.aggregate, B0.aggregate); assert.deepEqual(derived.structure, B0.structure); assert.deepEqual(derived.references, B0.references); assert.equal(derived.verified_claim_sem_id, S.baseline.vclaim);
});

test("refusal vocabulary: every code the checker can emit is declared, every code measured in this file is declared, and every R13 §6 code was measured at least once", () => {
  const src = readFileSync(resolve(V, "lib/certificate.mjs"), "utf8"); const emitted = new Set([...src.matchAll(/"(gproj-[a-z-]+)"/g)].map((m) => m[1]));
  for (const c of emitted) assert.ok(REFUSAL_CODES.includes(c), `${c} is emitted but not declared`);
  for (const c of SEEN) assert.ok(REFUSAL_CODES.includes(c), `${c} measured but not declared`);
  const r13 = REFUSAL_CODES.slice(0, 21); const unmeasured = r13.filter((c) => !SEEN.has(c)); assert.deepEqual(unmeasured, [], `R13 codes never measured: ${unmeasured}`);
});
