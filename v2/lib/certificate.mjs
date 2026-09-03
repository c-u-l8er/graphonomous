/* certificate.mjs — G0-D: the `GRAPHONOMOUS-PROJECTION-v0` projection certificate (D-054, D-055, R13 §6).
 *
 * WHAT IT CERTIFIES. Reconstruction identity, not truth: *under these pinned source identities (the snapshot commitment),
 * this ingestion code (adapter contract), these record schemas, this rule program id and this canonical-byte discipline
 * (the TRVM pin), the projection directory reconstructs to exactly this root, and the relations the checker requires
 * hold.* The `scope` record says in refusable values what it does NOT mean: no claim is true, no evidence is sufficient,
 * no state is promoted, no registry is written, no TRVM derivation happened. `verified_claim_sem_id` is TRVM's
 * `verifiedClaimSemId` over (protocol, projection_claim_sem_id, aggregate_id, chain_ids) — the same certificate identity
 * the TRVM leaf protocols carry, so a TRVM nest bundle can cite it (after TRVM-P0, with `childProtocolEntry(dirs)`).
 *
 * FIVE PLANES, exact key sets, extras refused (TRVM `schema.mjs grammar`):
 *   protocol     CHECKED                                                    claim  SEMANTIC — every field DERIVED here
 *   chain_ids    CHECKED against the LIVE pin table + LIVE code identities   references  TRANSPORT (content addresses)
 *   aggregate    EVIDENCE — DERIVED from the manifest and the record files   structure   SHAPE — in the root, outside
 *   annotations  NON_AUTHORITATIVE prose (strings only)                                  the certificate
 *
 * RELATIONS, NOT VALUES (TRVM live_dag.mjs). `checkCertificate` re-derives EVERYTHING from the projection directory it is
 * handed — root through the CAS over every manifest entry, snapshot commitment from the resolved snapshot record, the
 * schema/adapter/projector/checker code identities from the files on disk, the aggregate from the record files, the chain
 * from `TRVM_PIN` — and compares the bundle to that, field by field. It writes nothing, keeps nothing, issues nothing:
 * possession of a `vclaim-` confers no authority (D-054), and there is no registry of accepted certificates anywhere.
 *
 * DEVIATIONS FROM R13 §6, with reasons:
 *   1. `chain_ids.trvm_blobs` is a SET of `{file, blob}` records, not a `{path: blob}` map — a path is not a G0 record key
 *      (`canon.mjs KEY_RE`), and the bundle is written in canonical G0 bytes. Same shape as `wrl_world.mjs` identities.
 *   2. `adapter_contract_id` is over the adapters the projection's OWN `adapter_run` records name (`file:adapters/…`),
 *      each paired with the LIVE blob of that file (refused `gproj-adapter-contract-mismatch` when the run record's blob
 *      and the file disagree) — R13 [3] measured over the whole adapters directory. Reason: G0-F adds a second adapter,
 *      and D-054 requires the pre-G0-F certificate to stay checkable; an adapter that never ran is not part of what
 *      reconstructed this projection. `adapters/git.mjs` (the pinned read contract) is in the projector code id instead.
 *   3. `projector` / `checker` chain entries are records `{id, code}`: the declared version id plus a `gcode-` identity over
 *      the blob OIDs of the modules (the checker cannot hash itself, so its entry hashes the modules it imports).
 *   4. Codes beyond the R13 list, each a distinct fault the list left unnamed: `gproj-ruleset-mismatch`,
 *      `gproj-schema-set-mismatch`, `gproj-adapter-contract-mismatch`, `gproj-reference-contract-mismatch`,
 *      `gproj-reference-mismatch`, `gproj-structure-mismatch`. Folding them into a neighbour would hide which bound value
 *      moved; R13's own rule is "own code per fault".
 *   5. `snapshot_commitment` excludes the factory source's `repo_dir` — a LOCATOR, not an identity (its commit, tree and
 *      blobs are the identity). `snapshot_id` (the label) is bound separately, so a relabelled snapshot is a different claim.
 *
 * WHAT BINDING MEANS. `schema_set_id`, `adapter_contract_id` and the projector/checker code ids are relations to the code
 * on disk, exactly as TRVM's `chainIds()`: editing a schema, an adapter that ran, or a projector module re-mints the
 * certificate (the old one refuses by name). A LATER SNAPSHOT does not: the baseline certificate checks against
 * `projections/baseline/` for as long as that code is unchanged — the G0-F precondition (test 6). */
import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { canonicalBytesG0, hashOfBytes, sha256Hex, sortSet, gitBlobOid, G0Error, artifactRoot, TRVM_PIN, assertTrvmPinned } from "./canon.mjs";
import { verifiedClaimSemId, certificateOf, CERTIFICATE_PROTOCOL } from "../../../TRVM/governance/certificate.mjs";
import { grammar, publicResult, ownSnapshot } from "../../../TRVM/governance/schema.mjs";
import { putArtifact, resolveArtifact, directoryStore, canonicalWireBytes, isRoot, WIRE_LIMITS } from "../../../TRVM/governance/cas.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(HERE, "..");

export const PROTOCOL = "GRAPHONOMOUS-PROJECTION-v0";
export const CLAIM_FIELD = "projection_claim_sem_id";
export const CHECKER_ID = "graphonomous.g0.certificate.v0";
export const PROJECTOR_ID = "graphonomous.g0.project.v0";
export const BUNDLE_VERSION = "0.1.0";
/** D-054's "must not mean" list as refusable values; compared value for value like IMPLEMENTED_NEST_SCOPE. */
export const IMPLEMENTED_SCOPE = Object.freeze({
  kind: "PROJECTION_RECONSTRUCTION_IDENTITY", quantifier: "OVER_THE_PINNED_SOURCE_SET",
  truth_claimed: false, evidence_sufficiency_claimed: false, state_promoted: false, registry_written: false, trvm_derivation: false,
});
export const IMPLEMENTED_REFERENCE_CONTRACT = Object.freeze({ resolution: "CONTENT_ADDRESSED", wire: "CANONICAL", address_is_a_warrant: false });
export const REFERENCE_ROLES = Object.freeze(["manifest", "snapshot"]);
/** The code whose blobs the chain names. The projector set is what builds a projection; the checker set is what this module
 *  imports from this tree (TRVM is named by the pin). Edit either → the certificate re-mints. */
export const PROJECTOR_MODULES = Object.freeze(["adapters/git.mjs", "lib/canon.mjs", "lib/emit.mjs", "lib/lid.mjs", "lib/project.mjs", "lib/rules.mjs", "lib/schema.mjs"]);
export const CHECKER_IMPORTS = Object.freeze(["lib/canon.mjs"]);
export const RECORD_KINDS = Object.freeze(["node", "relation", "assertion", "source_location", "fault", "adapter_run"]);

/** The grammar — declared here, not imported (TRVM nest_check.mjs:178). Exported so a field sweep can derive its denominator. */
export const GRAMMAR = Object.freeze({
  bundle: { required: ["protocol", "claim", "chain_ids", "references", "aggregate", "structure"], optional: ["type", "version", "annotations"] },
  claim: { required: ["projection_root", "snapshot_id", "snapshot_commitment", "spec", "ruleset", "schema_set_id", "adapter_contract_id", "scope", CLAIM_FIELD], optional: [] },
  scope: { required: Object.keys(IMPLEMENTED_SCOPE), optional: [] },
  chain_ids: { required: ["trvm_commit", "trvm_blobs", "projector", "checker"], optional: [] },
  trvm_blob: { required: ["file", "blob"], optional: [] },
  code: { required: ["id", "code"], optional: [] },
  references: { required: ["contract", "operands"], optional: [] },
  reference_contract: { required: Object.keys(IMPLEMENTED_REFERENCE_CONTRACT), optional: [] },
  reference: { required: ["role", "artifact_root"], optional: [] },
  aggregate: { required: ["count", "per_kind", "faults", "adapter_runs", "aggregate_id"], optional: [] },
  faults: { required: ["count", "digest", "by_code"], optional: [] },
  structure: { required: ["kinds", "cas_objects", "manifest_bytes", "structure_sem_id"], optional: [] },
});
export const REFUSAL_CODES = Object.freeze([
  "gproj-root-mismatch", "gproj-snapshot-commitment-mismatch", "gproj-source-unpinned",
  "gproj-artifact-unresolvable", "gproj-artifact-non-canonical", "gproj-artifact-invalid-utf8", "gproj-artifact-root-mismatch", "gproj-artifact-malformed",
  "gproj-entry-mismatch", "gproj-protocol-mismatch", "gproj-spec-mismatch", "gproj-ruleset-missing", "gproj-chain-id-mismatch",
  "gproj-certificate-stale", "gproj-citation-cross-wired", "gproj-ingress-refused", "gproj-vocabulary-unknown", "gproj-claim-id-mismatch",
  "gproj-count-inconsistent", "gproj-scope-mismatch", "gproj-checker-threw",
  // deviation 4
  "gproj-ruleset-mismatch", "gproj-schema-set-mismatch", "gproj-adapter-contract-mismatch", "gproj-reference-contract-mismatch", "gproj-reference-mismatch", "gproj-structure-mismatch",
]);

/* ─────────────────────────────────────────── identities ─────────────────────────────────────────── */
const H = (...parts) => sha256Hex(Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : Buffer.from(p, "utf8")))));
const tag = (t) => Buffer.from(PROTOCOL + "|" + (t ? t + "|" : ""), "utf8");
const HEX40 = /^[0-9a-f]{40}$/, HEX64 = /^[0-9a-f]{64}$/;

/** One source's identity: what pins it, never where it lives (`repo_dir` is a locator). Files are a set. */
export const sourceIdentity = (s) => ({ namespace: s.namespace, registry: s.registry, repo: s.repo, commit: s.commit, tree: s.tree, files: sortSet(s.files.map((f) => ({ path: f.path, blob: f.blob, sha256: f.sha256, bytes: f.bytes })), "files") });
/** `gsnap-`: the SET of source identities — order-independent, dropped-source-sensitive, duplicate refused (G0_SET_DUPLICATE). */
export const snapshotCommitment = (snapshot) => "gsnap-" + H(tag("snapshot"), canonicalBytesG0(sortSet(snapshot.sources.map(sourceIdentity), "sources")));
/** A name each source (and each file) must satisfy to count as pinned. Returns the first problem or null. */
export function unpinnedSource(s) {
  for (const k of ["namespace", "registry", "repo"]) if (typeof s?.[k] !== "string" || !s[k]) return `source ${JSON.stringify(s?.namespace)}: ${k} missing`;
  if (!HEX40.test(s.commit ?? "")) return `source ${s.namespace}: commit is not a git oid`;
  if (!HEX40.test(s.tree ?? "")) return `source ${s.namespace}: tree is not a git oid`;
  if (!Array.isArray(s.files)) return `source ${s.namespace}: files is not a list`;
  for (const f of s.files) { if (typeof f?.path !== "string" || !f.path) return `source ${s.namespace}: a file without a path`; if (!HEX40.test(f.blob ?? "")) return `source ${s.namespace}:${f.path} has no blob oid`; if (!HEX64.test(f.sha256 ?? "")) return `source ${s.namespace}:${f.path} has no sha256`; if (!Number.isSafeInteger(f.bytes) || f.bytes < 0) return `source ${s.namespace}:${f.path} has no byte length`; }
  return null;
}
const blobPairs = (files) => files.map((f) => [f, gitBlobOid(readFileSync(resolve(ROOT_DIR, f)))]);
/** `gschema-`: the 12 record schemas, [file, blob] in name order (R13 [3] preimage). Measured live. */
export function schemaSetId() { const files = readdirSync(resolve(ROOT_DIR, "schemas")).filter((f) => f.endsWith(".schema.json")).sort().map((f) => "schemas/" + f); return { id: "gschema-" + H(canonicalBytesG0(blobPairs(files).map(([f, b]) => [f.slice("schemas/".length), b]))), files }; }
/** `gcode-`: a code identity over [path, blob] pairs of live modules. */
export const codeId = (files) => "gcode-" + H(canonicalBytesG0(blobPairs(files)));
/** `gadapt-`: the adapters the projection's run records name, with their LIVE blobs (deviation 2). */
export function adapterContractId(runs) {
  const problems = []; const pairs = [];
  for (const r of runs) {
    const uri = r?.adapter?.uri ?? ""; const rel = uri.startsWith("file:") ? uri.slice(5) : null;
    if (!rel || !rel.startsWith("adapters/") || rel.includes("..")) { problems.push(`${r?.lid}: adapter uri ${JSON.stringify(uri)} is not a file under adapters/`); continue; }
    if (!existsSync(resolve(ROOT_DIR, rel))) { problems.push(`${r?.lid}: ${rel} is not on disk`); continue; }
    const live = gitBlobOid(readFileSync(resolve(ROOT_DIR, rel)));
    if (live !== r?.adapter?.digest?.gitBlob) problems.push(`${r?.lid}: ran ${rel} at blob ${r?.adapter?.digest?.gitBlob}, the file on disk is blob ${live}`);
    pairs.push([rel, live]);
  }
  return { id: "gadapt-" + H(canonicalBytesG0(sortSet(pairs, "adapters"))), pairs: sortSet(pairs, "adapters"), problems };
}
/** The live chain: the TRVM pin + the projector and checker code ids. Never read from a bundle. */
export function liveChainIds() {
  return { trvm_commit: TRVM_PIN.commit, trvm_blobs: sortSet(Object.entries(TRVM_PIN.blobs).map(([file, blob]) => ({ file, blob })), "trvm_blobs"),
    projector: { id: PROJECTOR_ID, code: codeId(PROJECTOR_MODULES) }, checker: { id: CHECKER_ID, code: codeId(CHECKER_IMPORTS) } };
}
export const claimSemId = (claim) => { const { [CLAIM_FIELD]: _omit, ...body } = claim; return "gclaim-" + H(tag(""), canonicalBytesG0({ protocol: PROTOCOL, ...body })); };
export const aggregateId = (agg) => { const { aggregate_id: _omit, ...body } = agg; return "gagg-" + H(tag(""), canonicalBytesG0(body)); };
export const structureSemId = (st) => { const { structure_sem_id: _omit, ...body } = st; return "gstruct-" + H(tag("structure"), canonicalBytesG0(body)); };
/** The certificate preimage TRVM hashes — exposed so a test can re-derive `vclaim-` by hand (R13 §7.1 [2]). */
export const certificatePreimage = (cert) => Buffer.from(CERTIFICATE_PROTOCOL + "|" + canonicalWireBytes({ certificate_protocol: CERTIFICATE_PROTOCOL, protocol: cert.protocol, claim_sem_id: cert.claim_sem_id, aggregate_id: cert.aggregate_id, chain_ids: cert.chain_ids }).toString("utf8"), "utf8");

/* ─────────────────────────────────────── derivation from the directory ─────────────────────────────────────── */
const CAS_CODE = { unresolvable: "gproj-artifact-unresolvable", "non-canonical-wire": "gproj-artifact-non-canonical", "invalid-utf8": "gproj-artifact-invalid-utf8", "root-mismatch": "gproj-artifact-root-mismatch", "bad-root-syntax": "gproj-artifact-malformed", "too-large": "gproj-artifact-malformed", malformed: "gproj-artifact-malformed" };
const readJsonl = (p) => (existsSync(p) ? readFileSync(p) : Buffer.alloc(0));
const lines = (buf) => buf.toString("utf8").split("\n").filter(Boolean);

/** Re-derive every plane of the certificate from a projection directory. Reads only; returns `{refusals, derived}` where
 *  `derived` is complete whenever the directory could be read at all (so a checker can still say which field disagreed). */
export function deriveFromDirectory(dir) {
  const refusals = []; const refuse = (code, detail) => refusals.push({ code, detail });
  const store = directoryStore(join(dir, "cas"));
  // the manifest and the root, through the CAS
  const manifestBytes = readFileSync(join(dir, "manifest.json")); let manifest;
  try { manifest = JSON.parse(manifestBytes.toString("utf8")); } catch (e) { throw new G0Error("MANIFEST_UNREADABLE", String(e?.message ?? e)); }
  if (!canonicalWireBytes(manifest).equals(manifestBytes)) refuse("gproj-artifact-non-canonical", "manifest.json is not the canonical encoding of what it parses to");
  const root = artifactRoot(manifest);
  const rootFile = existsSync(join(dir, "ROOT")) ? readFileSync(join(dir, "ROOT"), "utf8").trim() : null;
  if (rootFile !== root) refuse("gproj-root-mismatch", `ROOT says ${rootFile}, the manifest's canonical bytes hash to ${root}`);
  const mres = resolveArtifact(store, root); if (mres.outcome !== "ok") refuse(CAS_CODE[mres.outcome] ?? "gproj-artifact-malformed", `manifest: ${mres.detail}`);
  else if (!mres.bytes.equals(manifestBytes)) refuse("gproj-artifact-root-mismatch", "the CAS object under the root is not manifest.json byte for byte");
  // every entry: stored bytes hash to the manifest entry, and resolve through the CAS
  let index = {}; try { index = Object.fromEntries(JSON.parse(readFileSync(join(dir, "records_index.json"), "utf8")).map((e) => [e.lid, e])); } catch { refuse("gproj-entry-mismatch", "records_index.json is missing or unreadable"); }
  const files = {}; for (const k of RECORD_KINDS) files[`records/${k}.jsonl`] = readJsonl(join(dir, `records/${k}.jsonl`));
  const fileLines = Object.fromEntries(Object.entries(files).map(([k, b]) => [k, lines(b)]));
  let checked = 0; const entries = Array.isArray(manifest.entries) ? manifest.entries : [];
  for (const [lid, hash] of entries) {
    const loc = index[lid]; if (!loc || !fileLines[loc.file]) { refuse("gproj-entry-mismatch", `${lid}: no record on disk`); continue; }
    const line = fileLines[loc.file][loc.line]; if (line === undefined) { refuse("gproj-entry-mismatch", `${lid}: index points past the end of ${loc.file}`); continue; }
    if (hashOfBytes(Buffer.from(line, "utf8")) !== hash) { refuse("gproj-entry-mismatch", `${lid}: stored bytes hash ${hashOfBytes(Buffer.from(line, "utf8")).slice(0, 24)}…, manifest says ${String(hash).slice(0, 24)}…`); continue; }
    let rec; try { rec = JSON.parse(line); } catch { refuse("gproj-artifact-malformed", `${lid}: the stored line does not parse`); continue; }
    if (rec.lid !== lid) refuse("gproj-entry-mismatch", `${lid}: the record on that line is ${rec.lid}`);
    const r = resolveArtifact(store, artifactRoot(rec)); if (r.outcome !== "ok") refuse(CAS_CODE[r.outcome] ?? "gproj-artifact-malformed", `${lid}: ${r.detail}`);
    checked++;
  }
  // the snapshot record: on disk, in the CAS, pinned, labelled as the manifest says
  let snapshot = null, snapshotRoot = null, snapshotCommitmentId = null;
  if (!existsSync(join(dir, "snapshot.json"))) refuse("gproj-artifact-unresolvable", "snapshot.json is not in the projection directory");
  else {
    const sbytes = readFileSync(join(dir, "snapshot.json"));
    try { snapshot = JSON.parse(sbytes.toString("utf8")); } catch { refuse("gproj-artifact-malformed", "snapshot.json does not parse"); }
    if (snapshot) {
      if (!canonicalWireBytes(snapshot).equals(sbytes)) refuse("gproj-artifact-non-canonical", "snapshot.json is not the canonical encoding of what it parses to");
      snapshotRoot = artifactRoot(snapshot);
      const sres = resolveArtifact(store, snapshotRoot); if (sres.outcome !== "ok") refuse(CAS_CODE[sres.outcome] ?? "gproj-artifact-malformed", `snapshot record: ${sres.detail}`);
      if (snapshot.id !== manifest.snapshot) refuse("gproj-snapshot-commitment-mismatch", `the snapshot record is ${snapshot.id}, the manifest was built from ${manifest.snapshot}`);
      const sources = Array.isArray(snapshot.sources) ? snapshot.sources : [];
      let unpinned = 0; for (const s of sources) { const p = unpinnedSource(s); if (p) { unpinned++; refuse("gproj-source-unpinned", p); } }
      if (!unpinned) try { snapshotCommitmentId = snapshotCommitment(snapshot); } catch (e) { refuse("gproj-snapshot-commitment-mismatch", `the source set has no commitment: ${e.code ?? e.message}`); }
    }
  }
  // the code the claim binds
  const schemas = schemaSetId();
  const runs = fileLines["records/adapter_run.jsonl"].map((l) => JSON.parse(l));
  const adapters = adapterContractId(runs); for (const p of adapters.problems) refuse("gproj-adapter-contract-mismatch", p);
  if (typeof manifest.ruleset !== "string" || !manifest.ruleset) refuse("gproj-ruleset-missing", "the manifest names no rule program; the claim requires one");
  // the chain
  let chain = null; try { assertTrvmPinned(); chain = liveChainIds(); } catch (e) { refuse("gproj-chain-id-mismatch", `the pinned TRVM files on disk are not the pinned blobs: ${e.message}`); }
  // the aggregate, re-derived from the record files rather than believed from the manifest
  const perKind = RECORD_KINDS.map((k) => [k, hashOfBytes(files[`records/${k}.jsonl`])]).sort();
  const faultRecs = fileLines["records/fault.jsonl"].map((l) => JSON.parse(l)); const byCode = {}; for (const f of faultRecs) byCode[f.code] = (byCode[f.code] || 0) + 1;
  const aggregate = { count: entries.length, per_kind: perKind, faults: { count: faultRecs.length, digest: hashOfBytes(files["records/fault.jsonl"]), by_code: Object.entries(byCode).sort() }, adapter_runs: sortSet(runs.map((r) => hashOfBytes(canonicalBytesG0(r))), "adapter_runs") };
  const stable = (v) => canonicalBytesG0(v).toString("utf8");
  for (const k of Object.keys(aggregate)) if (stable(aggregate[k]) !== (manifest[k] === undefined ? null : stable(manifest[k]))) refuse("gproj-count-inconsistent", `manifest.${k} says ${JSON.stringify(manifest[k]).slice(0, 80)}, the record files derive ${JSON.stringify(aggregate[k]).slice(0, 80)}`);
  aggregate.aggregate_id = aggregateId(aggregate);
  // the structure
  const kinds = RECORD_KINDS.map((k) => [k, fileLines[`records/${k}.jsonl`].length]);
  const casObjects = existsSync(join(dir, "cas")) ? readdirSync(join(dir, "cas")).filter((f) => /^root-[0-9a-f]{64}\.json$/.test(f)).length : 0;
  const structure = { kinds, cas_objects: casObjects, manifest_bytes: manifestBytes.length }; structure.structure_sem_id = structureSemId(structure);
  // the claim
  const claim = { projection_root: root, snapshot_id: manifest.snapshot ?? null, snapshot_commitment: snapshotCommitmentId, spec: manifest.spec ?? null, ruleset: manifest.ruleset ?? null, schema_set_id: schemas.id, adapter_contract_id: adapters.id, scope: { ...IMPLEMENTED_SCOPE } };
  claim[CLAIM_FIELD] = claimSemId(claim);
  const derived = { root, manifest, manifest_bytes: manifestBytes.length, entries_checked: checked, snapshot, snapshot_root: snapshotRoot, claim, chain_ids: chain, aggregate, structure, schema_files: schemas.files, adapter_pairs: adapters.pairs,
    references: { contract: { ...IMPLEMENTED_REFERENCE_CONTRACT }, operands: [{ role: "manifest", artifact_root: root }, { role: "snapshot", artifact_root: snapshotRoot }] } };
  derived.verified_claim_sem_id = chain && snapshotCommitmentId ? verifiedClaimSemId({ protocol: PROTOCOL, claim_sem_id: claim[CLAIM_FIELD], aggregate_id: aggregate.aggregate_id, chain_ids: chain }) : null;
  return { refusals, derived };
}

/* ───────────────────────────────────────────── the producer ───────────────────────────────────────────── */
/** Put the snapshot identity record into the projection's CAS beside the manifest (NOT a manifest entry — the root does
 *  not move; D-049). Idempotent. Returns the record's root. */
export function putSnapshotRecord(dir) {
  const bytes = readFileSync(join(dir, "snapshot.json")); const snapshot = JSON.parse(bytes.toString("utf8"));
  if (!canonicalWireBytes(snapshot).equals(bytes)) throw new G0Error("SNAPSHOT_NON_CANONICAL", "snapshot.json is not canonical bytes");
  return putArtifact(join(dir, "cas"), snapshot);
}
/** Build `<dir>/certificate/{bundle.json, VCLAIM}` (canonical G0 bytes). Throws on any derivation refusal — a producer
 *  never writes a certificate over a projection that does not reconstruct. */
export function buildCertificate(dir, { out = join(dir, "certificate") } = {}) {
  putSnapshotRecord(dir);
  const { refusals, derived: d } = deriveFromDirectory(dir);
  if (refusals.length) throw new G0Error("CERTIFICATE_REFUSED", refusals.map((r) => `${r.code}: ${r.detail}`).slice(0, 5).join("; "), { refusals });
  const bundle = { type: "ProjectionCertificate", version: BUNDLE_VERSION, protocol: PROTOCOL, claim: d.claim, chain_ids: d.chain_ids, references: d.references, aggregate: d.aggregate, structure: d.structure,
    annotations: { note: "NON-AUTHORITATIVE — nothing in this record is hashed, checked, or established", generator: "graphonomous/v2 lib/certificate.mjs " + BUNDLE_VERSION,
      statement: `under the pinned source set ${d.claim.snapshot_commitment.slice(0, 24)}… this projection reconstructs to ${d.root.slice(0, 24)}…; not a warrant, not a truth claim` } };
  const bytes = canonicalBytesG0(bundle);
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "bundle.json"), bytes);
  writeFileSync(join(out, "VCLAIM"), d.verified_claim_sem_id + "\n");
  return { bundle, bytes, verified_claim_sem_id: d.verified_claim_sem_id, artifact_root: artifactRoot(bundle), derived: d };
}

/* ────────────────────────────────────────────── the checker ────────────────────────────────────────────── */
const THREW = Symbol("threw"); const safe = (f) => { try { return f(); } catch { return THREW; } };
const stableText = (v) => { try { return canonicalWireBytes(v).toString("utf8"); } catch { return "undefined"; } };
const codesOf = (refusals) => [...new Set(refusals.map((r) => r.code))].sort();
const result = (refusals, measured) => { const r = publicResult({ refusals, measured: { ...measured, refusal_codes: codesOf(refusals), writes: 0 } }); r.codes = codesOf(refusals); return r; };

/** Take the bundle into the checker's ownership: bytes must be canonical; an object is canonicalised once and re-parsed. */
function ingress(bundleOrBytes) {
  if (Buffer.isBuffer(bundleOrBytes) || bundleOrBytes instanceof Uint8Array) {
    const bytes = Buffer.from(bundleOrBytes);
    if (bytes.length > WIRE_LIMITS.max_artifact_bytes) return { refusal: `${bytes.length} octets, over the ${WIRE_LIMITS.max_artifact_bytes}-octet ceiling — bounded before decoding` };
    let obj; try { obj = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); } catch (e) { return { refusal: `the octets are not a canonical artifact: ${String(e?.message ?? e)}` }; }
    let canon; try { canon = canonicalWireBytes(obj); } catch (e) { return { refusal: `no canonical form: ${String(e?.message ?? e)}` }; }
    if (!canon.equals(bytes)) return { refusal: `the octets are not the canonical UTF-8 encoding of what they parse to (${bytes.length} received, ${canon.length} canonical)` };
    return { bundle: obj, bytes: bytes.length };
  }
  if (bundleOrBytes === null || typeof bundleOrBytes !== "object") return { refusal: `this boundary takes an artifact record or its octets; it was handed a ${bundleOrBytes === null ? "null" : typeof bundleOrBytes}` };
  try { const owned = ownSnapshot(bundleOrBytes); return { bundle: owned, bytes: canonicalWireBytes(owned).length }; }
  catch (e) { return { refusal: `the artifact has no canonical form and cannot be taken into this verifier's ownership: ${String(e?.message ?? e)}` }; }
}

/**
 * Check a certificate against a projection directory. `bundleOrBytes` defaults to `<dir>/certificate/bundle.json` (bytes);
 * `cited` (a `vclaim-` string, or `{verified_claim_sem_id, protocol?, claim_sem_id?, aggregate_id?}`) defaults to
 * `<dir>/certificate/VCLAIM` when present and `null` to skip the citation comparison. Writes nothing. Returns TRVM's public
 * result shape `{ok, verdict, evidence_verdict, refusals, measured}` plus `codes`.
 */
export function checkCertificate(dir, bundleOrBytes, { cited } = {}) {
  const measured = { checker_id: CHECKER_ID, protocol: PROTOCOL, directory: dir };
  try {
    if (bundleOrBytes === undefined) { const p = join(dir, "certificate", "bundle.json"); if (!existsSync(p)) return result([{ code: "gproj-ingress-refused", detail: `${p} does not exist` }], measured); bundleOrBytes = readFileSync(p); }
    if (cited === undefined) cited = existsSync(join(dir, "certificate", "VCLAIM")) ? readFileSync(join(dir, "certificate", "VCLAIM"), "utf8").trim() : null;
    if (typeof cited === "string") cited = { verified_claim_sem_id: cited };
    const ing = ingress(bundleOrBytes); if (ing.refusal) return result([{ code: "gproj-ingress-refused", detail: ing.refusal }], measured);
    const bundle = ing.bundle; measured.bundle_bytes = ing.bytes;
    const refusals = []; const refuse = (code, detail) => refusals.push({ code, detail });
    if (bundle?.protocol !== PROTOCOL) { refuse("gproj-protocol-mismatch", `protocol ${JSON.stringify(bundle?.protocol)}; this checker implements ${PROTOCOL}`); return result(refusals, measured); }
    const vocab = (record, spec, where) => { for (const v of grammar(record, spec, where)) refuse("gproj-vocabulary-unknown", v.detail); };
    vocab(bundle, GRAMMAR.bundle, "bundle");
    if (bundle.annotations !== undefined) {
      const flat = (v) => typeof v === "string" || (Array.isArray(v) && v.every((x) => typeof x === "string"));
      if (bundle.annotations === null || typeof bundle.annotations !== "object" || Array.isArray(bundle.annotations) || !Object.values(bundle.annotations).every(flat))
        refuse("gproj-vocabulary-unknown", "annotations is the NON-AUTHORITATIVE seat and holds prose only (strings, or lists of strings)");
    }
    const claim = bundle.claim ?? {}; vocab(claim, GRAMMAR.claim, "claim"); vocab(claim.scope, GRAMMAR.scope, "claim.scope");
    const chain = bundle.chain_ids ?? {}; vocab(chain, GRAMMAR.chain_ids, "chain_ids");
    if (Array.isArray(chain.trvm_blobs)) chain.trvm_blobs.forEach((b, i) => vocab(b, GRAMMAR.trvm_blob, `chain_ids.trvm_blobs[${i}]`)); else refuse("gproj-vocabulary-unknown", "chain_ids.trvm_blobs is not a list");
    vocab(chain.projector, GRAMMAR.code, "chain_ids.projector"); vocab(chain.checker, GRAMMAR.code, "chain_ids.checker");
    const references = bundle.references ?? {}; vocab(references, GRAMMAR.references, "references"); vocab(references.contract, GRAMMAR.reference_contract, "references.contract");
    const refs = Array.isArray(references.operands) ? references.operands : []; refs.forEach((r, i) => vocab(r, GRAMMAR.reference, `references.operands[${i}]`));
    const agg = bundle.aggregate ?? {}; vocab(agg, GRAMMAR.aggregate, "aggregate"); vocab(agg.faults, GRAMMAR.faults, "aggregate.faults");
    const st = bundle.structure ?? {}; vocab(st, GRAMMAR.structure, "structure");

    // everything the directory says, derived once, owned by this call
    const { refusals: dirRefusals, derived: d } = deriveFromDirectory(dir); refusals.push(...dirRefusals);
    Object.assign(measured, { projection_root: d.root, snapshot_id: d.claim.snapshot_id, snapshot_commitment: d.claim.snapshot_commitment, snapshot_root: d.snapshot_root, spec: d.claim.spec, ruleset: d.claim.ruleset,
      schema_set_id: d.claim.schema_set_id, adapter_contract_id: d.claim.adapter_contract_id, projection_claim_sem_id: d.claim[CLAIM_FIELD], aggregate_id: d.aggregate.aggregate_id, chain_ids: d.chain_ids,
      verified_claim_sem_id: d.verified_claim_sem_id, entries_checked: d.entries_checked, entries: d.manifest.entries?.length ?? 0, cas_objects: d.structure.cas_objects, sources: d.snapshot?.sources?.length ?? 0,
      files_pinned: d.snapshot?.sources?.reduce((n, s) => n + (s.files?.length ?? 0), 0) ?? 0, structure: d.structure });

    // the claim plane, field by field
    if (claim.projection_root !== d.root) refuse("gproj-root-mismatch", `claim.projection_root ${String(claim.projection_root).slice(0, 24)}…, this directory reconstructs to ${d.root.slice(0, 24)}…`);
    if (claim.snapshot_id !== d.claim.snapshot_id) refuse("gproj-snapshot-commitment-mismatch", `claim.snapshot_id ${JSON.stringify(claim.snapshot_id)}, the manifest was built from ${JSON.stringify(d.claim.snapshot_id)}`);
    if (d.claim.snapshot_commitment && claim.snapshot_commitment !== d.claim.snapshot_commitment) refuse("gproj-snapshot-commitment-mismatch", `claim.snapshot_commitment ${String(claim.snapshot_commitment).slice(0, 24)}…, the pinned source set commits to ${d.claim.snapshot_commitment.slice(0, 24)}…`);
    if (claim.spec !== d.claim.spec) refuse("gproj-spec-mismatch", `claim.spec ${JSON.stringify(claim.spec)}, the manifest says ${JSON.stringify(d.claim.spec)}`);
    if (typeof claim.ruleset !== "string" || !claim.ruleset) refuse("gproj-ruleset-missing", "claim.ruleset is required");
    else if (d.claim.ruleset && claim.ruleset !== d.claim.ruleset) refuse("gproj-ruleset-mismatch", `claim.ruleset ${claim.ruleset.slice(0, 24)}…, the manifest says ${d.claim.ruleset.slice(0, 24)}…`);
    if (claim.schema_set_id !== d.claim.schema_set_id) refuse("gproj-schema-set-mismatch", `claim.schema_set_id ${String(claim.schema_set_id).slice(0, 24)}…, the ${d.schema_files.length} schemas on disk are ${d.claim.schema_set_id.slice(0, 24)}…`);
    if (claim.adapter_contract_id !== d.claim.adapter_contract_id) refuse("gproj-adapter-contract-mismatch", `claim.adapter_contract_id ${String(claim.adapter_contract_id).slice(0, 24)}…, the adapters that ran are ${d.claim.adapter_contract_id.slice(0, 24)}… on disk`);
    for (const k of Object.keys(IMPLEMENTED_SCOPE)) if (claim.scope?.[k] !== IMPLEMENTED_SCOPE[k]) refuse("gproj-scope-mismatch", `scope.${k} is ${JSON.stringify(claim.scope?.[k])}, this checker implements ${JSON.stringify(IMPLEMENTED_SCOPE[k])}`);
    const statedClaimId = safe(() => claimSemId(claim));
    if (statedClaimId !== claim[CLAIM_FIELD]) refuse("gproj-claim-id-mismatch", `${CLAIM_FIELD} does not identify the claim record beside it`);
    // the chain: the live table, never the bundle's
    if (d.chain_ids) for (const k of GRAMMAR.chain_ids.required) if (stableText(chain[k]) !== stableText(d.chain_ids[k])) refuse("gproj-chain-id-mismatch", `chain_ids.${k} says ${JSON.stringify(chain[k]).slice(0, 80)}, this checker's live chain is ${JSON.stringify(d.chain_ids[k]).slice(0, 80)}`);
    // the reference plane: the contract, and exactly one root per role
    for (const k of Object.keys(IMPLEMENTED_REFERENCE_CONTRACT)) if (references.contract?.[k] !== IMPLEMENTED_REFERENCE_CONTRACT[k]) refuse("gproj-reference-contract-mismatch", `references.contract.${k} is ${JSON.stringify(references.contract?.[k])}, this checker implements ${JSON.stringify(IMPLEMENTED_REFERENCE_CONTRACT[k])}`);
    const byRole = new Map(); for (const r of refs) { if (byRole.has(r?.role)) refuse("gproj-reference-mismatch", `two references for role ${JSON.stringify(r?.role)}`); byRole.set(r?.role, r); }
    for (const role of REFERENCE_ROLES) { const want = d.references.operands.find((o) => o.role === role).artifact_root; const got = byRole.get(role)?.artifact_root; if (!isRoot(got)) refuse("gproj-reference-mismatch", `references.operands has no well-formed root for role ${role}`); else if (want && got !== want) refuse(role === "manifest" ? "gproj-root-mismatch" : "gproj-reference-mismatch", `references.operands[${role}] cites ${got.slice(0, 24)}…, this directory's ${role} record is ${want.slice(0, 24)}…`); }
    for (const role of byRole.keys()) if (!REFERENCE_ROLES.includes(role)) refuse("gproj-reference-mismatch", `a reference for role ${JSON.stringify(role)} this checker does not implement`);
    // the evidence plane
    for (const k of ["count", "per_kind", "faults", "adapter_runs"]) if (stableText(agg[k]) !== stableText(d.aggregate[k])) refuse("gproj-count-inconsistent", `aggregate.${k} says ${JSON.stringify(agg[k]).slice(0, 80)}, this checker derives ${JSON.stringify(d.aggregate[k]).slice(0, 80)}`);
    if (safe(() => aggregateId(agg)) !== agg.aggregate_id) refuse("gproj-count-inconsistent", "aggregate_id does not identify the aggregate beside it");
    // the structure plane
    for (const k of ["kinds", "cas_objects", "manifest_bytes"]) if (stableText(st[k]) !== stableText(d.structure[k])) refuse("gproj-structure-mismatch", `structure.${k} says ${JSON.stringify(st[k])}, this checker derives ${JSON.stringify(d.structure[k])}`);
    if (safe(() => structureSemId(st)) !== st.structure_sem_id) refuse("gproj-structure-mismatch", "structure_sem_id does not identify the structure beside it");
    // the certificate: what the bundle names vs what this directory names, then vs the citation
    const own = certificateOf(bundle, CLAIM_FIELD); const stated = safe(() => verifiedClaimSemId(own));
    measured.stated_verified_claim_sem_id = stated === THREW ? null : stated;
    if (stated === THREW) refuse("gproj-certificate-stale", "the bundle is missing a field the certificate identity binds and cannot be NAMED");
    else if (d.verified_claim_sem_id && stated !== d.verified_claim_sem_id) refuse("gproj-certificate-stale", `the bundle names ${stated.slice(0, 24)}…, this directory under this checker's chain names ${d.verified_claim_sem_id.slice(0, 24)}…`);
    if (cited && stated !== THREW) {
      if (cited.verified_claim_sem_id !== stated) refuse("gproj-certificate-stale", `cited ${String(cited.verified_claim_sem_id).slice(0, 24)}…, the bundle computes ${stated.slice(0, 24)}…`);
      for (const f of ["protocol", "claim_sem_id", "aggregate_id"]) if (cited[f] !== undefined && cited[f] !== own[f]) refuse("gproj-citation-cross-wired", `the citation says ${f} ${JSON.stringify(cited[f])}, the bundle's own is ${JSON.stringify(own[f])}`);
    }
    return result(refusals, measured);
  } catch (e) {
    return result([{ code: "gproj-checker-threw", detail: `the checker raised instead of refusing: ${String(e?.message ?? e)}` }], measured);
  }
}

/** The leaf `check` a TRVM nest verifier may supply after TRVM-P0: locate the projection among the directories THIS
 *  verifier holds by the root the child claims (a lookup, never a warrant — everything is re-derived from that directory),
 *  then run the checker. No directory reconstructs to the cited root → `gproj-root-mismatch`. */
export function checkGraphonomousChild(child, { dirs = [] } = {}) {
  const want = child?.claim?.projection_root;
  const dir = dirs.find((d) => existsSync(join(d, "ROOT")) && readFileSync(join(d, "ROOT"), "utf8").trim() === want);
  if (!dir) return result([{ code: "gproj-root-mismatch", detail: `no projection held by this verifier reconstructs to ${String(want).slice(0, 24)}… (${dirs.length} held)` }], { checker_id: CHECKER_ID, protocol: PROTOCOL });
  return checkCertificate(dir, child, { cited: null });
}
/** The exact `child_protocols` entry Graphonomous supplies: `{ "GRAPHONOMOUS-PROJECTION-v0": childProtocolEntry(dirs) }`. */
export const childProtocolEntry = (dirs) => Object.freeze({ claim_field: CLAIM_FIELD, check: (child) => checkGraphonomousChild(child, { dirs }), composed: false, checker_id: CHECKER_ID });
