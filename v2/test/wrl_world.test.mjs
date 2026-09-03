/* wrl_world.test.mjs — G0-C spike laws over the SHIPPED baseline projection, against the pinned WRL kernel. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { assertWrlPinned, encodeObjectId, decodeObjectId, semanticArtifact, identities, gsemOf, worldBytes, relIdUnder, kernelRelId, PROFILE } from "../lib/wrl_world.mjs";
import { canonicalizeRelationRevision } from "../../../WRL/relation-identity.js";
import { serializeArtifact } from "../../../WRL/wrl.js";
import { loadProjection } from "../lib/evaluation.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const P = loadProjection(resolve(V, "projections/baseline"));
const clone = (p) => JSON.parse(JSON.stringify({ root: p.root, snapshot: p.snapshot, nodes: p.nodes, relations: p.relations, assertions: p.assertions, locations: p.locations }));
const shuffled = (arr, seed) => { const a = arr.slice(); let s = (seed >>> 0) || 1; for (let i = a.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) >>> 0; const j = s % (i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const A0 = semanticArtifact(P); const I0 = await identities(A0);
const revMap = (I) => new Map(I.relations.map((r) => [r.relation_name, r.rev])), relMap = (I) => new Map(I.relations.map((r) => [r.relation_name, r.provisional_allocation_preimage_id]));

test("the WRL kernel is the pinned one; every object_id is \\w+ and decodes back to its lid; the encoding is injective", () => {
  assertWrlPinned();
  const lids = [...P.nodes.map((n) => n.lid), ...P.locations.map((l) => l.lid)];
  const ids = lids.map(encodeObjectId);
  assert.ok(ids.every((id) => /^\w+$/.test(id))); assert.equal(new Set(ids).size, lids.length);
  lids.forEach((lid, i) => assert.equal(decodeObjectId(ids[i]), lid));
  assert.equal(encodeObjectId("claim:crosswalk:E-48"), PROFILE.object_id_encoding.example.object_id);
  assert.equal(decodeObjectId(encodeObjectId("a_b:c/d%3F?é")), "a_b:c/d%3F?é");
});

test("same projection ⇒ same gsem- and identical bytes; record order is irrelevant", () => {
  assert.match(I0.gsem, /^gsem-[0-9a-f]{64}$/);
  const again = semanticArtifact(P); assert.ok(worldBytes(again).equals(worldBytes(A0)));
  const c = clone(P); c.nodes = shuffled(c.nodes, 7); c.relations = shuffled(c.relations, 8); c.locations = shuffled(c.locations, 9);
  assert.equal(gsemOf(semanticArtifact(c)), I0.gsem);
  assert.equal(A0.objects.length, P.nodes.length + P.locations.length); assert.equal(A0.relations.length, P.relations.length);
});

test("one semantic relation edit ⇒ exactly that rev- moves, every other rev- holds, the gsem- moves, and (WRL D8.5 world scoping) every grelpre- moves while relation names hold", async () => {
  const c = clone(P); const target = c.relations.find((r) => r.kind === "STATES"); target.attrs = { ...target.attrs, relation_field: target.attrs.relation_field + "*" };
  const I1 = await identities(semanticArtifact(c));
  assert.notEqual(I1.gsem, I0.gsem);
  const r0 = revMap(I0), r1 = revMap(I1); let moved = [];
  for (const [name, rev] of r0) if (r1.get(name) !== rev) moved.push(name);
  assert.deepEqual(moved, [target.lid], "exactly one rev- moved");
  const l0 = relMap(I0), l1 = relMap(I1); assert.ok([...l0].every(([name, rel]) => l1.get(name) !== rel), "D8.5: the provisional allocation preimage id is world-scoped, so a new gsem- renames every grelpre-");
  assert.deepEqual([...l1.keys()].sort(), [...l0.keys()].sort(), "the statement lids (relation_name) are the stable cross-world names");
});

test("an assertion-only (provenance) edit moves nothing: same gsem-, same rev-, same grelpre- (WRL D8.3: provenance is outside the revision)", async () => {
  const c = clone(P); const a = c.assertions.find((x) => x.attrs && x.attrs.role); a.attrs.role = a.attrs.role + "-edited"; a.attrs.extra_note = "provenance only";
  c.assertions.push({ ...c.assertions[0], lid: c.assertions[0].lid + ":dup" });
  const I2 = await identities(semanticArtifact(c));
  assert.equal(I2.gsem, I0.gsem); assert.deepEqual(revMap(I2), revMap(I0)); assert.deepEqual(relMap(I2), relMap(I0));
});

test("a node-attribute edit moves the gsem- but no rev- (rev- is the relation revision alone)", async () => {
  const c = clone(P); const n = c.nodes.find((x) => x.kind === "CLAIM"); n.attrs = { ...n.attrs, name: n.attrs.name + " (edited)" };
  const I3 = await identities(semanticArtifact(c));
  assert.notEqual(I3.gsem, I0.gsem); assert.deepEqual(revMap(I3), revMap(I0));
});

test("no coordinates, timestamps, hosts, sem- or provenance in the artifact; every id carries its own prefix", () => {
  const keys = new Set(); const walk = (v) => { if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { keys.add(k); walk(x); } }; walk(A0);
  for (const k of ["x", "y", "position", "layout", "started_at", "finished_at", "host", "assertions", "asserted_by", "snapshot", "basis"]) assert.ok(!keys.has(k), `key ${k} must not enter identity`);
  const text = worldBytes(A0).toString("utf8"); assert.ok(!/"sem-[0-9a-f]{8}/.test(text), "no sem- anywhere");
  assert.ok(I0.relations.every((r) => /^rev-[0-9a-f]{64}$/.test(r.rev) && /^grelpre-[0-9a-f]{64}$/.test(r.provisional_allocation_preimage_id)));
  assert.ok(I0.relations.every((r) => r.provisional_minted_by === "g0-d8.1-preimage (GAP-W11; not a WRL rel-)" && r.rev_minted_by.startsWith("wrl-kernel@1f4c5fd")));
  assert.ok(I0.relations.every((r) => !("rel" in r) && !("rel_minted_by" in r)), "D-037 / GAP-W11 relabel: nothing G0 computes is presented as a rel-");
  assert.ok(!JSON.stringify(I0).includes('"rel-'), "no rel- anywhere in the identities");
  assert.equal(A0.profile_id, "graphonomous.semantic.v0");
});

test("the kernel's byte rules are what we rely on: rev- = sha256(serializeArtifact(canonical revision)); the kernel refuses a gsem- world_id (GAP-W11) but mints, for a sem- scope, a rel- whose hex equals our grelpre- through the same preimage", async () => {
  const r = A0.relations[0]; const manual = "rev-" + createHash("sha256").update(Buffer.from(serializeArtifact(canonicalizeRelationRevision(r.revision)), "utf8")).digest("hex");
  assert.equal(I0.relations.find((x) => x.relation_name === r.identity_seed.relation_name).rev, manual);
  await assert.rejects(async () => kernelRelId(I0.gsem, r.identity_seed.relation_name), (e) => e.code === "WRL_BAD_ALLOCATION");
  const fakeSem = "sem-" + "a".repeat(64);
  const ours = relIdUnder(fakeSem, r.identity_seed.relation_name); assert.match(ours, /^grelpre-[0-9a-f]{64}$/);
  assert.equal(await kernelRelId(fakeSem, r.identity_seed.relation_name), "rel-" + ours.slice("grelpre-".length), "our preimage IS the kernel's function: the hex is unchanged, only the label differs (grelpre- says who computed it)");
});

test("the profile's endpoint constraints hold for every relation of the real projection, and a violating relation is refused", () => {
  const c = clone(P); c.relations.push({ lid: "rel:g0:BINDS:obligation:inv:S1:obligation:inv:S5", kind: "BINDS", source: "obligation:inv:S1", target: "obligation:inv:S5", basis: "observed", snapshot: c.snapshot, attrs: {}, assertions: [] });
  assert.throws(() => semanticArtifact(c), /WORLD_ENDPOINT_KIND/);
  const d = clone(P); d.relations.push({ ...d.relations[0], lid: d.relations[0].lid + ":x", source: "claim:crosswalk:E-99" });
  assert.throws(() => semanticArtifact(d), /WORLD_DANGLING_TERMINAL/);
});

test("D-037 in the world profile (PAIRS form): transition → claim SUPERSEDES is refused, claim → claim SUPERSEDES is accepted, transition → claim STATE_TRANSITION_OF is what the real data carries", () => {
  assert.deepEqual(PROFILE.endpoint_constraints.SUPERSEDES, [["CLAIM", "CLAIM"], ["ROUND", "ROUND"], ["EVIDENCE_STATE_TRANSITION", "EVIDENCE_STATE_TRANSITION"]]);
  assert.deepEqual(PROFILE.endpoint_constraints.STATE_TRANSITION_OF, [["EVIDENCE_STATE_TRANSITION", "CLAIM"]]);
  for (const [k, v] of Object.entries(PROFILE.endpoint_constraints)) if (k !== "note") assert.ok(Array.isArray(v) && v.every((p) => Array.isArray(p) && p.length === 2 && p.every((x) => typeof x === "string")), `${k} is a list of [source kind, target kind] pairs`);
  assert.ok(PROFILE.relation_signatures.kinds.includes("STATE_TRANSITION_OF"));
  const t = P.relations.find((r) => r.kind === "STATE_TRANSITION_OF"); assert.ok(t, "the shipped baseline carries STATE_TRANSITION_OF");
  assert.equal(P.relations.filter((r) => r.kind === "STATE_TRANSITION_OF").length, 14); assert.equal(P.relations.filter((r) => r.kind === "SUPERSEDES").length, 0);
  const bad = clone(P); bad.relations.push({ ...t, lid: `rel:g0:SUPERSEDES:${t.source}:${t.target}`, kind: "SUPERSEDES" });
  assert.throws(() => semanticArtifact(bad), (e) => e.code === "WORLD_ENDPOINT_KIND" && /EVIDENCE_STATE_TRANSITION → CLAIM/.test(e.message), "the pre-D-034 edge is refused by the world validator");
  const good = clone(P); const [c1, c2] = good.nodes.filter((n) => n.kind === "CLAIM").slice(0, 2);
  good.relations.push({ lid: `rel:g0:SUPERSEDES:${c1.lid}:${c2.lid}`, kind: "SUPERSEDES", source: c1.lid, target: c2.lid, basis: "observed", snapshot: good.snapshot, attrs: {}, assertions: [] });
  const A = semanticArtifact(good); assert.equal(A.relations.length, P.relations.length + 1, "claim → claim SUPERSEDES is accepted");
  const star = clone(P); const cl = star.nodes.find((n) => n.kind === "CLAIM"), loc = star.locations[0];
  star.relations.push({ lid: `rel:g0:CITES:${cl.lid}:${loc.lid}`, kind: "CITES", source: cl.lid, target: loc.lid, basis: "observed", snapshot: star.snapshot, attrs: {}, assertions: [] });
  assert.equal(semanticArtifact(star).relations.length, P.relations.length + 1, "`*` still means any kind in the pairs form");
});
