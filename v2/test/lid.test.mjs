import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLid, parseLid, isLid, relationLid, assertionLid, locationLid, contextBoundLid, LidTable, KIND_PREFIX, PREFIXES, RELATION_KINDS, RELATION_QUALIFIERS } from "../lib/lid.mjs";

test("every kind has a distinct lowercase prefix", () => {
  assert.equal(new Set(PREFIXES).size, PREFIXES.length);
  for (const p of PREFIXES) assert.match(p, /^[a-z]+$/);
});

test("makeLid spells the spec's examples", () => {
  assert.equal(makeLid("CLAIM", "crosswalk", "E-13b").lid, "claim:crosswalk:E-13b");
  assert.equal(makeLid("LAW", "trvm", "kappa.monotonicity.unrestricted@1").lid, "law:trvm:kappa.monotonicity.unrestricted@1");
  assert.equal(makeLid("FINDING", "computedriven", "F35").lid, "finding:computedriven:F35");
  assert.equal(makeLid("ADJUDICATION", "gpt", "exec-v1:s1").lid, "adjudication:gpt:exec-v1:s1");
  assert.equal(makeLid("RECEIPT", "sha256", "6ba8544cbf7c91ef").lid, "receipt:sha256:6ba8544cbf7c91ef");
});

test("a local part outside the grammar falls back to a hash and says so", () => {
  const r = makeLid("PROFILE", "text", "single host; one deployment-supplied anchor namespace");
  assert.equal(r.fallback, true);
  assert.match(r.lid, /^profile:text:h\.[0-9a-f]{16}$/);
  assert.equal(r.raw, "single host; one deployment-supplied anchor namespace");
  // deterministic
  assert.equal(makeLid("PROFILE", "text", r.raw).lid, r.lid);
  // the spec's § is not ASCII: refused into fallback, never transliterated silently
  assert.equal(makeLid("ADJUDICATION", "gpt", "exec-v1:§1").fallback, true);
});

test("namespaces and kinds are validated", () => {
  assert.throws(() => makeLid("CLAIM", "CrossWalk", "E-1"), /BAD_NAMESPACE/);
  assert.throws(() => makeLid("claim", "crosswalk", "E-1"), /BAD_KIND/);
  assert.throws(() => makeLid("CLAIM", "crosswalk", ""), /BAD_LOCAL/);
});

test("parseLid round-trips and refuses garbage", () => {
  const p = parseLid("loc:crosswalk:4639a28d888a54abe5c2a804f4bcfc4278566139:package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json#/records/12");
  assert.equal(p.kind, "SOURCE_LOCATION"); assert.equal(p.namespace, "crosswalk");
  assert.equal(p.local, "4639a28d888a54abe5c2a804f4bcfc4278566139:package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json#/records/12");
  assert.equal(isLid("claim:crosswalk:E 13"), false);
  assert.equal(isLid("nope:crosswalk:E-13"), false);
  assert.equal(isLid("claim::E-13"), false);
});

test("relation lids are propositions (D-029): no kind takes a citation qualifier; only a declared typed semantic qualifier is accepted", () => {
  const a = "claim:crosswalk:E-44", b = "obligation:g0:S1";
  assert.equal(relationLid("DERIVES_FROM", a, b), "rel:g0:DERIVES_FROM:claim:crosswalk:E-44:obligation:g0:S1");
  assert.throws(() => relationLid("DERIVES_FROM", a, b, "loc:crosswalk:x:y"), /QUALIFIER_NOT_ALLOWED/);
  // the pre-B.1 per-citation relation is gone: WITNESSES is one relation per (witness, claim), however many citations
  const w = relationLid("WITNESSES", "witness:crosswalk:x", a);
  assert.equal(w, "rel:g0:WITNESSES:witness:crosswalk:x:claim:crosswalk:E-44");
  assert.throws(() => relationLid("WITNESSES", "witness:crosswalk:x", a, "loc:crosswalk:oid:path"), /QUALIFIER_NOT_ALLOWED/);
  assert.throws(() => relationLid("WITNESSES", "witness:crosswalk:x", a, "role=sensitivity"), /QUALIFIER_NOT_ALLOWED/);
  assert.deepEqual(RELATION_QUALIFIERS, {}, "no field of the first source changes a proposition; the table is declared empty, not absent");
  assert.throws(() => relationLid("LOVES", a, b), /BAD_RELATION_KIND/);
  assert.equal(RELATION_KINDS.length, 32, "30 of spec §3.2 + D-027, STATE_TRANSITION_OF (D-037), DISCHARGED_BY (D-064, semantic.v1)");
  assert.ok(RELATION_KINDS.includes("STATE_TRANSITION_OF"));
  assert.ok(RELATION_KINDS.includes("DISCHARGED_BY"), "v1 adds exactly one kind; the profile, not this table, decides which world may carry it");
  // A lid prefix is NOT profile-scoped: a lid is a statement NAME and carries no profile, which is what makes a v0 lid
  // and a v1 lid comparable across worlds (measured: 1,574/1,574 shared statements, same rev-, different rel-).
  for (const role of ["ARGUMENT", "DEFEATER", "INSTRUMENT"]) assert.ok(KIND_PREFIX[role], role);
  assert.equal(makeLid("ARGUMENT", "factory", "ARG-FED-1PA-DEC-CITATION").lid, "argument:factory:ARG-FED-1PA-DEC-CITATION");
  assert.equal(makeLid("DEFEATER", "factory", "DEF-R83-UNTRUSTED-COUNT").lid, "defeater:factory:DEF-R83-UNTRUSTED-COUNT");
  assert.equal(makeLid("INSTRUMENT", "factory", "INS-PANEL").lid, "instrument:factory:INS-PANEL");
});

test("context-bound anonymous identity (D-030): same container + same sentence => one lid; another container or another sentence => another lid", () => {
  const r8 = "round:computedriven:R0.8", r9 = "round:computedriven:R0.9", s = "single-host only \u2014 no partition-tolerant consensus claim";
  const a = contextBoundLid("FINDING", "inv", r8, s);
  assert.match(a, /^finding:inv:h\.[0-9a-f]{16}$/);
  assert.equal(contextBoundLid("FINDING", "inv", r8, s), a, "deterministic");
  assert.notEqual(contextBoundLid("FINDING", "inv", r9, s), a, "a different container is a different finding");
  assert.notEqual(contextBoundLid("FINDING", "inv", r8, s + " "), a, "the exact source string, no normalization");
  // the NUL separator makes the encoding injective: moving a character across the boundary cannot collide
  assert.notEqual(contextBoundLid("FINDING", "inv", "round:computedriven:R0", ".8" + s), a);
  assert.throws(() => contextBoundLid("FINDING", "inv", "not a lid", s), /BAD_LID/);
  assert.throws(() => contextBoundLid("FINDING", "inv", r8, ""), /BAD_LOCAL/);
});

test("assertion and location lids", () => {
  const loc = locationLid("crosswalk", "4639a28d888a54abe5c2a804f4bcfc4278566139", "package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json", "/records/0");
  assert.equal(loc.fallback, false);
  assert.equal(assertionLid("claim:crosswalk:E-01", loc.lid), `asrt:g0:claim:crosswalk:E-01:${loc.lid}`);
});

test("LidTable is idempotent for identical content and refuses a collision", () => {
  const t = new LidTable();
  assert.equal(t.add("claim:crosswalk:E-01", "sha256:aa"), "new");
  assert.equal(t.add("claim:crosswalk:E-01", "sha256:aa"), "same");
  assert.throws(() => t.add("claim:crosswalk:E-01", "sha256:bb"), /DUPLICATE_ID/);
  assert.equal(t.size, 1);
  assert.equal(Object.keys(KIND_PREFIX).length, PREFIXES.length);
});

test("D-037 endpoint constraint: transition → claim SUPERSEDES is REFUSED at lid minting (so at emission and projection); claim → claim SUPERSEDES and transition → claim STATE_TRANSITION_OF are accepted", () => {
  const t = "transition:crosswalk:E-14:promotion:v2.7", c = "claim:crosswalk:E-14", c2 = "claim:crosswalk:E-13b", t2 = "transition:crosswalk:E-14:v2.5-%3Ev2.6", r = "round:computedriven:R0.8", r2 = "round:computedriven:R0.9";
  assert.throws(() => relationLid("SUPERSEDES", t, c), (e) => e.code === "ENDPOINT_REFUSED" && /EVIDENCE_STATE_TRANSITION → CLAIM/.test(e.message), "the pre-D-034 edge can no longer be spelled");
  assert.throws(() => relationLid("SUPERSEDES", c, t), (e) => e.code === "ENDPOINT_REFUSED");
  assert.throws(() => relationLid("SUPERSEDES", r, c), (e) => e.code === "ENDPOINT_REFUSED");
  assert.equal(relationLid("SUPERSEDES", c2, c), `rel:g0:SUPERSEDES:${c2}:${c}`, "claim → claim is a replacement between comparable entities");
  assert.equal(relationLid("SUPERSEDES", r2, r), `rel:g0:SUPERSEDES:${r2}:${r}`);
  assert.equal(relationLid("SUPERSEDES", t, t2), `rel:g0:SUPERSEDES:${t}:${t2}`, "transition → transition is allowed only when a source states it; the adapter never infers it from order");
  assert.equal(relationLid("STATE_TRANSITION_OF", t, c), `rel:g0:STATE_TRANSITION_OF:${t}:${c}`);
  assert.throws(() => relationLid("STATE_TRANSITION_OF", c, t), (e) => e.code === "ENDPOINT_REFUSED", "STATE_TRANSITION_OF is transition → claim only");
  assert.equal(relationLid("CITES", t, c), `rel:g0:CITES:${t}:${c}`, "kinds without a declared pair table are unconstrained here (the world profile constrains them)");
});
