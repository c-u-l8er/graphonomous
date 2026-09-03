/* WRL-P0 reproducer / Graphonomous G0-C conformance vector.
 *
 *   node graphonomous_seal_reproducer.mjs
 *
 * Seals the minimized `graphonomous.semantic.v0` world through WRL's generic
 * static-profile path and prints the `sem-` the kernel mints, the canonical
 * bytes it hashes, and the kernel `rel-`/`rev-` per relation. Nothing here is
 * computed outside WRL: the world id is `v2WorldIdOfArtifact`, every `rel-` is
 * `relationIdFromAllocation` over `expandSeed(sem, seed)`, every `rev-` is
 * `relationRevisionId`. Imports by absolute path; pin the WRL commit you ran
 * it against beside the output. */
import * as V2 from "/home/travis/ProjectAmp2/WRL/relation-v2.js";
import * as R from "/home/travis/ProjectAmp2/WRL/relation-identity.js";
import * as W from "/home/travis/ProjectAmp2/WRL/wrl.js";

const RULES = "graphonomous.semantic.rules.v0";
const RECEIPT = "receipt_3Asha256_3Aabc";          /* lid receipt:sha256:abc, \w+-encoded */
const CLAIM = "claim_3Acrosswalk_3AE_2D48";        /* lid claim:crosswalk:E-48 */
const NAME = "rel:WITNESSES:receipt:sha256:abc:claim:crosswalk:E-48";

export const WORLD = {
  ir_version: "2.0",
  profile_id: "graphonomous.semantic.v0",
  semantic_policies: { rulepack_id: RULES },
  objects: [
    { object_id: RECEIPT, role: "RECEIPT", static_config: { lid: "receipt:sha256:abc", attrs: {} }, ports: ["node"] },
    { object_id: CLAIM, role: "CLAIM", static_config: { lid: "claim:crosswalk:E-48", attrs: {} }, ports: ["node"] },
  ],
  relations: [{
    identity_seed: { variant: "named-initial", relation_name: NAME },
    revision: {
      domain: "semantic", kind: "WITNESSES", orientation: "directed", texture: "solid",
      endpoints: [{ role: "source", terminal: { object_id: RECEIPT, port: "node" } },
                  { role: "target", terminal: { object_id: CLAIM, port: "node" } }],
      attributes: {}, policy: RULES,
    },
  }],
};

const bytes = V2.serializeV2Artifact(WORLD);
const sem = await V2.v2WorldIdOfArtifact(WORLD);
const view = await V2.deriveV2Relations(WORLD, sem);

/* the same ids, re-derived through the kernel's own entry points, so the
 * vector is checkable without trusting deriveV2Relations */
const check = [];
for (const r of view.relations) {
  const rel = await R.relationIdFromAllocation(R.namedInitialAllocation(sem, r.identity_seed.relation_name));
  const rev = await R.relationRevisionId(r.revision);
  check.push({ relation_name: r.identity_seed.relation_name, relation_id: r.relation_id, revision_id: r.revision_id,
               kernel_agrees: rel === r.relation_id && rev === r.revision_id });
}

console.log(JSON.stringify({
  profile_id: WORLD.profile_id,
  canonical_bytes: bytes,
  canonical_bytes_length: bytes.length,
  sem: sem,
  world_id_is_sem: /^sem-[0-9a-f]{64}$/.test(sem),
  relations: check,
  seedsInArtifactBytes: view.seedsInArtifactBytes,
  idsInArtifactBytes: view.idsInArtifactBytes,
  rev_bytes: view.relations.map((r) => W.serializeArtifact(r.revision)),
}, null, 1));
