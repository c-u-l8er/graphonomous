/* consistency.test.mjs — G1-A: a finding is DERIVED, ORDER-INDEPENDENT, EXPLAINABLE TO OBSERVED PREMISES, and
 * CHANGES WITH THE SNAPSHOT (GPT Adjudication v6 §10/§12 → D-071, D-074).
 *
 * Each accepted rule gets a POSITIVE fixture (it fires, and on the right premises) and a REFUSAL/NEGATIVE fixture (it
 * does NOT fire when the thing it detects is absent). Three of GPT's seven candidates were reduced to zero against
 * the real data and are NOT implemented — the reasons are asserted here too, so a future session that adds one has to
 * come through this file.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { RULES, REJECTED, RETIRED, RULEPACK_ID, RULEPACK_V0, RULEPACK_V1, DEFAULT_RULEPACK, rulesOf, CLASSES, findingId, contextFor, runConsistency, PRESERVED_ROOTS } from "../lib/consistency.mjs";
import { runLinkage, readLinkage, RULEPACK_ID as LINK_RULEPACK, LINK_RELATION } from "../lib/linkage.mjs";
import { liveChainIds } from "../lib/certificate.mjs";
import { loadProfile, submittedFacets, admittedFacets } from "../lib/wrl_world.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DIR = (n) => join(V, "projections", n);
const PROFILES = () => ["graphonomous.semantic.v0", "graphonomous.semantic.v1"].map((id) => ({ id, at: `handoff/WRL_SCHEMA_OR_PROFILE/${id}.json`, submitted: submittedFacets(loadProfile(id)), admitted: admittedFacets(id) }));
const ctxOf = (n, extra = {}) => contextFor(DIR(n), { liveChain: liveChainIds(), profiles: PROFILES(), ...extra });
const run = (n, extra) => runConsistency(ctxOf(n, extra));

const TRI = run("tri");
const MULTI_V1 = run("multi-v1");

test("TWO rulepacks are declared: v0 with its six rules kept intact as a pre-linkage receipt, v1 with the five that survive, and the removal states its reason exactly as a rejection does", () => {
  assert.equal(RULEPACK_V0, "graphonomous.consistency.rules.v0");
  assert.equal(RULEPACK_V1, "graphonomous.consistency.rules.v1");
  assert.equal(DEFAULT_RULEPACK, RULEPACK_V1, "the current pack is the default; v0 is history");
  assert.equal(RULEPACK_ID, RULEPACK_V1);
  assert.equal(rulesOf(RULEPACK_V0).length, 6);
  assert.equal(rulesOf(RULEPACK_V1).length, 5);
  assert.equal(RULES.length, 5);
  /* v1 is v0 MINUS one rule, carried forward in GPT v7 §11's order, with nothing invented to keep the count at six */
  const v0 = rulesOf(RULEPACK_V0).map((r) => r.id), v1 = rulesOf(RULEPACK_V1).map((r) => r.id);
  assert.deepEqual(v0.filter((id) => !v1.includes(id)), ["CROSS_REGISTRY_COREFERENCE_UNLINKED"]);
  assert.deepEqual(v1.filter((id) => !v0.includes(id)), [], "v1 added nothing");
  assert.deepEqual(v1, ["REFERENCE_TARGET_DRIFT", "SOURCE_PIN_DIVERGENCE", "LAW_REFERENCE_UNRESOLVED", "CERTIFICATE_COORDINATE_STALE", "PROFILE_DECLARATION_DRIFT"]);
  /* the v0 rule objects are the SAME objects, so v0's receipts stay reproducible */
  for (const id of v1) assert.equal(rulesOf(RULEPACK_V1).find((r) => r.id === id), rulesOf(RULEPACK_V0).find((r) => r.id === id));

  for (const pack of [RULEPACK_V0, RULEPACK_V1]) for (const r of rulesOf(pack)) {
    assert.ok(CLASSES.includes(r.class), `${r.id}: class ${r.class} is not one of ${CLASSES.join("/")}`);
    assert.ok(r.states.length > 60, `${r.id}: states what it detects`);
    assert.ok(r.decidable_absence.length > 20, `${r.id}: must say when absence is decidable`);
    assert.equal(typeof r.version, "number");
  }
  /* a REMOVAL carries its measurement, its successor and the case that is still a finding */
  assert.equal(RETIRED.length, 1);
  const [ret] = RETIRED;
  assert.equal(ret.id, "CROSS_REGISTRY_COREFERENCE_UNLINKED");
  assert.equal(ret.retired_in, RULEPACK_V1);
  assert.equal(ret.superseded_by, "graphonomous.linkage.rules.v0 / EXACT_EXTERNAL_COREFERENCE");
  assert.ok(ret.why.length > 200, "a removal needs its measurement");
  assert.ok(ret.still_a_finding_when.length > 40, "a removal must say what is STILL a finding");

  assert.deepEqual(REJECTED.map((r) => r.id).sort(), ["AUTHORITY_STATE_CONFLICT", "QUALIFIED_ID_COLLISION", "VOCABULARY_MEANING_CONFLICT"]);
  for (const r of REJECTED) { assert.ok(r.why.length > 150); assert.ok(r.reopen_when.length > 20); }
  /* every one of GPT's seven candidates is accounted for: implemented, retired, or reduced */
  const named = new Set([...rulesOf(RULEPACK_V0).map((r) => r.id), ...REJECTED.map((r) => r.id)]);
  for (const c of ["QUALIFIED_ID_COLLISION", "AUTHORITY_STATE_CONFLICT", "REFERENCE_TARGET_DRIFT", "PROFILE_DECLARATION_DRIFT", "CERTIFICATE_COORDINATE_STALE", "LAW_REFERENCE_UNRESOLVED", "VOCABULARY_MEANING_CONFLICT"]) assert.ok(named.has(c), `candidate ${c} unaccounted for`);
});


test("EVERY finding is visibly derived and carries no authority: basis derived, trvm_derivation false, a content-bound id, a snapshot, a projection root, families, premises and an explanation", () => {
  /* both packs, because a v0 receipt must stay as well-formed as a v1 finding */
  const all = [...TRI.findings, ...MULTI_V1.findings, ...run("baseline").findings,
    ...runConsistency(ctxOf("tri"), { rulepack: RULEPACK_V0 }).findings];
  assert.ok(all.length >= 25, `only ${all.length} findings across three projections and two rulepacks`);
  for (const f of all) {
    assert.equal(f.basis, "derived");
    assert.equal(f.trvm_derivation, false);
    assert.equal(f.authority, "none");
    assert.ok([RULEPACK_V0, RULEPACK_V1].includes(f.rulepack), `${f.rule}: unknown rulepack ${f.rulepack}`);
    assert.match(f.lid, /^cfind-[0-9a-f]{64}$/);
    assert.equal(f.lid, findingId(f), "the id does not identify the finding beside it");
    assert.match(f.snapshot, /^snapshot:g0:/);
    assert.match(f.projection_root, /^root-[0-9a-f]{64}$/);
    assert.ok(f.families.length >= 1);
    assert.ok(f.premises.length >= 1, `${f.rule}: a finding with no premises is an opinion`);
    assert.ok(Array.isArray(f.explain) && f.explain.length >= 2, `${f.rule}: explain must be a chain, not a sentence`);
    assert.ok(CLASSES.includes(f.class));
    /* nothing in a finding may look like a repair, a proposal, or a state promotion */
    const text = JSON.stringify(f);
    for (const forbidden of ['"repair"', '"proposal"', '"promote"', '"fix"', '"apply"']) assert.ok(!text.includes(forbidden), `${f.rule}: a finding must not carry ${forbidden}`);
  }
});

test("every premise is an OBSERVED thing, and explain bottoms out in it — never in a conclusion", () => {
  for (const f of [...TRI.findings, ...run("multi").findings]) {
    for (const p of f.premises) {
      assert.ok(["node", "relation", "pinned_file", "source_pin", "certificate", "verifier", "registry", "declaration"].includes(p.kind), `${f.rule}: premise kind ${p.kind}`);
      assert.equal(typeof p.ref, "string");
      assert.ok(p.ref.length > 0);
      /* a premise never carries another finding */
      assert.ok(!String(p.ref).startsWith("cfind-"), "a finding may not be a premise of a finding");
    }
    /* every explain line names something that appears in a premise, or is the rule's stated caveat */
    const refs = f.premises.map((p) => p.ref);
    const mentioned = f.explain.filter((line) => refs.some((r) => line.includes(r) || line.includes(String(r).slice(0, 24))));
    assert.ok(mentioned.length >= 1, `${f.rule}: no explain line names a premise\n${f.explain.join("\n")}`);
  }
});

/* ─────────────────────────── positive fixtures, on real data ─────────────────────────── */

test("POSITIVE — REFERENCE_TARGET_DRIFT fires on the real thing it was written for: one snapshot reads TRVM/governance/invariant-grid.json at two different blobs", () => {
  const f = TRI.findings.filter((x) => x.rule === "REFERENCE_TARGET_DRIFT");
  assert.equal(f.length, 1);
  assert.equal(f[0].class, "drift");
  assert.deepEqual(f[0].families, ["trvm", "trvm-gov"]);
  assert.match(f[0].detail, /invariant-grid\.json is pinned by 2 source declarations at 2 different blobs/);
  const blobs = f[0].premises.map((p) => p.observed.blob);
  assert.equal(new Set(blobs).size, 2, "the two premises must name two different blobs");
  const bytes = f[0].premises.map((p) => p.observed.bytes).sort((a, b) => a - b);
  assert.ok(bytes[1] > bytes[0], "the two coordinates are not even the same size");
});

test("POSITIVE — SOURCE_PIN_DIVERGENCE fires: one snapshot names TRVM at two commits, and the finding says this is LEGAL rather than calling it a contradiction", () => {
  const f = TRI.findings.filter((x) => x.rule === "SOURCE_PIN_DIVERGENCE");
  assert.equal(f.length, 1);
  assert.equal(f[0].class, "drift");
  const commits = f[0].premises.map((p) => p.ref.split("@")[1]);
  assert.equal(new Set(commits).size, 2);
  assert.ok(commits.includes("8816e59055322fc608c9bc7dae9723c02d8402b7"), "the governance pin");
  assert.ok(f[0].explain.some((l) => /LEGAL/.test(l) && /not a contradiction/.test(l)), "a drift finding must not be dressed up as a contradiction");
});

test("PRE-LINKAGE RECEIPT — the retired rule still fires 13 times under rulepack v0, and does not exist at all under v1: the evidence did not change, its classification did", () => {
  const v0 = runConsistency(ctxOf("tri"), { rulepack: RULEPACK_V0 });
  const f = v0.findings.filter((x) => x.rule === "CROSS_REGISTRY_COREFERENCE_UNLINKED");
  assert.equal(f.length, 13, "the v0 pack must still reproduce exactly what it saw before linkage existed");
  for (const x of f) {
    assert.equal(x.rulepack, RULEPACK_V0);
    assert.equal(x.class, "unresolved");
    assert.deepEqual(x.families, ["trvm", "trvm-gov"]);
    assert.equal(x.premises.length, 2);
    assert.equal(new Set(x.premises.map((p) => p.observed.citation)).size, 1, "both premises must name ONE external identity");
    assert.equal(new Set(x.premises.map((p) => p.ref.split(":")[1])).size, 2, "the two statements must be in two namespaces");
  }
  /* under v1 the rule is GONE — not zero-count, absent */
  assert.equal(TRI.counts.CROSS_REGISTRY_COREFERENCE_UNLINKED, undefined);
  assert.ok(!rulesOf(RULEPACK_V1).some((r) => r.id === "CROSS_REGISTRY_COREFERENCE_UNLINKED"));
  /* and the same 13 pairs are now LINKS, one for one */
  const links = runLinkage(ctxOf("tri")).links;
  assert.equal(links.length, 13);
  const pairKey = (a, b) => [a, b].sort().join("|");
  const wasFinding = new Set(f.map((x) => pairKey(x.premises[0].ref, x.premises[1].ref)));
  const isLink = new Set(links.map((l) => pairKey(l.endpoints[0], l.endpoints[1])));
  assert.deepEqual([...isLink].sort(), [...wasFinding].sort(), "every retired finding became exactly one link, and no link is new");
});


test("POSITIVE — CERTIFICATE_COORDINATE_STALE fires on the preserved receipts, names the exact coordinate that moved, and says in so many words that it is a status and not an invalidity claim", () => {
  const f = run("baseline").findings.filter((x) => x.rule === "CERTIFICATE_COORDINATE_STALE");
  assert.ok(f.length >= 4, `expected the preserved baseline receipts to be stale, got ${f.length}`);
  for (const x of f) {
    assert.equal(x.class, "stale");
    assert.equal(x.premises.length, 2);
    assert.ok(x.premises.some((p) => p.kind === "certificate" && /^vclaim-/.test(p.ref)));
    assert.ok(x.premises.some((p) => p.kind === "verifier"));
    assert.match(x.detail, /chain_ids|projector|checker|trvm_commit/);
    assert.ok(x.explain.some((l) => /STATUS, NOT AN INVALIDITY CLAIM/.test(l)), "the D-060 caveat must travel with the finding");
    assert.ok(x.explain.some((l) => /this verifier's live value is/.test(l)), "the finding must name what the live verifier says");
  }
  /* the pre-trvm receipts moved EXACTLY ONE coordinate — the residue D-072 measured */
  const pretrvm = f.filter((x) => x.premises.some((p) => String(p.at).includes("pre-trvm/")));
  assert.ok(pretrvm.length >= 2, "the pre-trvm re-mint should be visible as stale");
  for (const x of pretrvm) assert.match(x.detail, /projector/);
});

/* ─────────────────────────── negative fixtures ─────────────────────────── */

test("NEGATIVE — LAW_REFERENCE_UNRESOLVED does NOT fire on the real data (all 13 crosswalk citations resolve and are canonical), and the fixture proves it CAN fire when a revision does not resolve", () => {
  assert.equal(TRI.counts.LAW_REFERENCE_UNRESOLVED, 0, "a rule reporting zero is a measurement, and this one measured zero");

  const ctx = ctxOf("tri");
  const gov = ctx.nodes.filter((n) => n.kind === "LAW" && n.lid.split(":")[1] === "trvm-gov");
  assert.equal(gov.length, 139, "the owning registry the rule decides against");
  /* bump one crosswalk citation to a revision the registry does not hold */
  const cw = ctx.nodes.find((n) => n.kind === "LAW" && n.lid.split(":")[1] === "trvm");
  const known = cw.attrs.citation;
  const bumped = { ...cw, attrs: { ...cw.attrs, citation: known.replace(/@\d+$/, "@99") } };
  const hit = runConsistency({ ...ctx, nodes: ctx.nodes.map((n) => (n === cw ? bumped : n)) });
  const f = hit.findings.filter((x) => x.rule === "LAW_REFERENCE_UNRESOLVED");
  assert.equal(f.length, 1);
  assert.equal(f[0].class, "unresolved");
  assert.match(f[0].detail, /names revision 99 of a law the registry knows only at revision\(s\) \d+/);
  assert.ok(f[0].explain.some((l) => /the REVISION is the coordinate that does not resolve/.test(l)));
  assert.ok(f[0].explain.some((l) => /Absence is decidable here/.test(l)), "the rule must say why absence counts");

  /* and an id the registry has never heard of takes the other branch */
  const alien = { ...cw, attrs: { ...cw.attrs, citation: "law:not.a.real.law@1" } };
  const f2 = runConsistency({ ...ctx, nodes: ctx.nodes.map((n) => (n === cw ? alien : n)) }).findings.filter((x) => x.rule === "LAW_REFERENCE_UNRESOLVED");
  assert.equal(f2.length, 1);
  assert.match(f2[0].detail, /names a law id the registry does not contain at all/);
});

test("NEGATIVE — LAW_REFERENCE_UNRESOLVED does not fire at all when no owning registry is in the projection: a rule with nothing to decide against decides nothing", () => {
  assert.equal(MULTI_V1.counts.LAW_REFERENCE_UNRESOLVED, 0);
  const ctx = ctxOf("multi-v1");
  assert.equal(ctx.nodes.filter((n) => n.kind === "LAW" && n.lid.split(":")[1] === "trvm-gov").length, 0);
  /* multi-v1 DOES contain the crosswalk's 13 law citations; they are not reported unresolved, because with no owning
     registry present "unresolved" would be a statement about this projection's scope, not about the sources. */
  assert.ok(ctx.nodes.filter((n) => n.kind === "LAW" && n.lid.split(":")[1] === "trvm").length >= 13);
});

test("NEGATIVE — PROFILE_DECLARATION_DRIFT does not fire: the submitted and admitted declarations of BOTH profiles agree facet for facet. The fixture proves it fires when one facet moves.", () => {
  assert.equal(TRI.counts.PROFILE_DECLARATION_DRIFT, 0);
  const ctx = ctxOf("tri");
  assert.equal(ctx.profiles.length, 2);
  for (const p of ctx.profiles) assert.deepEqual(p.submitted, p.admitted, `${p.id}: submitted and admitted disagree TODAY`);

  const bent = ctx.profiles.map((p, i) => (i === 0 ? { ...p, submitted: { ...p.submitted, rulepack_id: "graphonomous.semantic.rules.vX" } } : p));
  const f = runConsistency({ ...ctx, profiles: bent }).findings.filter((x) => x.rule === "PROFILE_DECLARATION_DRIFT");
  assert.equal(f.length, 1);
  assert.equal(f[0].class, "contradiction");
  assert.deepEqual(f[0].families, ["graphonomous", "wrl"]);
  assert.match(f[0].detail, /rulepack_id differ/);
});

test("NEGATIVE — REFERENCE_TARGET_DRIFT and SOURCE_PIN_DIVERGENCE do not fire on multi-v1, whose six sources name six distinct repositories at one commit each", () => {
  assert.equal(MULTI_V1.counts.REFERENCE_TARGET_DRIFT, 0);
  assert.equal(MULTI_V1.counts.SOURCE_PIN_DIVERGENCE, 0);
  const ctx = ctxOf("multi-v1");
  const repos = ctx.snapshot.sources.map((s) => s.repo);
  assert.equal(new Set(repos).size, repos.length, "no repository appears twice in multi-v1");
});

test("NEGATIVE — under rulepack v0 the retired rule is silenced by ONE linking relation, and no other rule's count moves (kept so the v0 receipts stay explainable)", () => {
  const ctx = ctxOf("tri");
  const v0 = runConsistency(ctx, { rulepack: RULEPACK_V0 });
  const one = v0.findings.find((x) => x.rule === "CROSS_REGISTRY_COREFERENCE_UNLINKED");
  const [a, b] = one.premises.map((p) => p.ref);
  const linked = runConsistency({ ...ctx, relations: [...ctx.relations, { lid: `rel:g0:CITES:${a}:${b}`, kind: "CITES", source: a, target: b }] }, { rulepack: RULEPACK_V0 });
  assert.equal(linked.counts.CROSS_REGISTRY_COREFERENCE_UNLINKED, v0.counts.CROSS_REGISTRY_COREFERENCE_UNLINKED - 1);
  for (const r of rulesOf(RULEPACK_V0)) if (r.id !== "CROSS_REGISTRY_COREFERENCE_UNLINKED") assert.equal(linked.counts[r.id], v0.counts[r.id], `${r.id} moved when an unrelated relation was added`);
});


/* ─────────────────────────── determinism and the acceptance test ─────────────────────────── */

test("two equivalent input orders give identical finding ids: shuffling the node, relation and source order changes nothing", () => {
  const ctx = ctxOf("tri");
  const shuffle = (xs, seed) => { const a = [...xs]; let s = seed; for (let i = a.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) >>> 0; const j = s % (i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const shuffled = runConsistency({
    ...ctx,
    nodes: shuffle(ctx.nodes, 7), relations: shuffle(ctx.relations, 11),
    snapshot: { ...ctx.snapshot, sources: shuffle(ctx.snapshot.sources, 13).map((s) => ({ ...s, files: shuffle(s.files, 17) })) },
    preserved: shuffle(ctx.preserved, 19),
  });
  assert.deepEqual(shuffled.findings.map((f) => f.lid), TRI.findings.map((f) => f.lid));
  assert.deepEqual(shuffled.counts, TRI.counts);
  assert.deepEqual(shuffled.findings, TRI.findings, "the whole finding set is byte-equal under a shuffle");
});

test("ACCEPTANCE (GPT v6 §F): changing a source pin CHANGES a consistency finding, while the old snapshot's result is preserved unchanged", () => {
  /* multi-v1 and tri commit to the same six sources; tri adds a SEVENTH declaration reading one of the same
     repositories at a different commit. That one change moves two rules and nothing else. */
  const a = MULTI_V1, b = TRI;
  assert.equal(a.counts.REFERENCE_TARGET_DRIFT, 0);
  assert.equal(b.counts.REFERENCE_TARGET_DRIFT, 1);
  assert.equal(a.counts.SOURCE_PIN_DIVERGENCE, 0);
  assert.equal(b.counts.SOURCE_PIN_DIVERGENCE, 1);
  /* the co-reference evidence moved to the LINKAGE layer (D-076): 0 links for multi-v1, 13 for tri, and neither
     rulepack-v1 run reports co-reference as a consistency problem at all. */
  assert.equal(a.counts.CROSS_REGISTRY_COREFERENCE_UNLINKED, undefined);
  assert.equal(b.counts.CROSS_REGISTRY_COREFERENCE_UNLINKED, undefined);
  assert.equal(runLinkage(ctxOf("multi-v1")).links.length, 0);
  assert.equal(runLinkage(ctxOf("tri")).links.length, 13);
  /* and the old snapshot's own result is untouched: re-running it now gives exactly what it gave before */
  assert.deepEqual(run("multi-v1").findings.map((f) => f.lid), a.findings.map((f) => f.lid));
  /* the two runs are about two different snapshots, and every finding says which */
  for (const f of a.findings) assert.match(f.snapshot, /multi-v1/);
  for (const f of b.findings) assert.match(f.snapshot, /^snapshot:g0:tri-/);
  assert.equal(new Set([...a.findings, ...b.findings].map((f) => f.snapshot)).size, 2);
});

test("a finding cannot mutate a registry: the consistency run writes nothing outside <dir>/consistency, and the emitted manifest declares zero authority", () => {
  const manifest = JSON.parse(readFileSync(join(DIR("tri"), "consistency", "manifest.json"), "utf8"));
  assert.deepEqual(manifest.scope, { authority: "none", basis: "derived", trvm_derivation: false, repairs_offered: 0, registry_written: false });
  assert.equal(manifest.rulepack, RULEPACK_ID);
  assert.equal(manifest.count, TRI.findings.length);
  assert.deepEqual(manifest.rejected.sort(), REJECTED.map((r) => r.id).sort());
  /* the consistency root is its OWN root and is not a member of the projection manifest */
  const proj = JSON.parse(readFileSync(join(DIR("tri"), "manifest.json"), "utf8"));
  const root = readFileSync(join(DIR("tri"), "consistency", "ROOT"), "utf8").trim();
  assert.match(root, /^root-[0-9a-f]{64}$/);
  assert.notEqual(root, readFileSync(join(DIR("tri"), "ROOT"), "utf8").trim());
  const entryLids = new Set(proj.entries.map(([lid]) => lid));
  for (const [lid] of manifest.entries) assert.ok(!entryLids.has(lid), `${lid} is a finding AND a projection entry — a derived finding must not enter the projection root`);
});

test("the preserved-receipt roots the rule reads are declared, and every one of them exists", () => {
  assert.ok(PRESERVED_ROOTS.includes("pre-trvm"));
  for (const r of PRESERVED_ROOTS) assert.ok(existsSync(join(V, "projections", r)), `projections/${r} is declared and missing`);
});
