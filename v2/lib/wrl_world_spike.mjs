/* wrl_world_spike.mjs — HISTORICAL. The G0-C SPIKE canonicalizer of D-036/D-037 (2026-09-03), kept ONLY so the mapping
 * `historical gsem- → WRL sem-` in identities.json can be reproduced and tested (D-038, D-041). NOT on the live path:
 * lib/wrl_world.mjs seals through WRL and never calls this except to record the supersession.
 *
 * What the spike did, verbatim: objects sorted identity-first (object_id, role); each revision canonicalized by the pinned
 * kernel; relations sorted by serializeArtifact(identity_seed) bytes; duplicate seeds refused; `gsem-` = sha256 over WRL
 * `serializeArtifact` bytes; `grelpre-` = sha256 over the D8.1 preimage {tag: WRL_RELATION, variant, world_id: <gsem->,
 * relation_name} — a value the kernel refuses to mint (validateAllocation wants a `sem-`), so it was never a `rel-`.
 * Every id this module returns carries a non-WRL prefix. Do not consume them. */
import { createHash } from "node:crypto";
import { canonicalizeRelationRevision } from "../../../WRL/relation-identity.js";
import { serializeArtifact } from "../../../WRL/wrl.js";
import { G0Error } from "./canon.mjs";

const sha256 = (b) => createHash("sha256").update(b).digest("hex");
export const SPIKE_WORLD_PREFIX = "gsem-", SPIKE_PREIMAGE_PREFIX = "grelpre-";
export const SPIKE_LABEL = "historical G0-C spike (D-036/D-037; superseded by the WRL seal, D-038/D-041)";

/** The spike's own canonical form of a submission (what the D-037 `world/artifact.json` held). */
export function spikeCanonicalize(artifact) {
  const objects = artifact.objects.map((o) => ({ ...o })).sort((a, b) => (a.object_id < b.object_id ? -1 : a.object_id > b.object_id ? 1 : a.role < b.role ? -1 : a.role > b.role ? 1 : 0));
  const seeds = new Set(); const relations = [];
  for (const r of artifact.relations) { const key = serializeArtifact(r.identity_seed); if (seeds.has(key)) throw new G0Error("SPIKE_DUPLICATE_SEED", r.identity_seed.relation_name); seeds.add(key); relations.push({ identity_seed: r.identity_seed, revision: canonicalizeRelationRevision(r.revision) }); }
  relations.sort((a, b) => { const x = serializeArtifact(a.identity_seed), y = serializeArtifact(b.identity_seed); return x < y ? -1 : x > y ? 1 : 0; });
  return { ir_version: artifact.ir_version, profile_id: artifact.profile_id, semantic_policies: artifact.semantic_policies, objects, relations };
}
export const spikeBytes = (artifact) => Buffer.from(serializeArtifact(spikeCanonicalize(artifact)), "utf8");
export const spikeGsem = (artifact) => SPIKE_WORLD_PREFIX + sha256(spikeBytes(artifact));
export const spikePreimageId = (gsem, relationName) => SPIKE_PREIMAGE_PREFIX + sha256(Buffer.from(serializeArtifact({ tag: "WRL_RELATION", variant: "named-initial", world_id: gsem, relation_name: relationName }), "utf8"));

/** Reproduce the spike's identities for a submission: gsem- and, per relation, the grelpre- (historical; never a rel-). */
export function spikeIdentities(artifact) {
  const c = spikeCanonicalize(artifact); const gsem = spikeGsem(artifact);
  return { gsem, label: SPIKE_LABEL, bytes: spikeBytes(artifact), relations: c.relations.map((r) => ({ relation_name: r.identity_seed.relation_name, provisional_allocation_preimage_id: spikePreimageId(gsem, r.identity_seed.relation_name) })) };
}
