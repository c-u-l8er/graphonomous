/* wrl_world.mjs — G0-C (spike, D-036): the V2-shaped SEMANTIC WORLD of a projection, its `gsem-` id, and per-relation
 * `rev-` (WRL kernel) / `grelpre-` (the G0-computed D8.1 preimage under the gsem-; GAP-W11 relabel per D-037 — a value
 * the kernel cannot mint is not presented as a `rel-`). Profile: handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json.
 *
 * WHAT IS THE KERNEL'S AND WHAT IS OURS (R10). `canonicalizeRelationRevision` / `relationRevisionId` come from the pinned
 * WRL relation kernel — the `rev-` ids here ARE kernel-minted. The world canonicalization (`canonicalizeV2Artifact`) and
 * the allocation validator refuse our profile and our `gsem-` (GAP-W13, GAP-W11), so G0 owns: the envelope, object
 * ordering, seed ordering, duplicate-seed refusal, the `gsem-` hash (WRL `serializeArtifact` bytes + SHA-256), and the
 * `grelpre-` preimage (`{tag: WRL_RELATION, variant, world_id, relation_name}` — its hex verified equal to what the kernel
 * mints for a `sem-` world). Every `grelpre-` is labelled `g0-d8.1-preimage`, never "kernel-minted", never a WRL `rel-`.
 * Nothing here is a `sem-`.
 *
 * WHAT IS NOT IN THE WORLD. Assertions, faults, derived facts, timestamps, hosts, coordinates: provenance and presentation
 * live outside identity (WRL D8.3; spec §7.4, §11). Objects are the projection's nodes AND its source locations
 * (LOCATED_IN needs a terminal); attributes are the records' observed attrs. */
import { readFileSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { canonicalizeRelationRevision, relationRevisionId, namedInitialAllocation, relationIdFromAllocation } from "../../../WRL/relation-identity.js";
import { serializeArtifact } from "../../../WRL/wrl.js";
import { gitBlobOid, G0Error, canonicalBytesG0 } from "./canon.mjs";
import { loadProjection } from "./evaluation.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const WRL_DIR = resolve(HERE, "../../../WRL");
/** The two WRL files this module imports, blob-pinned (R10 also read `relation-v2.js` = blob `b5e9ff81…` at this commit,
 *  but nothing here imports it, so it is documentation, not a dependency — and not a REPRO_DEPENDENCIES entry). */
export const WRL_PIN = Object.freeze({ commit: "1f4c5fd4cf50ce65e3939fe1981efb9bb3363aba", blobs: Object.freeze({ "relation-identity.js": "880cfe0406ab570f4963dbb3a9b6a7cc0ab39f01", "wrl.js": "19e94ad97acec633f7a83bcff4e3a01acd867b07" }) });
export function assertWrlPinned() { const seen = {}; for (const [rel, want] of Object.entries(WRL_PIN.blobs)) { const got = gitBlobOid(readFileSync(resolve(WRL_DIR, rel))); seen[rel] = got; if (got !== want) throw new G0Error("WRL_MOVED", `${rel} is blob ${got}, pinned ${want} (commit ${WRL_PIN.commit})`); } return seen; }
export const PROFILE = JSON.parse(readFileSync(resolve(HERE, "../handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json"), "utf8"));
export const PROFILE_ID = PROFILE.profile_id, POLICY = PROFILE.canonical_defaults.policy;
const sha256 = (b) => createHash("sha256").update(b).digest("hex");
const FORBIDDEN_KEYS = new Set(["x", "y", "position", "layout", "started_at", "finished_at", "host"]);

/** Reversible lid → \w+ (GAP-W12): `_` → `__`; any other char outside [A-Za-z0-9] → `_HH` per UTF-8 byte. */
export function encodeObjectId(lid) { let out = ""; for (const ch of String(lid)) { if (/[A-Za-z0-9]/.test(ch)) out += ch; else if (ch === "_") out += "__"; else for (const b of Buffer.from(ch, "utf8")) out += "_" + b.toString(16).toUpperCase().padStart(2, "0"); } return out; }
export function decodeObjectId(id) { const bytes = []; for (let i = 0; i < id.length; i++) { const c = id[i]; if (c !== "_") { bytes.push(c.charCodeAt(0)); continue; } if (id[i + 1] === "_") { bytes.push(95); i += 1; continue; } bytes.push(parseInt(id.slice(i + 1, i + 3), 16)); i += 2; } return Buffer.from(bytes).toString("utf8"); }

/** Build the canonical V2-shaped artifact (sync; no ids yet). Refuses what the profile's validators refuse. */
export function semanticArtifact(p) {
  const kinds = new Map(); const objects = [];
  for (const n of p.nodes) { kinds.set(n.lid, n.kind); objects.push({ object_id: encodeObjectId(n.lid), role: n.kind, static_config: { lid: n.lid, attrs: n.attrs, ...(n.evidence_state ? { evidence_state: n.evidence_state } : {}) }, ports: PROFILE.roles.ports }); }
  for (const l of p.locations) { kinds.set(l.lid, "SOURCE_LOCATION"); objects.push({ object_id: encodeObjectId(l.lid), role: "SOURCE_LOCATION", static_config: { lid: l.lid, registry: l.registry, pinned_identity: l.pinned_identity, path: l.path, ...(l.fragment ? { fragment: l.fragment } : {}), precision: l.precision }, ports: PROFILE.roles.ports }); }
  for (const o of objects) if (!PROFILE.roles.kinds.includes(o.role)) throw new G0Error("WORLD_ROLE", `${o.static_config.lid}: role ${o.role} is not declared by ${PROFILE_ID}`);
  const ids = new Set(objects.map((o) => o.object_id)); if (ids.size !== objects.length) throw new G0Error("WORLD_OBJECT_ID_COLLISION", "two lids encode to one object_id");
  objects.sort((a, b) => (a.object_id < b.object_id ? -1 : a.object_id > b.object_id ? 1 : a.role < b.role ? -1 : a.role > b.role ? 1 : 0));
  const relations = []; const seeds = new Set();
  for (const r of p.relations) {
    // D-037 PAIRS form: the profile lists explicit [source kind, target kind] pairs per relation kind (`*` = any kind)
    const pairs = PROFILE.endpoint_constraints[r.kind] || [["*", "*"]];
    for (const end of [r.source, r.target]) if (!kinds.has(end)) throw new G0Error("WORLD_DANGLING_TERMINAL", `${r.lid}: ${end} is not an object of this world`);
    const sk = kinds.get(r.source), tk = kinds.get(r.target);
    if (!pairs.some(([a, b]) => (a === "*" || a === sk) && (b === "*" || b === tk))) throw new G0Error("WORLD_ENDPOINT_KIND", `${r.lid}: ${sk} → ${tk} is not an allowed pair for ${r.kind} (profile allows ${pairs.map(([a, b]) => `${a}→${b}`).join(", ")})`);
    const revision = canonicalizeRelationRevision({ domain: PROFILE.relation_signatures.domain, kind: r.kind, orientation: "directed", texture: "solid", endpoints: [{ role: "source", terminal: { object_id: encodeObjectId(r.source), port: "node" } }, { role: "target", terminal: { object_id: encodeObjectId(r.target), port: "node" } }], attributes: r.attrs, policy: POLICY });
    const identity_seed = { variant: "named-initial", relation_name: r.lid };
    const seedKey = serializeArtifact(identity_seed); if (seeds.has(seedKey)) throw new G0Error("WORLD_DUPLICATE_SEED", r.lid); seeds.add(seedKey);
    relations.push({ identity_seed, revision });
  }
  relations.sort((a, b) => { const x = serializeArtifact(a.identity_seed), y = serializeArtifact(b.identity_seed); return x < y ? -1 : x > y ? 1 : 0; });
  const artifact = { ir_version: PROFILE.ir_version, profile_id: PROFILE_ID, semantic_policies: PROFILE.semantic_policies, objects, relations };
  scanKeys(artifact, "");
  return artifact;
}
function scanKeys(v, path) { if (Array.isArray(v)) v.forEach((x, i) => scanKeys(x, `${path}/${i}`)); else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { if (FORBIDDEN_KEYS.has(k)) throw new G0Error("WORLD_FORBIDDEN_KEY", `${path}/${k}: presentation or run data must not enter identity`); if (x === undefined) throw new G0Error("WORLD_UNDEFINED", `${path}/${k}`); if (typeof x === "number" && !Number.isSafeInteger(x)) throw new G0Error("WORLD_NUMBER", `${path}/${k}`); scanKeys(x, `${path}/${k}`); } }

export const worldBytes = (artifact) => Buffer.from(serializeArtifact(artifact), "utf8");
export const gsemOf = (artifact) => "gsem-" + sha256(worldBytes(artifact));
/** D8.1 preimage with a G0-owned scope (GAP-W11): the hex the kernel would mint if it accepted a gsem- world_id, under
 *  the G0 prefix `grelpre-` (D-037 relabel: never presented as a kernel `rel-`). `preimageHex` is the bare digest so a
 *  test can compare it with the kernel's `rel-` for a `sem-` scope. */
export const PREIMAGE_PREFIX = "grelpre-";
export const preimageHex = (worldId, relationName) => sha256(Buffer.from(serializeArtifact({ tag: "WRL_RELATION", variant: "named-initial", world_id: worldId, relation_name: relationName }), "utf8"));
export const relIdUnder = (worldId, relationName) => PREIMAGE_PREFIX + preimageHex(worldId, relationName);

/** All identities of a world: gsem-, and per relation the kernel rev- and the G0 grelpre- (provisional allocation preimage id). */
export async function identities(artifact) {
  const gsem = gsemOf(artifact); const relations = [];
  for (const r of artifact.relations) relations.push({ relation_name: r.identity_seed.relation_name, rev: await relationRevisionId(r.revision), provisional_allocation_preimage_id: relIdUnder(gsem, r.identity_seed.relation_name), rev_minted_by: "wrl-kernel@" + WRL_PIN.commit.slice(0, 7), provisional_minted_by: "g0-d8.1-preimage (GAP-W11; not a WRL rel-)" });
  return { gsem, profile_id: PROFILE_ID, wrl_pin: WRL_PIN.commit, objects: artifact.objects.length, relations };
}

/** Build and write `<projection>/world/`. Provisional identities (D-036): nothing downstream may consume them yet. */
export async function buildWorld(dir, { out = join(dir, "world") } = {}) {
  assertWrlPinned();
  const p = loadProjection(dir); const artifact = semanticArtifact(p); const ids = await identities(artifact);
  rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "artifact.json"), worldBytes(artifact));
  writeFileSync(join(out, "identities.json"), canonicalBytesG0({ ...ids, projection_root: p.root, snapshot: p.snapshot, state: "PROVISIONAL — historical spike identity (D-036/D-038); superseded for WRL-world purposes by the real sem- once WRL-P0 seals the profile", never: "sem-" }));
  writeFileSync(join(out, "GSEM"), ids.gsem + "\n");
  return { ...ids, projection_root: p.root, snapshot: p.snapshot, bytes: worldBytes(artifact).length };
}
/** Exposed for the tests: the kernel's own allocation path (which refuses gsem-), to keep GAP-W11 measured, not assumed. */
export async function kernelRelId(worldId, relationName) { return relationIdFromAllocation(namedInitialAllocation(worldId, relationName)); }
