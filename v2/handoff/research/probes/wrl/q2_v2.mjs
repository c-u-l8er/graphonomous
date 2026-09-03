import * as W from "/home/travis/ProjectAmp2/WRL/wrl.js";
import * as R from "/home/travis/ProjectAmp2/WRL/relation-identity.js";
import * as V2 from "/home/travis/ProjectAmp2/WRL/relation-v2.js";

const src = `profile forge.world.core.v1
ir 2.0

[pulser:p0](every 2){sig_out}
[relay:r0]{sig_in, sig_out}
[spinner:sp](w=16, n=8, rotor=quarter_turn_z, configurable){sig_in, socket}
[orb:ob]{pose}

[clock_feed]: [p0] --sig--> [r0]
[drive]: [r0] --sig--> [sp]
[pose_out]: [sp] --socket--> [ob]
`;
const a = await V2.admitWorldSource(src);
console.log("== (a) V2 named starter world ==");
console.log("family:", a.family, "declared:", a.declared, "ok:", a.ok, a.ok ? "" : a.code + " " + a.message);
console.log("V2 sem-:", a.semanticWorldId);
console.log("V2 bytes (" + a.bytes.length + " chars):");
console.log(a.bytes);
console.log("denamed V1 sem- (execution view):", (await W.sealWorld(a.denamed)).semanticId, "== STARTER?", (await W.sealWorld(a.denamed)).semanticId === W.STARTER_WORLD_SEMANTIC_ID);
console.log("\none relation record (pretty):");
console.log(JSON.stringify(a.artifact.relations[0], null, 2));
const view = await V2.deriveV2Relations(a.artifact);
console.log("\nderived ids (seedsInArtifactBytes=" + view.seedsInArtifactBytes + ", idsInArtifactBytes=" + view.idsInArtifactBytes + "):");
for (const r of view.relations) console.log(" ", JSON.stringify({ seed: r.identity_seed, allocation: r.allocation, rel: r.relation_id, rev: r.revision_id }));
console.log("rel- preimage example:", W.serializeArtifact({ tag: "WRL_RELATION", ...view.relations[0].allocation }));
console.log("rev- preimage example:", W.serializeArtifact(R.canonicalizeRelationRevision(view.relations[0].revision)));

console.log("\n== (b) migrateV1ToV2(starter) ==");
const v1 = await W.sealWorld(W.STARTER_WORLD);
const m = V2.migrateV1ToV2(v1.artifact);
console.log("migrated bytes:", V2.serializeV2Artifact(m));
console.log("migrated sem-:", await V2.v2WorldIdOfArtifact(m));
console.log("downgrade(m,'1.0') byte-exact vs V1:", W.serializeArtifact(V2.downgradeV2ToV1(m, "1.0")) === v1.bytes);

console.log("\n== (c) runtime projection wire for the named world ==");
const p = await V2.deriveRuntimeProjection(a.artifact);
console.log("coincident:", p.coincident, "semantic_world_id:", p.semantic_world_id, "execution_view_id:", p.execution_view_id);
console.log(V2.serializeRuntimeProjection(p));

console.log("\n== (d) mutation probes on the sealed V2 artifact (through assertV2Artifact / canonicalizeV2Artifact) ==");
const tryIt = (label, fn) => { try { const out = fn(); console.log(`${label.padEnd(44)} => ACCEPTED ${typeof out === "string" ? out.slice(0, 80) : ""}`); }
  catch (e) { console.log(`${label.padEnd(44)} => ${e.code} | fieldPath=${e.fieldPath} | ${(e.detail || e.message).split("\n")[0].slice(0, 160)}`); } };
const clone = () => structuredClone(a.artifact);
let c;
c = clone(); c.relations[0].revision.kind = "supports";                 tryIt("revision.kind = 'supports'", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.kind = "SUPPORTS";                 tryIt("revision.kind = 'SUPPORTS'", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.domain = "evidence";               tryIt("revision.domain = 'evidence'", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.attributes = { evidence_state: "open" }; tryIt("revision.attributes = {evidence_state}", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.texture = "async";                 tryIt("revision.texture = 'async'", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.orientation = "symmetric"; c.relations[0].revision.endpoints.forEach(e => e.role = "peer"); delete c.relations[0].revision.texture; tryIt("orientation symmetric / peers", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.policy = "graphonomous.g0.rules.v0"; tryIt("revision.policy = other rulepack", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.provenance = { by: "x" };          tryIt("revision.provenance = {...}", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.predecessor = "rev-0";             tryIt("revision.predecessor = 'rev-0'", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].relation_id = "rel-00";                      tryIt("record.relation_id stored", () => V2.serializeV2Artifact(c));
c = clone(); c.objects[0].role = "Claim";                                tryIt("object.role = 'Claim'", () => V2.serializeV2Artifact(c));
c = clone(); c.objects.push({ object_id: "claim_1", role: "Relay", static_config: {}, state_schema_ref: "state.relay.v1", ports: { in: ["sig_in"], out: ["sig_out"] } }); tryIt("extra unwired Relay object (ports-free use?)", () => V2.serializeV2Artifact(c));
c = clone(); c.profile_id = "graphonomous.g0.v1";                        tryIt("profile_id = graphonomous.g0.v1", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].revision.endpoints.push({ terminal: { object_id: "ob", port: "pose" }, role: "target" }); tryIt("3-endpoint directed relation", () => V2.serializeV2Artifact(c));
c = clone(); c.relations[0].identity_seed = { variant: "granted", grant_id: "g", local_counter: 0 }; tryIt("granted seed in initial bytes", () => V2.serializeV2Artifact(c));
c = clone(); c.relations.push(structuredClone(c.relations[0]));           tryIt("duplicate seed", () => V2.serializeV2Artifact(c));

console.log("\n== (e) the family-neutral revision kernel, called directly (relation-identity.js) ==");
const g0rev = {
  domain: "evidence", kind: "SUPPORTS",
  endpoints: [
    { terminal: { object_id: "receipt_42", port: "asserts" }, role: "source" },
    { terminal: { object_id: "claim_7", port: "subject" }, role: "target" }],
  orientation: "directed", texture: "solid",
  attributes: { evidence_state: "open", scope: "computedriven/edge", source_loc: "STACK_GAP_REGISTER.md:12" },
  policy: "graphonomous.g0.rules.v0",
};
tryIt("validateRelationRevision(G0 SUPPORTS)", () => JSON.stringify(R.validateRelationRevision(g0rev)).slice(0, 60));
console.log("rev- for a G0 SUPPORTS revision:", await R.relationRevisionId(g0rev));
console.log("canonical rev bytes:", W.serializeArtifact(R.canonicalizeRelationRevision(g0rev)));
const g0rev3 = structuredClone(g0rev); g0rev3.endpoints.push({ terminal: { object_id: "experiment_3", port: "asserts" }, role: "source" });
console.log("rev- for a 2-source hyperarc:", await R.relationRevisionId(g0rev3));
const fakeWorld = "sem-" + "0".repeat(64);
tryIt("namedInitialAllocation(fakeWorld,'supports_1')", () => JSON.stringify(R.namedInitialAllocation(fakeWorld, "supports_1")));
console.log("rel- from that allocation:", await R.relationIdFromAllocation(R.namedInitialAllocation(fakeWorld, "supports_1")));
tryIt("kernel: revision with 'provenance' field", () => R.validateRelationRevision({ ...g0rev, provenance: {} }));
tryIt("kernel: revision with 'predecessor'", () => R.validateRelationRevision({ ...g0rev, predecessor: "rev-0" }));
tryIt("kernel: texture on acausal", () => R.validateRelationRevision({ ...g0rev, orientation: "acausal", endpoints: g0rev.endpoints.map(e => ({ ...e, role: "terminal" })) }));
tryIt("kernel: directed w/o texture", () => { const r = { ...g0rev }; delete r.texture; return R.validateRelationRevision(r); });
tryIt("kernel: projectRelationRevisionToV1Edge(G0)", () => JSON.stringify(R.projectRelationRevisionToV1Edge(g0rev)));
tryIt("kernel: attributes with float 0.5", () => W.serializeArtifact(R.canonicalizeRelationRevision({ ...g0rev, attributes: { w: 0.5 } })));
tryIt("kernel: attributes nested list/obj", () => W.serializeArtifact(R.canonicalizeRelationRevision({ ...g0rev, attributes: { tags: ["a", "b"], loc: { file: "x", line: 3 } } })));
console.log("\nexports relation-identity.js:", Object.keys(R).join(", "));
console.log("\nexports relation-v2.js:", Object.keys(V2).join(", "));
