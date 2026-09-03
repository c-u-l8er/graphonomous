/* wrl_world.test.mjs — G0-C identity laws over the SHIPPED projections, sealed through the REAL WRL path (WRL-P0, pinned
 * b072db0). Every `sem-`/`rel-`/`rev-` compared here is WRL's; the kernel is called directly (relation-identity.js) to
 * re-derive them, so nothing is trusted because lib/wrl_world.mjs said it. The historical spike (gsem-/grelpre-) appears
 * only in the supersession test. Numbers in test names are measured on the shipped pins. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import * as V2 from "../../../WRL/relation-v2.js";
import { CODES as WRL_CODES } from "../../../WRL/wrl.js";
import { namedInitialAllocation, relationIdFromAllocation, relationRevisionId, RELATION_CODES } from "../../../WRL/relation-identity.js";
import { assertWrlPinned, WRL_PIN, MINTED_BY, encodeObjectId, decodeObjectId, semanticArtifact, seal, sealProjection, PROFILE, PROFILE_ID, WRL_ROW } from "../lib/wrl_world.mjs";
import { spikeIdentities, spikeBytes } from "../lib/wrl_world_spike.mjs";
import { loadProjection } from "../lib/evaluation.mjs";
import { canonicalBytesG0, hashOfBytes, artifactRoot } from "../lib/canon.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const PINS = { baseline: loadProjection(resolve(V, "projections/baseline")), historical: loadProjection(resolve(V, "projections/historical")) };
const P = PINS.baseline;
const clone = (p) => JSON.parse(JSON.stringify({ root: p.root, snapshot: p.snapshot, manifest: p.manifest, nodes: p.nodes, relations: p.relations, assertions: p.assertions, locations: p.locations }));
const shuffled = (arr, seed) => { const a = arr.slice(); let s = (seed >>> 0) || 1; for (let i = a.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) >>> 0; const j = s % (i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const ID = /^(sem|rel|rev)-[0-9a-f]{64}$/;
const worldFile = (name, dir, f) => readFileSync(resolve(V, "projections", name, dir, f));
const shipped = (name) => ({ sem: worldFile(name, "world", "SEM").toString("utf8").trim(), identities: JSON.parse(worldFile(name, "world", "identities.json").toString("utf8")), artifact: worldFile(name, "world", "artifact.json") });
const S0 = await sealProjection(P);
const revMap = (S) => new Map(S.relations.map((r) => [r.relation_name, r.rev])), relMap = (S) => new Map(S.relations.map((r) => [r.relation_name, r.rel]));
const moved = (a, b) => [...a].filter(([k, v]) => b.get(k) !== v).map(([k]) => k);
const codeOf = async (artifact) => { try { await seal(artifact); return "SEALED"; } catch (e) { return e.code; } };

test("the WRL pin is b072db0 with three blobs (relation-v2.js is now a live import); every object_id is \\w+, decodes back to its lid, and the encoding is injective; a colliding object id is refused by G0 naming WRL_DUPLICATE_ID and by WRL with that code", async () => {
  const seen = assertWrlPinned(); assert.deepEqual(Object.keys(seen).sort(), ["relation-identity.js", "relation-v2.js", "wrl.js"]);
  assert.equal(WRL_PIN.commit, "b072db0a983a33108b9a0c4429b978cb07e54148"); assert.equal(WRL_PIN.blobs["relation-v2.js"], "fd1babc5459206c4de1ac1c994b880d24e18ef81");
  const lids = [...P.nodes.map((n) => n.lid), ...P.locations.map((l) => l.lid)]; const ids = lids.map(encodeObjectId);
  assert.ok(ids.every((id) => /^\w+$/.test(id))); assert.equal(new Set(ids).size, lids.length);
  lids.forEach((lid, i) => assert.equal(decodeObjectId(ids[i]), lid));
  assert.equal(encodeObjectId("claim:crosswalk:E-48"), PROFILE.object_id_encoding.example.object_id);
  assert.equal(decodeObjectId(encodeObjectId("a_b:c/d%3F?é")), "a_b:c/d%3F?é");
  assert.notEqual(encodeObjectId("a_b"), encodeObjectId("a__b")); assert.notEqual(encodeObjectId("a:b"), encodeObjectId("a_3Ab"));
  const c = clone(P); c.nodes.push({ ...c.nodes[0] });
  assert.throws(() => semanticArtifact(c), (e) => e.code === "WORLD_OBJECT_ID_COLLISION" && e.wrl_code === "WRL_DUPLICATE_ID");
  const a = semanticArtifact(P); a.objects.push({ ...a.objects[0] }); assert.equal(await codeOf(a), "WRL_DUPLICATE_ID", "WRL refuses the same thing without G0's pre-check");
});

test("(1) same semantic input ⇒ same sem-: two seals of the shipped baseline agree with each other, with world/SEM and byte-for-byte with world/artifact.json (WRL canonical bytes)", async () => {
  const S1 = await sealProjection(P); const W = shipped("baseline");
  assert.match(S0.sem, /^sem-[0-9a-f]{64}$/); assert.equal(S1.sem, S0.sem); assert.ok(S1.bytes.equals(S0.bytes));
  assert.equal(W.sem, S0.sem); assert.ok(W.artifact.equals(S0.bytes), "world/artifact.json is exactly serializeV2Artifact");
  assert.equal(W.identities.sem, S0.sem); assert.equal(W.identities.projection_root, P.root);
  assert.deepEqual(W.identities.relations, S0.relations);
  assert.equal(S0.objects, P.nodes.length + P.locations.length); assert.equal(S0.relations.length, P.relations.length);
});

test("(2) shuffled records ⇒ same sem- and the same bytes (object and seed order are WRL's, not the submission's)", async () => {
  const c = clone(P); c.nodes = shuffled(c.nodes, 7); c.relations = shuffled(c.relations, 8); c.locations = shuffled(c.locations, 9);
  const sub = semanticArtifact(c); assert.notDeepEqual(sub.objects.map((o) => o.object_id).slice(0, 5), semanticArtifact(P).objects.map((o) => o.object_id).slice(0, 5), "the submission really is in a different order");
  const S = await seal(sub); assert.equal(S.sem, S0.sem); assert.ok(S.bytes.equals(S0.bytes)); assert.deepEqual(S.relations, S0.relations);
});

test("(3) an assertion-only (provenance) edit ⇒ same sem-, same every rel-/rev- — while the projection root WOULD move (the edited assertion record's canonical bytes and manifest entry change; WRL D8.3, D-041 §8)", async () => {
  const c = clone(P); const a = c.assertions.find((x) => x.attrs && x.attrs.role); const before = P.assertions.find((x) => x.lid === a.lid);
  a.attrs.role = a.attrs.role + "-edited"; a.attrs.extra_note = "provenance only";
  c.assertions.push({ ...c.assertions[0], lid: c.assertions[0].lid + ":dup" });
  const S = await seal(semanticArtifact(c));
  assert.equal(S.sem, S0.sem); assert.deepEqual(revMap(S), revMap(S0)); assert.deepEqual(relMap(S), relMap(S0));
  // projection-root sensitivity: the manifest entry is sha256 over the record's canonical bytes; recompute the root with the edited record
  const entry = P.manifest.entries.find(([lid]) => lid === a.lid); assert.ok(entry, "the assertion is a manifest entry");
  assert.equal(hashOfBytes(canonicalBytesG0(before)), entry[1], "control: the unedited record hashes to its manifest entry");
  const edited = hashOfBytes(canonicalBytesG0(a)); assert.notEqual(edited, entry[1], "the assertion record's canonical bytes changed");
  const m2 = { ...P.manifest, entries: P.manifest.entries.map(([lid, h]) => (lid === a.lid ? [lid, edited] : [lid, h])) };
  assert.equal(artifactRoot(P.manifest), P.root); assert.notEqual(artifactRoot(m2), P.root, "the projection root moves; the sem- did not");
});

test("(4) one relation semantic edit (attribute) ⇒ that rev- moves, every other rev- holds, sem- moves, EVERY rel- moves (WRL D8.5 / D-043), the statement-lid set is identical", async () => {
  const c = clone(P); const target = c.relations.find((r) => r.kind === "STATES"); target.attrs = { ...target.attrs, relation_field: target.attrs.relation_field + "*" };
  const S = await seal(semanticArtifact(c));
  assert.notEqual(S.sem, S0.sem);
  assert.deepEqual(moved(revMap(S0), revMap(S)), [target.lid], "exactly one rev- moved");
  assert.equal(moved(relMap(S0), relMap(S)).length, S0.relations.length, "every rel- moved (world-scoped allocation)");
  assert.deepEqual([...relMap(S).keys()].sort(), [...relMap(S0).keys()].sort());
});

test("(5) a node semantic edit ⇒ sem- moves, every rev- holds, every rel- moves", async () => {
  const c = clone(P); const n = c.nodes.find((x) => x.kind === "CLAIM"); n.attrs = { ...n.attrs, name: n.attrs.name + " (edited)" };
  const S = await seal(semanticArtifact(c));
  assert.notEqual(S.sem, S0.sem); assert.deepEqual(moved(revMap(S0), revMap(S)), []); assert.equal(moved(relMap(S0), relMap(S)).length, S0.relations.length);
});

test("(6) the kernel mints: for 5 sampled relations and then the whole set, rel- === relationIdFromAllocation(namedInitialAllocation(sem, relation_name)) and rev- === relationRevisionId(revision), through relation-identity.js directly", async () => {
  const canon = new Map(S0.canonical.relations.map((r) => [r.identity_seed.relation_name, r.revision]));
  const n = S0.relations.length; const sample = [0, Math.floor(n / 4), Math.floor(n / 2), Math.floor((3 * n) / 4), n - 1].map((i) => S0.relations[i]);
  assert.equal(new Set(sample.map((r) => r.relation_name)).size, 5);
  for (const r of sample) { assert.equal(await relationIdFromAllocation(namedInitialAllocation(S0.sem, r.relation_name)), r.rel); assert.equal(await relationRevisionId(canon.get(r.relation_name)), r.rev); }
  let agree = 0; for (const r of S0.relations) if ((await relationIdFromAllocation(namedInitialAllocation(S0.sem, r.relation_name))) === r.rel && (await relationRevisionId(canon.get(r.relation_name))) === r.rev) agree++;
  assert.equal(agree, n, `kernel agrees on ${agree}/${n}`);
  assert.ok(S0.relations.every((r) => r.minted_by === MINTED_BY && MINTED_BY === "wrl-kernel@b072db0"));
});

test("(7) no gsem-/grelpre- masquerades at either pin: identities.json carries a historical gsem- ONLY under supersedes.historical_spike_gsem; artifact.json carries no id of any family; sem matches ^sem-[0-9a-f]{64}$; every rel-/rev- is kernel-shaped and labelled wrl-kernel@b072db0", () => {
  for (const name of Object.keys(PINS)) {
    const W = shipped(name); const hits = [];
    const walk = (v, path) => { if (typeof v === "string") { if (/gsem-|grelpre-/.test(v)) hits.push(path); } else if (Array.isArray(v)) v.forEach((x, i) => walk(x, `${path}/${i}`)); else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { assert.ok(!/provisional|never/.test(k), `${name}: spike-era key ${k}`); walk(x, `${path}/${k}`); } };
    walk(W.identities, "");
    assert.deepEqual(hits, ["/supersedes/historical_spike_gsem"], `${name}: gsem-/grelpre- only in the supersession mapping`);
    assert.match(W.sem, /^sem-[0-9a-f]{64}$/); assert.equal(W.identities.sem, W.sem); assert.equal(W.identities.wrl.commit, WRL_PIN.commit);
    assert.ok(W.identities.relations.every((r) => ID.test(r.rel) && r.rel.startsWith("rel-") && ID.test(r.rev) && r.rev.startsWith("rev-") && r.minted_by === "wrl-kernel@b072db0" && Object.keys(r).sort().join() === "minted_by,rel,relation_name,rev"));
    assert.ok(!/\b(sem|rel|rev|gsem|grelpre)-[0-9a-f]{64}\b/.test(W.artifact.toString("utf8")), `${name}: no id of any family in the sealed bytes (idsInArtifactBytes: false)`);
    assert.equal(W.identities.state, "SEALED by WRL (WRL-P0); FROZEN only when GPT accepts this round");
  }
});

test("(8) the admitted row's endpoint pairs cover every (kind, source role, target role) triple measured at both pins, and both pins seal (the shipped SEM is what WRL mints today)", async () => {
  for (const [name, p] of Object.entries(PINS)) {
    const S = await sealProjection(p); assert.equal(S.sem, shipped(name).sem, `${name} re-seals to its shipped SEM`);
    const kinds = new Map([...p.nodes.map((n) => [n.lid, n.kind]), ...p.locations.map((l) => [l.lid, "SOURCE_LOCATION"])]);
    const triples = new Set(p.relations.map((r) => `${r.kind}|${kinds.get(r.source)}|${kinds.get(r.target)}`));
    const uncovered = [...triples].filter((t) => { const [k, s, d] = t.split("|"); const pairs = WRL_ROW.endpoints[k]; return !pairs || !pairs.some(([a, b]) => (a === "*" || a === s) && (b === "*" || b === d)); });
    assert.deepEqual(uncovered, [], `${name}: ${triples.size} measured triples all covered by V2_PROFILES row pairs`);
    assert.ok(triples.size >= 30, `${name}: ${triples.size} triples measured`);
  }
});

test("(9) WRL refuses, with the codes conformance 21j registers: transition→claim SUPERSEDES WRL_UNDECLARED_ENDPOINT_PAIR · undeclared kind WRL_UNDECLARED_KIND · undeclared profile_id WRL_UNSUPPORTED_PROFILE · undeclared policy WRL_UNDECLARED_POLICY · a stated schemas key WRL_V2_WORLD_MISMATCH (+ duplicate seed, dangling terminal, undeclared role, stated ports); G0's pre-check names the same code where it has one", async () => {
  const sub = () => semanticArtifact(P); const sto = (a) => a.relations.find((r) => r.revision.kind === "STATE_TRANSITION_OF");
  const cases = {
    "transition → claim SUPERSEDES": [() => { const a = sub(); sto(a).revision.kind = "SUPERSEDES"; return a; }, "WRL_UNDECLARED_ENDPOINT_PAIR"],
    "an undeclared kind": [() => { const a = sub(); a.relations[0].revision.kind = "WarpTunnel"; return a; }, "WRL_UNDECLARED_KIND"],
    "an undeclared profile_id": [() => ({ ...sub(), profile_id: "graphonomous.semantic.v9" }), "WRL_UNSUPPORTED_PROFILE"],
    "an undeclared policy": [() => { const a = sub(); a.relations[0].revision.policy = "anything.at.all"; return a; }, "WRL_UNDECLARED_POLICY"],
    "a stated schemas key": [() => ({ ...sub(), schemas: {} }), "WRL_V2_WORLD_MISMATCH"],
    "a duplicate identity seed": [() => { const a = sub(); a.relations.push({ ...a.relations[0] }); return a; }, "WRL_DUPLICATE_RELATION_SEED"],
    "a terminal naming no object": [() => { const a = sub(); a.relations[0].revision.endpoints[0].terminal.object_id = "ghost"; return a; }, "WRL_UNKNOWN_ENDPOINT"],
    "an undeclared role": [() => { const a = sub(); a.objects[0].role = "Alien"; return a; }, "WRL_UNDECLARED_ROLE"],
    "a stated ports list the role does not declare": [() => { const a = sub(); a.objects[0].ports = ["node", "extra"]; return a; }, "WRL_V2_WORLD_MISMATCH"],
  };
  const got = {}; for (const [what, [build]] of Object.entries(cases)) got[what] = await codeOf(build());
  assert.deepEqual(got, Object.fromEntries(Object.entries(cases).map(([w, [, c]]) => [w, c])));
  const registered = new Set([...Object.keys(V2.RELATION_V2_CODES), ...Object.keys(WRL_CODES), ...Object.keys(RELATION_CODES)]); for (const [, c] of Object.values(cases)) assert.ok(registered.has(c), `${c} registered in one of the three WRL code registries (relation-v2 / wrl.js / relation-identity)`);
  await assert.rejects(seal(cases["an undeclared kind"][0]()), (e) => e.code === "WRL_UNDECLARED_KIND" && typeof e.fieldPath === "string");
  // G0's pre-check on the PROJECTION-level edit names the same WRL code and refuses before the seal
  const bad = clone(P); const t = bad.relations.find((r) => r.kind === "STATE_TRANSITION_OF"); bad.relations.push({ ...t, lid: `rel:g0:SUPERSEDES:${t.source}:${t.target}`, kind: "SUPERSEDES" });
  assert.throws(() => semanticArtifact(bad), (e) => e.code === "WORLD_ENDPOINT_KIND" && e.wrl_code === "WRL_UNDECLARED_ENDPOINT_PAIR" && /EVIDENCE_STATE_TRANSITION → CLAIM/.test(e.message));
  const d = clone(P); d.relations.push({ ...d.relations[0], lid: d.relations[0].lid + ":x", source: "claim:crosswalk:E-99" });
  assert.throws(() => semanticArtifact(d), (e) => e.code === "WORLD_DANGLING_TERMINAL" && e.wrl_code === "WRL_UNKNOWN_ENDPOINT");
});

test("(10) supersession at both pins: supersedes.historical_spike_gsem equals world-spike/GSEM and what the spike code reproduces from the same projection; the spike receipt's bytes are untouched; MEASURED at b072db0: the spike's bytes EQUAL WRL's canonical bytes, so the sem- hex equals the gsem- hex — an equivalence measured per pin, not a rule (D-041: not required, not forbidden); the spike is not a seal, and no grelpre- equals any kernel rel- (the allocation scope differs: gsem- vs sem-)", async () => {
  for (const [name, p] of Object.entries(PINS)) {
    const W = shipped(name); const sub = semanticArtifact(p); const S = await seal(sub); const spike = spikeIdentities(sub);
    assert.ok(existsSync(resolve(V, "projections", name, "world-spike", "GSEM")), `${name}: the D-037 spike world was moved to world-spike/`);
    const gsem = worldFile(name, "world-spike", "GSEM").toString("utf8").trim(); assert.match(gsem, /^gsem-[0-9a-f]{64}$/);
    assert.equal(W.identities.supersedes.historical_spike_gsem, gsem); assert.equal(spike.gsem, gsem, `${name}: the spike code reproduces the receipt`);
    assert.ok(worldFile(name, "world-spike", "artifact.json").equals(spike.bytes), `${name}: world-spike/artifact.json is the untouched spike receipt`);
    const spikeIds = JSON.parse(worldFile(name, "world-spike", "identities.json").toString("utf8")); assert.equal(spikeIds.gsem, gsem);
    assert.deepEqual(spikeIds.relations.map((r) => [r.relation_name, r.provisional_allocation_preimage_id]), spike.relations.map((r) => [r.relation_name, r.provisional_allocation_preimage_id]));
    // the measured relation between the two byte strings — recorded, not assumed
    assert.ok(spike.bytes.equals(S.bytes), `${name}: MEASURED — the spike reproduced WRL's canonicalization byte for byte`);
    assert.equal(S.sem.slice("sem-".length), gsem.slice("gsem-".length), `${name}: MEASURED — same hex; the prefix says who sealed it (WRL) and who did not (the spike)`);
    assert.notEqual(S.sem, gsem);
    const rel = relMap(S); assert.ok(spike.relations.every((r) => "rel-" + r.provisional_allocation_preimage_id.slice("grelpre-".length) !== rel.get(r.relation_name)), `${name}: every grelpre- differs from the kernel rel- (world scope)`);
    assert.equal(spike.relations.length, S.relations.length);
  }
});

test("declaration reconcile: every facet of V2_PROFILES['graphonomous.semantic.v0'] (the ADMITTED declaration) agrees with handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json (the SUBMITTED one): rulepack, policies, domain, signature, roles, ports, kinds, endpoint pairs", () => {
  const row = WRL_ROW; const S = (x) => JSON.stringify(x); assert.equal(row.derivation, "static"); assert.equal(PROFILE_ID, "graphonomous.semantic.v0");
  assert.equal(row.rulepack_id, PROFILE.semantic_policies.rulepack_id);
  assert.deepEqual(row.policies, [PROFILE.canonical_defaults.policy]);
  assert.equal(row.domain, PROFILE.relation_signatures.domain);
  assert.equal(S(row.signature), S({ orientation: PROFILE.relation_signatures.orientation, texture: PROFILE.relation_signatures.texture, arity: PROFILE.relation_signatures.arity, endpoint_roles: PROFILE.relation_signatures.endpoint_roles }));
  assert.deepEqual(Object.keys(row.roles), PROFILE.roles.kinds); assert.equal(Object.keys(row.roles).length, 21);
  assert.ok(Object.values(row.roles).every((p) => S(p) === S(PROFILE.roles.ports)));
  assert.deepEqual(Object.keys(row.endpoints), PROFILE.relation_signatures.kinds); assert.equal(Object.keys(row.endpoints).length, 31);
  const theirs = Object.fromEntries(Object.entries(PROFILE.endpoint_constraints).filter(([k]) => k !== "note"));
  const norm = (o) => S(Object.keys(o).sort().map((k) => [k, o[k].map((p) => p.join(">")).sort()]));
  assert.equal(norm(row.endpoints), norm(theirs));
  assert.equal(Object.values(row.endpoints).reduce((n, v) => n + v.length, 0), 92); assert.equal(Object.values(theirs).reduce((n, v) => n + v.length, 0), 92);
  assert.equal(PROFILE.world_identity.prefix, "sem-"); assert.equal(PROFILE.canonical_defaults.texture, row.signature.texture);
});

test("D-037 in the admitted profile: SUPERSEDES is same-kind only, STATE_TRANSITION_OF is transition → claim, the shipped baseline carries 14 / 0, claim → claim SUPERSEDES and a `*` CITES seal", async () => {
  assert.deepEqual(WRL_ROW.endpoints.SUPERSEDES, [["CLAIM", "CLAIM"], ["ROUND", "ROUND"], ["EVIDENCE_STATE_TRANSITION", "EVIDENCE_STATE_TRANSITION"]]);
  assert.deepEqual(WRL_ROW.endpoints.STATE_TRANSITION_OF, [["EVIDENCE_STATE_TRANSITION", "CLAIM"]]);
  assert.equal(P.relations.filter((r) => r.kind === "STATE_TRANSITION_OF").length, 14); assert.equal(P.relations.filter((r) => r.kind === "SUPERSEDES").length, 0);
  const good = clone(P); const [c1, c2] = good.nodes.filter((n) => n.kind === "CLAIM").slice(0, 2);
  good.relations.push({ lid: `rel:g0:SUPERSEDES:${c1.lid}:${c2.lid}`, kind: "SUPERSEDES", source: c1.lid, target: c2.lid, basis: "observed", snapshot: good.snapshot, attrs: {}, assertions: [] });
  const cl = good.nodes.find((n) => n.kind === "CLAIM"), loc = good.locations[0];
  good.relations.push({ lid: `rel:g0:CITES:${cl.lid}:${loc.lid}`, kind: "CITES", source: cl.lid, target: loc.lid, basis: "observed", snapshot: good.snapshot, attrs: {}, assertions: [] });
  const S = await seal(semanticArtifact(good)); assert.equal(S.relations.length, P.relations.length + 2); assert.notEqual(S.sem, S0.sem);
});
