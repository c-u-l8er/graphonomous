/* wrl_world.mjs — G0-C (final, D-039/D-041/D-042/D-043/D-047): the SEMANTIC WORLD of a projection, SEALED BY WRL.
 *
 * WHO OWNS WHAT (D-041). Graphonomous owns the observed projection root, statement/assertion semantics and the SUBMISSION
 * it asks WRL to seal: `semanticArtifact(p)` builds the `graphonomous.semantic.v0` artifact (G0 lid rules, the reversible
 * lid → \w+ object-id encoding of D-040, and a G0 pre-check that names the WRL code it expects). WRL owns everything
 * after that: `canonicalizeV2Artifact` (object order, seed order, duplicate-seed refusal, endpoint constraints, the policy
 * vocabulary — all read from the admitted row `V2_PROFILES["graphonomous.semantic.v0"]`), `serializeV2Artifact` (the bytes
 * the seal hashes), `v2WorldIdOfArtifact` (the real `sem-`) and `deriveV2Relations` (every `rel-` through expandSeed →
 * validateAllocation → relationIdFromAllocation, every `rev-` through relationRevisionId). NOTHING in this module computes
 * a `sem-`, a `rel-` or a `rev-`; nothing here sorts or de-duplicates on the live path.
 *
 * THE SPIKE IS HISTORY (D-038). The D-036/D-037 `gsem-` / `grelpre-` canonicalizer lives in `wrl_world_spike.mjs`, imported
 * here only to record the supersession mapping `historical gsem- → sem-` in identities.json. It is not on the live path.
 *
 * WHAT IS NOT IN THE WORLD. Assertions, faults, derived facts, timestamps, hosts, coordinates: provenance and presentation
 * live outside identity (WRL D8.3; spec §7.4, §11; D-041 §8 — G0-C is the semantic statement world, not the evidence
 * world). Objects are the projection's nodes AND its source locations (LOCATED_IN needs a terminal); attributes are the
 * records' observed attrs. */
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, renameSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import * as V2 from "../../../WRL/relation-v2.js";
import { gitBlobOid, G0Error, canonicalBytesG0 } from "./canon.mjs";
import { loadProjection } from "./evaluation.mjs";
import { spikeIdentities } from "./wrl_world_spike.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const WRL_DIR = resolve(HERE, "../../../WRL");
/** The WRL commit that carries WRL-P0 (STACK_FIX_RECEIPTS/WRL-P0.md) and the three files this lane imports, blob-pinned.
 *  `relation-v2.js` is now a live import (the seal); the kernel and the spine are imported by it and are unchanged by P0. */
export const WRL_PIN = Object.freeze({
  commit: "b072db0a983a33108b9a0c4429b978cb07e54148",
  blobs: Object.freeze({ "relation-v2.js": "fd1babc5459206c4de1ac1c994b880d24e18ef81", "relation-identity.js": "880cfe0406ab570f4963dbb3a9b6a7cc0ab39f01", "wrl.js": "19e94ad97acec633f7a83bcff4e3a01acd867b07" }),
});
export const MINTED_BY = "wrl-kernel@" + WRL_PIN.commit.slice(0, 7);
export function assertWrlPinned() { const seen = {}; for (const [rel, want] of Object.entries(WRL_PIN.blobs)) { const got = gitBlobOid(readFileSync(resolve(WRL_DIR, rel))); seen[rel] = got; if (got !== want) throw new G0Error("WRL_MOVED", `${rel} is blob ${got}, pinned ${want} (commit ${WRL_PIN.commit})`); } return seen; }

/** Graphonomous's SUBMITTED declaration (handoff/WRL_SCHEMA_OR_PROFILE) and WRL's ADMITTED one (the frozen row). The test
 *  suite holds them facet-for-facet equal; the G0 pre-check below reads the submitted one, WRL reads its own. */
export const PROFILE = JSON.parse(readFileSync(resolve(HERE, "../handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json"), "utf8"));
export const PROFILE_ID = PROFILE.profile_id, POLICY = PROFILE.canonical_defaults.policy;
export const WRL_ROW = V2.V2_PROFILES[PROFILE_ID];
const FORBIDDEN_KEYS = new Set(["x", "y", "position", "layout", "started_at", "finished_at", "host"]);

/** Reversible lid → \w+ (D-040 / GAP-W12): `_` → `__`; any other char outside [A-Za-z0-9] → `_HH` per UTF-8 byte. */
export function encodeObjectId(lid) { let out = ""; for (const ch of String(lid)) { if (/[A-Za-z0-9]/.test(ch)) out += ch; else if (ch === "_") out += "__"; else for (const b of Buffer.from(ch, "utf8")) out += "_" + b.toString(16).toUpperCase().padStart(2, "0"); } return out; }
export function decodeObjectId(id) { const bytes = []; for (let i = 0; i < id.length; i++) { const c = id[i]; if (c !== "_") { bytes.push(c.charCodeAt(0)); continue; } if (id[i + 1] === "_") { bytes.push(95); i += 1; continue; } bytes.push(parseInt(id.slice(i + 1, i + 3), 16)); i += 2; } return Buffer.from(bytes).toString("utf8"); }

/** A G0 refusal that names the WRL code the same input would draw from the seal. The pre-check is a courtesy (a sharper
 *  message with the lid in it); WRL is the authority and refuses the same thing without it. */
function refuse(code, wrlCode, msg) { const e = new G0Error(code, msg); e.wrl_code = wrlCode; return e; }

/** Build the SUBMISSION: the `graphonomous.semantic.v0` artifact in projection order, uncanonicalized. WRL decides object
 *  order, seed order, duplicates, endpoint pairs, the policy vocabulary and the bytes. */
export function semanticArtifact(p) {
  const kinds = new Map(); const objects = [];
  for (const n of p.nodes) { kinds.set(n.lid, n.kind); objects.push({ object_id: encodeObjectId(n.lid), role: n.kind, static_config: { lid: n.lid, attrs: n.attrs, ...(n.evidence_state ? { evidence_state: n.evidence_state } : {}) }, ports: PROFILE.roles.ports }); }
  for (const l of p.locations) { kinds.set(l.lid, "SOURCE_LOCATION"); objects.push({ object_id: encodeObjectId(l.lid), role: "SOURCE_LOCATION", static_config: { lid: l.lid, registry: l.registry, pinned_identity: l.pinned_identity, path: l.path, ...(l.fragment ? { fragment: l.fragment } : {}), precision: l.precision }, ports: PROFILE.roles.ports }); }
  for (const o of objects) if (!PROFILE.roles.kinds.includes(o.role)) throw refuse("WORLD_ROLE", "WRL_UNDECLARED_ROLE", `${o.static_config.lid}: role ${o.role} is not declared by ${PROFILE_ID}`);
  const ids = new Set(objects.map((o) => o.object_id)); if (ids.size !== objects.length) throw refuse("WORLD_OBJECT_ID_COLLISION", "WRL_DUPLICATE_ID", "two lids encode to one object_id");
  const relations = [];
  for (const r of p.relations) {
    // D-037 PAIRS form: the profile lists explicit [source kind, target kind] pairs per relation kind (`*` = any kind)
    const pairs = PROFILE.endpoint_constraints[r.kind] || [["*", "*"]];
    for (const end of [r.source, r.target]) if (!kinds.has(end)) throw refuse("WORLD_DANGLING_TERMINAL", "WRL_UNKNOWN_ENDPOINT", `${r.lid}: ${end} is not an object of this world`);
    const sk = kinds.get(r.source), tk = kinds.get(r.target);
    if (!pairs.some(([a, b]) => (a === "*" || a === sk) && (b === "*" || b === tk))) throw refuse("WORLD_ENDPOINT_KIND", "WRL_UNDECLARED_ENDPOINT_PAIR", `${r.lid}: ${sk} → ${tk} is not an allowed pair for ${r.kind} (profile allows ${pairs.map(([a, b]) => `${a}→${b}`).join(", ")})`);
    relations.push({ identity_seed: { variant: "named-initial", relation_name: r.lid }, revision: { domain: PROFILE.relation_signatures.domain, kind: r.kind, orientation: PROFILE.relation_signatures.orientation, texture: PROFILE.canonical_defaults.texture, endpoints: [{ role: "source", terminal: { object_id: encodeObjectId(r.source), port: "node" } }, { role: "target", terminal: { object_id: encodeObjectId(r.target), port: "node" } }], attributes: r.attrs, policy: POLICY } });
  }
  const artifact = { ir_version: PROFILE.ir_version, profile_id: PROFILE_ID, semantic_policies: PROFILE.semantic_policies, objects, relations };
  scanKeys(artifact, "");
  return artifact;
}
function scanKeys(v, path) { if (Array.isArray(v)) v.forEach((x, i) => scanKeys(x, `${path}/${i}`)); else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { if (FORBIDDEN_KEYS.has(k)) throw new G0Error("WORLD_FORBIDDEN_KEY", `${path}/${k}: presentation or run data must not enter identity`); if (x === undefined) throw new G0Error("WORLD_UNDEFINED", `${path}/${k}`); if (typeof x === "number" && !Number.isSafeInteger(x)) throw new G0Error("WORLD_NUMBER", `${path}/${k}`); scanKeys(x, `${path}/${k}`); } }

/** SEAL through WRL. Every identity in the result is WRL's: the bytes are `serializeV2Artifact`, the world id is
 *  `v2WorldIdOfArtifact`, each `rel-`/`rev-` is `deriveV2Relations` (kernel path). A WRL refusal propagates as the typed
 *  WrlError (`e.code`, `e.fieldPath`) — G0 does not translate it. */
export async function seal(artifact) {
  const canonical = V2.canonicalizeV2Artifact(artifact);
  const bytes = Buffer.from(V2.serializeV2Artifact(artifact), "utf8");
  const sem = await V2.v2WorldIdOfArtifact(artifact);
  const view = await V2.deriveV2Relations(artifact, sem);
  if (!view.derived || !view.seedsInArtifactBytes || view.idsInArtifactBytes || view.world_id !== sem) throw new G0Error("WORLD_SEAL_SHAPE", "deriveV2Relations did not answer in the shape this lane relies on");
  return { sem, profile_id: PROFILE_ID, bytes, canonical, objects: canonical.objects.length, relations: view.relations.map((r) => ({ relation_name: r.identity_seed.relation_name, rel: r.relation_id, rev: r.revision_id, minted_by: MINTED_BY })) };
}
/** Convenience: submission + seal of a loaded projection. */
export async function sealProjection(p) { return seal(semanticArtifact(p)); }

const WORLD_STATE = "SEALED by WRL (WRL-P0); FROZEN only when GPT accepts this round";
/** The identities document (canonical G0 bytes). `supersedes` is the only place a historical `gsem-` may appear. */
export function identitiesDocument(sealed, p, historicalSpikeGsem) {
  return {
    sem: sealed.sem, profile_id: sealed.profile_id,
    wrl: { commit: WRL_PIN.commit, blobs: Object.entries(WRL_PIN.blobs).map(([file, blob]) => ({ file, blob })) },
    projection_root: p.root, snapshot: p.snapshot, objects: sealed.objects, relations: sealed.relations,
    supersedes: { historical_spike_gsem: historicalSpikeGsem, note: "D-038/D-041: provisional Graphonomous spike identity (world-spike/); superseded for WRL-world purposes by sem. Equivalence of the two hexes is MEASURED per pin by test/wrl_world.test.mjs, never assumed: the spike is not a seal, whatever its bytes" },
    state: WORLD_STATE,
  };
}

/** Build and write `<projection>/world/`: artifact.json (WRL canonical bytes, exactly serializeV2Artifact), identities.json,
 *  SEM. A D-036/D-037 spike `world/` (it has a GSEM and no SEM) is MOVED to `world-spike/` first, bytes untouched, and its
 *  GSEM is recorded under `supersedes`. */
export async function buildWorld(dir, { out = join(dir, "world"), spikeOut = join(dir, "world-spike") } = {}) {
  assertWrlPinned();
  const p = loadProjection(dir); const artifact = semanticArtifact(p); const sealed = await seal(artifact);
  if (existsSync(join(out, "GSEM")) && !existsSync(join(out, "SEM"))) { if (existsSync(spikeOut)) throw new G0Error("WORLD_SPIKE_EXISTS", `${spikeOut} already exists; refusing to overwrite a historical receipt`); renameSync(out, spikeOut); }
  const historical = existsSync(join(spikeOut, "GSEM")) ? readFileSync(join(spikeOut, "GSEM"), "utf8").trim() : null;
  const doc = identitiesDocument(sealed, p, historical);
  rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "artifact.json"), sealed.bytes);
  writeFileSync(join(out, "identities.json"), canonicalBytesG0(doc));
  writeFileSync(join(out, "SEM"), sealed.sem + "\n");
  return { ...doc, bytes: sealed.bytes.length, spike_reproduced: historical ? spikeIdentities(artifact).gsem : null };
}
