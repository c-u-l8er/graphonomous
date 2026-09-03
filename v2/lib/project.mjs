/* project.mjs — the projector: folds adapter assertions into nodes and relations, validates every record against its
 * schema, hashes, refuses lid collisions, writes the canonical-JSON directory, stores every record and the manifest in
 * the TRVM CAS, and publishes the projection root (spec §6.6, §9). Deterministic by construction: every set is sorted
 * by canonical bytes, every file is written in lid order, nothing run-dependent enters a hashed byte (witness fields
 * live in witness.json outside the digest). */
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { hostname } from "node:os";
import { canonicalBytesG0, hashRecord, hashOfBytes, sha256Hex, sortSet, gitBlobOid, G0Error, artifactRoot } from "./canon.mjs";
import { putArtifact, resolveArtifact, directoryStore } from "../../../TRVM/governance/cas.mjs";
import { compile } from "./schema.mjs";
import { LidTable, parseLid, checkRelationEndpoints } from "./lid.mjs";
import { loadRules } from "./rules.mjs";
import { openRepo } from "../adapters/git.mjs";
import { ingestCrosswalk } from "../adapters/crosswalk.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(HERE, "..");
const SPEC_ID = "G0_G1_SPEC.md@2026-09-02";
const schema = Object.fromEntries(["node", "relation", "assertion", "source_location", "fault", "snapshot", "adapter_run", "manifest"].map((n) => [n, compile(JSON.parse(readFileSync(resolve(ROOT_DIR, "schemas", n + ".schema.json"), "utf8")))]));
const canonKey = (v) => canonicalBytesG0(v).toString("utf8");
const byBytes = (a, b) => Buffer.compare(canonicalBytesG0(a), canonicalBytesG0(b));

/** Deterministic shuffle (for the reconstruction gate): a seeded LCG permutation, not Math.random. */
export function shuffled(arr, seed) {
  const a = arr.slice(); let s = (seed >>> 0) || 1;
  for (let i = a.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) >>> 0; const j = s % (i + 1); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

/** Fold assertions about one lid into one record. Conflicts are faults, never silent picks: the first value in
 *  assertion-lid order is kept and the key is listed under attr_conflicts. */
function fold(kind, items, faults, snapshot, namespace) {
  const byLid = new Map();
  for (const it of items) { if (!byLid.has(it.lid)) byLid.set(it.lid, []); byLid.get(it.lid).push(it); }
  const out = [];
  for (const [lid, group] of byLid) {
    group.sort((a, b) => a.assertion.lid < b.assertion.lid ? -1 : a.assertion.lid > b.assertion.lid ? 1 : Buffer.compare(canonicalBytesG0(a.attrs || {}), canonicalBytesG0(b.attrs || {})));
    const first = group[0]; const rec = { lid, kind: first.kind, basis: "observed", snapshot, attrs: {} };
    if (kind === "relation") { rec.source = first.source; rec.target = first.target; if (first.qualifier) rec.qualifier = first.qualifier; }
    const conflicts = new Set(); let evidence_state = null;
    for (const g of group) {
      if (g.kind !== first.kind) { faults.push(mkFault(namespace, "CONTRADICTION", "projector.fold.kind", `${lid}: asserted as ${first.kind} and ${g.kind}`, [lid], snapshot, faults)); continue; }
      if (kind === "relation" && (g.source !== first.source || g.target !== first.target)) { faults.push(mkFault(namespace, "CONTRADICTION", "projector.fold.endpoints", `${lid}: endpoints differ between assertions`, [lid], snapshot, faults)); continue; }
      for (const [k, v] of Object.entries(g.attrs || {})) {
        if (!(k in rec.attrs)) rec.attrs[k] = v;
        else if (canonKey(rec.attrs[k]) !== canonKey(v)) conflicts.add(k);
      }
      const es = g.assertion.attrs?.evidence_state;
      if (es) { if (!evidence_state) evidence_state = es; else if (canonKey(es) !== canonKey(evidence_state)) conflicts.add("evidence_state"); }
    }
    if (conflicts.size) { rec.attrs.attr_conflicts = [...conflicts].sort(); faults.push(mkFault(namespace, "CONTRADICTION", "projector.fold.attrs", `${lid}: assertions disagree on ${[...conflicts].sort().join(", ")}`, [lid], snapshot, faults)); }
    if (evidence_state) rec.evidence_state = evidence_state;
    rec.assertions = sortSet([...new Set(group.map((g) => g.assertion.lid))]);
    out.push(rec);
  }
  return out;
}
let faultSeq = 0;
const mkFault = (ns, code, rule, message, concerns, snapshot) => ({ lid: `fault:${ns}:${code}:p${++faultSeq}`, code, rule, message, concerns: sortSet([...new Set(concerns)]), snapshot });

export function loadSnapshot(path) {
  const snap = JSON.parse(readFileSync(path, "utf8"));
  const errs = schema.snapshot(snap); if (errs.length) throw new G0Error("SNAPSHOT_SCHEMA", errs.map((e) => `${e.instancePath} ${e.message}`).join("; "));
  return snap;
}

/** Open every source repo at its pinned commit and verify the recorded blob OIDs. */
export function openSources(snap) {
  const repos = {}; const drift = [];
  for (const s of snap.sources) {
    const repo = openRepo(s.repo, s.repo_dir || resolve(ROOT_DIR, "../..", s.repo), s.commit);
    if (s.tree && repo.tree !== s.tree) throw new G0Error("SOURCE_MOVED", `${s.repo}@${s.commit}: tree ${repo.tree} != recorded ${s.tree}`);
    for (const f of s.files) { const got = repo.blobOid(f.path); if (got !== f.blob) throw new G0Error("SOURCE_MOVED", `${s.repo}@${s.commit.slice(0, 7)}:${f.path} is blob ${got}, recorded ${f.blob}`); }
    repos[s.namespace] = repo; if (repo.head !== repo.commit) drift.push({ repo: s.repo, head: repo.head, pinned: repo.commit });
  }
  return { repos, drift };
}

/**
 * Build a projection. opts: { out, shuffleSeed?, reverseAdapters?, quiet? }. Returns the manifest + root.
 * The adapters list is data so the order can be reversed by the reconstruction gate.
 */
export function project(snapshotPath, opts = {}) {
  const started = new Date().toISOString(); faultSeq = 0;
  const snap = loadSnapshot(snapshotPath); const snapshot = snap.id;
  const { repos, drift } = openSources(snap);
  const packageDir = snap.params?.package_dir; if (!packageDir) throw new G0Error("SNAPSHOT_PARAMS", "snapshot.params.package_dir is required");
  const treeRegistries = Object.fromEntries(snap.sources.map((s) => [s.namespace, s.registry]));
  const adapters = [{ name: "crosswalk", file: "adapters/crosswalk.mjs", run: () => ingestCrosswalk({ snapshot, repos, packageDir, treeRegistries }) }];
  const order = opts.reverseAdapters ? adapters.slice().reverse() : adapters;
  let nodesIn = [], relsIn = [], faultsIn = [], locsIn = []; const runs = [];
  for (const ad of order) {
    const res = ad.run();
    for (const part of Object.values(res).filter((p) => p && p.nodes)) { nodesIn.push(...part.nodes); relsIn.push(...part.relations); faultsIn.push(...part.faults); locsIn.push(...part.locations); }
    const adapterBytes = readFileSync(resolve(ROOT_DIR, ad.file));
    runs.push({ lid: `run:g0:${ad.name}`, adapter: { uri: `file:${ad.file}`, digest: { gitBlob: gitBlobOid(adapterBytes) } }, inputs: sortSet(snap.sources.flatMap((s) => s.files.map((f) => ({ uri: `git:${s.repo}@${s.commit}:${f.path}`, digest: { gitBlob: f.blob } })))), params: { package_dir: packageDir, order_index: order.indexOf(ad) }, snapshot, outputs: { records: 0, faults: 0 } });
  }
  if (opts.shuffleSeed !== undefined) { nodesIn = shuffled(nodesIn, opts.shuffleSeed); relsIn = shuffled(relsIn, opts.shuffleSeed + 1); faultsIn = shuffled(faultsIn, opts.shuffleSeed + 2); locsIn = shuffled(locsIn, opts.shuffleSeed + 3); }
  const faults = faultsIn.map((f) => ({ ...f }));
  const nodes = fold("node", nodesIn, faults, snapshot, "g0");
  const relations = fold("relation", relsIn, faults, snapshot, "g0");
  // D-037: a projection may never contain a SUPERSEDES / STATE_TRANSITION_OF over a refused endpoint pair (the emitter
  // already refuses it; this is the projection-time guard, loud, never a silent record)
  for (const r of relations) try { checkRelationEndpoints(r.kind, r.source, r.target); } catch (e) { throw new G0Error("ENDPOINT_REFUSED", e.message); }
  // relation endpoints must exist as nodes or locations
  const nodeLids = new Set(nodes.map((n) => n.lid)); const locByLid = new Map();
  for (const l of locsIn) { const prev = locByLid.get(l.lid); if (!prev) locByLid.set(l.lid, l); else if (canonKey(prev) !== canonKey(l)) { faults.push(mkFault("g0", "CONTRADICTION", "projector.locations", `${l.lid}: two emitters describe one location differently`, [l.lid], snapshot)); if (Buffer.compare(canonicalBytesG0(l), canonicalBytesG0(prev)) < 0) locByLid.set(l.lid, l); } }
  for (const r of relations) for (const end of [r.source, r.target]) if (!nodeLids.has(end) && !locByLid.has(end)) faults.push(mkFault("g0", "UNRESOLVED_LINK", "projector.endpoints", `${r.lid}: endpoint ${end} is not a node in this projection`, [r.lid], snapshot));
  const assertions = [...nodesIn, ...relsIn].map((x) => x.assertion);
  const assertionByLid = new Map();
  for (const a of assertions) {
    const prev = assertionByLid.get(a.lid);
    if (!prev) { assertionByLid.set(a.lid, a); continue; }
    if (canonKey(prev) !== canonKey(a)) { faults.push(mkFault("g0", "DUPLICATE_ID", "projector.assertions", `${a.lid} asserted twice with different content`, [a.lid], snapshot)); if (Buffer.compare(canonicalBytesG0(a), canonicalBytesG0(prev)) < 0) assertionByLid.set(a.lid, a); }
  }
  // faults get deterministic lids: sort by content, then number
  const faultRecords = faults.map(({ lid, ...rest }) => rest).sort(byBytes).map((f, i) => ({ lid: `fault:g0:${f.code}:${String(i + 1).padStart(4, "0")}`, ...f }));
  // validate + hash + write
  const kinds = { node: nodes, relation: relations, assertion: [...assertionByLid.values()], source_location: [...locByLid.values()], fault: faultRecords, adapter_run: runs };
  const table = new LidTable(); const entries = []; const index = []; const files = {}; const perKind = []; const schemaFaults = [];
  const out = opts.out; if (out) { rmSync(out, { recursive: true, force: true }); mkdirSync(join(out, "records"), { recursive: true }); }
  for (const [kind, recs] of Object.entries(kinds)) {
    const validator = schema[kind]; const witness = validator.witnessFields;
    const prepared = recs.map((r) => { const { identity, hash } = hashRecord(r, { witness_fields: witness }); return { identity, hash }; }).sort((a, b) => a.identity.lid < b.identity.lid ? -1 : a.identity.lid > b.identity.lid ? 1 : 0);
    const lines = [];
    prepared.forEach((p, i) => {
      const errs = validator(p.identity); if (errs.length) schemaFaults.push({ kind, lid: p.identity.lid, errors: errs.slice(0, 5) });
      parseLid(p.identity.lid); table.add(p.identity.lid, p.hash);
      lines.push(canonicalBytesG0(p.identity).toString("utf8")); entries.push([p.identity.lid, p.hash]); index.push({ lid: p.identity.lid, file: `records/${kind}.jsonl`, line: i });
      if (out) putArtifact(join(out, "cas"), p.identity);
    });
    const bytes = Buffer.from(lines.join("\n"), "utf8"); files[`records/${kind}.jsonl`] = bytes; perKind.push([kind, hashOfBytes(bytes)]);
  }
  if (schemaFaults.length) throw new G0Error("RECORD_SCHEMA", JSON.stringify(schemaFaults.slice(0, 3), null, 1) + (schemaFaults.length > 3 ? ` … +${schemaFaults.length - 3}` : ""));
  entries.sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
  const byCode = {}; for (const f of faultRecords) byCode[f.code] = (byCode[f.code] || 0) + 1;
  const ruleset = loadRules().rule_sem_id;
  const manifest = { kind: "graphonomous.projection", spec: SPEC_ID, snapshot, ruleset, entries, count: entries.length, per_kind: perKind.sort(), faults: { count: faultRecords.length, digest: hashOfBytes(files["records/fault.jsonl"]), by_code: Object.entries(byCode).sort() }, adapter_runs: sortSet(runs.map((r) => hashRecord(r, { witness_fields: schema.adapter_run.witnessFields }).hash)) };
  const merrs = schema.manifest(manifest); if (merrs.length) throw new G0Error("MANIFEST_SCHEMA", merrs.map((e) => `${e.instancePath} ${e.message}`).join("; "));
  const root = artifactRoot(manifest);
  if (out) {
    for (const [rel, bytes] of Object.entries(files)) writeFileSync(join(out, rel), bytes);
    writeFileSync(join(out, "manifest.json"), canonicalBytesG0(manifest));
    writeFileSync(join(out, "records_index.json"), canonicalBytesG0(index));
    writeFileSync(join(out, "ROOT"), root + "\n");
    writeFileSync(join(out, "snapshot.json"), canonicalBytesG0(hashRecord(snap, { witness_fields: schema.snapshot.witnessFields }).identity));
    putArtifact(join(out, "cas"), manifest);
    writeFileSync(join(out, "witness.json"), JSON.stringify({ started_at: started, finished_at: new Date().toISOString(), host: hostname(), node: process.version, head_drift: drift, shuffle_seed: opts.shuffleSeed ?? null, reverse_adapters: !!opts.reverseAdapters }, null, 1) + "\n");
  }
  return { root, manifest, counts: Object.fromEntries(Object.entries(kinds).map(([k, v]) => [k, v.length])), by_code: byCode, drift };
}

/** Re-resolve every stored record and the manifest through the CAS and re-derive the root. */
export function verify(dir) {
  const manifestBytes = readFileSync(join(dir, "manifest.json")); const manifest = JSON.parse(manifestBytes.toString("utf8"));
  const store = directoryStore(join(dir, "cas")); const problems = [];
  const root = artifactRoot(manifest); const rootFile = readFileSync(join(dir, "ROOT"), "utf8").trim();
  if (root !== rootFile) problems.push(`ROOT ${rootFile} != manifest root ${root}`);
  const mres = resolveArtifact(store, root); if (mres.outcome !== "ok") problems.push(`manifest does not resolve: ${mres.outcome}`);
  const index = Object.fromEntries(JSON.parse(readFileSync(join(dir, "records_index.json"), "utf8")).map((e) => [e.lid, e])); let checked = 0;
  const fileLines = {};
  for (const [lid, hash] of manifest.entries) {
    const loc = index[lid]; if (!loc) { problems.push(`no index for ${lid}`); continue; }
    if (!fileLines[loc.file]) fileLines[loc.file] = readFileSync(join(dir, loc.file)).toString("utf8").split("\n");
    const line = fileLines[loc.file][loc.line]; const got = "sha256:" + sha256Hex(Buffer.from(line, "utf8"));
    if (got !== hash) problems.push(`${lid}: stored bytes hash ${got}, manifest ${hash}`);
    const rec = JSON.parse(line); const r = resolveArtifact(store, artifactRoot(rec)); if (r.outcome !== "ok") problems.push(`${lid}: CAS ${r.outcome}`);
    checked++;
  }
  return { root, checked, entries: manifest.entries.length, problems };
}
