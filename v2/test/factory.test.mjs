/* factory.test.mjs — G0-F: the invariant factory ledger as the SECOND authoritative source (D-054, D-056), measured on the
 * SHIPPED multi projection (`projections/multi`, snapshot `snapshot:g0:multi-ba4e625-d217ee2`) and on synthetic sources
 * through the real adapter for the refusal paths the pinned ledger happens not to exercise. Every number in a test name
 * is a measurement (R12 at d217ee2); the frozen baseline/historical roots (D-049) are re-checked here so the second
 * adapter is proven not to have moved the first source's projections. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { execFileSync } from "node:child_process";
import { ingestFactory, factoryFiles, sectionLine, parseWitness, attrValue, VOCABULARY } from "../adapters/factory.mjs";
import { project, verify } from "../lib/project.mjs";
import { relationLid, contextBoundLid } from "../lib/lid.mjs";
import { Emitter, encodeLocal } from "../lib/emit.mjs";
import { fakeRepo } from "./helpers/fake_repo.mjs";

const HERE = dirname(fileURLToPath(import.meta.url)); const V = resolve(HERE, "..");
const MULTI = resolve(V, "projections/multi"), BASE = resolve(V, "projections/baseline"), HIST = resolve(V, "projections/historical");
const FROZEN = { baseline: "root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85", historical: "root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87" };
const readLines = (dir, kind) => readFileSync(join(dir, `records/${kind}.jsonl`), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const index = (dir) => ({ nodes: new Map(readLines(dir, "node").map((n) => [n.lid, n])), rels: readLines(dir, "relation"), asrts: new Map(readLines(dir, "assertion").map((a) => [a.lid, a])), locs: new Map(readLines(dir, "source_location").map((l) => [l.lid, l])), faults: readLines(dir, "fault"), manifest: JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8")), snapshot: JSON.parse(readFileSync(join(dir, "snapshot.json"), "utf8")) });
const I = index(MULTI);
const registryOf = (a) => I.asrts.get(a).asserted_by.split(":")[1];
const registries = (rec) => [...new Set(rec.assertions.map(registryOf))].sort();
const asrtAttrs = (rel) => rel.assertions.map((a) => I.asrts.get(a)).map((a) => ({ location: a.location, asserted_by: a.asserted_by, ...(a.attrs || {}) }));
const codes = (faults) => { const c = {}; for (const f of faults) c[f.code] = (c[f.code] || 0) + 1; return c; };
const FACTORY_REGISTRY = "registry:factory:factory-ledger@INV-R9.4";
const FACTORY_SRC = I.snapshot.sources.find((s) => s.namespace === "factory");

test("pin: the multi snapshot names both adapters, pins the factory at d217ee29… (tree 11ab2c61…, CLAIM_LEDGER.json blob 23141cd1…) with every file the adapter reads (66 files: ledger, assumptions, sources, cells.json, 20 receipts, 45 witness paths), and the frozen baseline/historical roots are UNCHANGED beside it", () => {
  assert.deepEqual(I.snapshot.params.adapters, ["crosswalk", "factory"]); assert.equal(I.manifest.snapshot, "snapshot:g0:multi-ba4e625-d217ee2");
  assert.equal(FACTORY_SRC.commit, "d217ee29a3322c68db0d43be47491f0e9d4fbc64"); assert.equal(FACTORY_SRC.tree, "11ab2c6192ecf19fbf974da7b6483899903eca32");
  const ledger = FACTORY_SRC.files.find((f) => f.path === "CLAIM_LEDGER.json"); assert.equal(ledger.blob, "23141cd132059483c6b1f4aaeb4c241231c43cf9"); assert.equal(ledger.bytes, 458585);
  assert.equal(FACTORY_SRC.files.length, 66); assert.equal(FACTORY_SRC.files.filter((f) => f.path.startsWith("mosaic/receipts/")).length, 20);
  for (const p of ["mosaic/assumptions.json", "mosaic/sources.json", "opensentience.org/_invariants/data/cells.json", "scripts/emb-support.mjs", "mosaic/embodiment.json"]) assert.ok(FACTORY_SRC.files.some((f) => f.path === p), p);
  // the first source's projections did not move (D-049): ROOT files and CAS re-verification
  for (const [name, dir] of [["baseline", BASE], ["historical", HIST]]) { assert.equal(readFileSync(join(dir, "ROOT"), "utf8").trim(), FROZEN[name]); const v = verify(dir); assert.deepEqual(v.problems, []); assert.equal(v.root, FROZEN[name]); }
  assert.notEqual(readFileSync(join(MULTI, "ROOT"), "utf8").trim(), FROZEN.baseline);
  const runs = readLines(MULTI, "adapter_run"); assert.deepEqual(runs.map((r) => r.adapter.uri).sort(), ["file:adapters/crosswalk.mjs", "file:adapters/factory.mjs"]);
  assert.equal(readLines(BASE, "adapter_run").length, 1, "the baseline still ran one adapter");
});

test("scope is D-056 (1)–(7): one factory REGISTRY with the 8-status vocabulary and the settled policy; 208 CLAIM MEMBER_OF it, each with evidence_state {status, factory-ledger} and prose carried verbatim; 87 WITNESS nodes / 269 WITNESSES assertions (118 pass, 151 not-stated); ASSUMES 110 free-text + 52 typed; BINDS 54 to 7 cells; SUPERSEDES 14; CITES 45 SRC + 1 cites_bound; 20 RECEIPT + 21 ROUND with 20 + 106 PRODUCED_BY; NOTHING from the deferred layer", () => {
  const reg = I.nodes.get(FACTORY_REGISTRY); assert.ok(reg); assert.equal(reg.kind, "REGISTRY");
  assert.deepEqual(Object.keys(reg.attrs.statuses).sort(), ["CONDITIONAL", "DECLARED", "KNOWN", "MEASURED", "OPEN", "PROVED", "PROVISIONAL", "REFUTED"]);
  assert.deepEqual(reg.attrs.settled_policy.statuses, ["PROVED", "CONDITIONAL", "REFUTED", "KNOWN", "MEASURED"]); assert.equal(reg.attrs.round.id, "INV-R9.4"); assert.equal(reg.attrs.claims, 208);
  const fc = [...I.nodes.values()].filter((n) => n.lid.startsWith("claim:factory:"));
  assert.equal(fc.length, 208);
  for (const c of fc) { assert.equal(c.evidence_state.vocabulary, VOCABULARY); assert.ok(Object.keys(reg.attrs.statuses).includes(c.evidence_state.token), c.lid); assert.equal(typeof c.attrs.statement, "string"); assert.equal(typeof c.attrs.evidence, "string"); assert.equal(c.attrs.registry_hint, VOCABULARY); }
  assert.equal(I.rels.filter((r) => r.kind === "MEMBER_OF" && r.target === FACTORY_REGISTRY).length, 208);
  const st = {}; for (const c of fc) st[c.evidence_state.token] = (st[c.evidence_state.token] || 0) + 1;
  assert.deepEqual(st, { DECLARED: 71, PROVED: 52, OPEN: 46, REFUTED: 19, KNOWN: 7, PROVISIONAL: 7, CONDITIONAL: 3, MEASURED: 3 }, "R12 status census");
  // prose is verbatim: EMB-CUT-EMPTY's statement and its three assumptions are the source strings
  const e = I.nodes.get("claim:factory:EMB-CUT-EMPTY"); assert.ok(e.attrs.statement.startsWith("For every monotone capability-support function")); assert.equal(e.attrs.assumptions.length, 3); assert.equal(e.attrs.implementation_binding, "scripts/emb-battery-control.mjs — analyse(), against CAP-SYNTHETIC-IN-PRIORS and CAP-SYNTHETIC-AOBC"); assert.equal(e.attrs.binding_form, "path-with-prose");
  // witnesses
  const fw = [...I.nodes.values()].filter((n) => n.lid.startsWith("witness:factory:") && registries(n).includes("factory"));
  assert.equal(fw.length, 87); assert.equal(fw.filter((n) => n.attrs.section).length, 48); assert.equal(fw.filter((n) => n.attrs.line > 0).length, 48, "every §n resolved to a banner line");
  const wr = I.rels.filter((r) => r.kind === "WITNESSES" && r.source.startsWith("witness:factory:") && r.target.startsWith("claim:factory:"));
  assert.equal(wr.reduce((n, r) => n + r.assertions.length, 0), 269);
  const outcomes = {}; for (const r of wr) for (const o of asrtAttrs(r)) { const k = JSON.stringify(o.outcome); outcomes[k] = (outcomes[k] || 0) + 1; assert.equal(typeof o.raw_status, "string"); assert.equal(o.outcome_basis, "status"); }
  assert.deepEqual(outcomes, { '"pass"': 118, '{"unknown":"not-stated"}': 151 });
  for (const r of wr) for (const a of r.assertions) assert.ok(!("outcome" in r.attrs) && I.asrts.has(a), "outcome rides on the assertion");
  // LOCATED_IN: a sectioned witness sits at the banner LINE of the pinned blob; a bare one at the file
  const w = I.nodes.get("witness:factory:scripts/emb-support.mjs#1"); assert.ok(w); assert.equal(w.attrs.blob, "13e285d91adfe9aa1e649aca3197eacda09b6903");
  const li = I.rels.find((r) => r.kind === "LOCATED_IN" && r.source === w.lid); assert.equal(li.target, `loc:factory:13e285d91adfe9aa1e649aca3197eacda09b6903:scripts/emb-support.mjs#L${w.attrs.line}`); assert.equal(I.locs.get(li.target).precision, "line");
  const bare = I.rels.find((r) => r.kind === "LOCATED_IN" && r.source === "witness:factory:mosaic/embodiment.json"); assert.equal(I.locs.get(bare.target).precision, "file");
  // assumptions
  const asm = I.rels.filter((r) => r.kind === "ASSUMES" && r.source.startsWith("claim:factory:"));
  const free = asm.filter((r) => r.target.startsWith("assumption:text:")); assert.equal(free.reduce((n, r) => n + r.assertions.length, 0), 110, "110 free-text assumption occurrences (R12)"); assert.equal(free.length, 110, "each a distinct (claim, sentence) proposition at this pin");
  assert.equal(asm.filter((r) => r.target.startsWith("assumption:factory:")).length, 52); assert.equal([...I.nodes.keys()].filter((l) => l.startsWith("assumption:factory:")).length, 29);
  // binds / supersedes / cites
  const binds = I.rels.filter((r) => r.kind === "BINDS" && r.source.startsWith("claim:factory:")); assert.equal(binds.length, 54);
  assert.deepEqual([...new Set(binds.map((r) => r.target))].sort(), ["cell:cells:01", "cell:cells:24", "cell:cells:25", "cell:cells:27a", "cell:cells:27b", "cell:cells:36", "cell:cells:45"]);
  assert.equal(I.rels.filter((r) => r.kind === "SUPERSEDES").length, 14); assert.ok(I.rels.filter((r) => r.kind === "SUPERSEDES").every((r) => r.source.startsWith("claim:factory:") && r.target.startsWith("claim:factory:")), "claim → claim only; no ROUND SUPERSEDES ROUND was inferred from the parent chain");
  assert.equal(I.rels.filter((r) => r.kind === "CITES" && r.target.startsWith("artifact:factory:SRC-")).length, 45); assert.equal([...I.nodes.keys()].filter((l) => l.startsWith("artifact:factory:SRC-")).length, 24);
  const cb = I.rels.find((r) => r.kind === "CITES" && r.source === "claim:factory:FED-Q3-HYP-S4" && r.target === "claim:factory:FED-WITNESS-BOUND"); assert.equal(asrtAttrs(cb)[0].needs, "upper");
  // receipts and rounds
  assert.equal([...I.nodes.keys()].filter((l) => l.startsWith("receipt:factory:")).length, 20); assert.equal([...I.nodes.keys()].filter((l) => l.startsWith("round:factory:")).length, 21);
  assert.equal(I.rels.filter((r) => r.kind === "PRODUCED_BY" && r.source.startsWith("receipt:factory:")).length, 20); assert.equal(I.rels.filter((r) => r.kind === "PRODUCED_BY" && r.source.startsWith("claim:factory:") && r.target.startsWith("round:factory:")).length, 106);
  const r94 = I.nodes.get("receipt:factory:mosaic/receipts/INV-R9.4.json"); assert.equal(r94.attrs.receipt_version, "4", "the source spells the version as a string; it is carried as one"); assert.equal(r94.attrs.parent.commit_oid, "0cc11141f1668efdd0998e4502880af1a79507d4"); assert.equal(r94.attrs.invariants.after, 208);
  assert.ok(I.rels.some((r) => r.kind === "PRODUCED_BY" && r.source === "claim:factory:FAC-INTEGRATION-PORTABLE-REPLAY" && r.target === "round:factory:INV-R9.4"));
  // nothing from the deferred layer: no argument / defeater / instrument / objective / incident object, no FALSIFIER, no SUPPORTS/ATTACKS edge from the factory
  for (const l of I.nodes.keys()) assert.ok(!/factory:(ARG|DEF|INS|SO|EVAL|INC-R\d|CAP|OCC)-/.test(l), `deferred object ${l}`);
  assert.equal(I.rels.filter((r) => ["SUPPORTS", "ATTACKS", "FALSIFIES"].includes(r.kind)).length, 0);
  assert.equal(readLines(MULTI, "node").filter((n) => n.kind === "FALSIFIER").length, 0);
  // the kinds and pairs are all inside the frozen v0 declaration (D-050): every relation lid is the bare proposition
  for (const r of I.rels) assert.equal(r.lid, relationLid(r.kind, r.source, r.target));
});

test("(a) unique shared identity: the 4 factory ids the crosswalk cites are ONE claim:factory:* node each with assertions from BOTH registries, the fold raised no CONTRADICTION, and the node carries the crosswalk's stub attrs beside the ledger's record", () => {
  for (const id of ["EMB-AUTH-NONAMP", "EMB-CUT-EMPTY", "TAX-RELATIONAL-2", "TAX-FLOW"]) {
    const n = I.nodes.get(`claim:factory:${id}`); assert.ok(n, id);
    assert.deepEqual(registries(n), ["crosswalk", "factory"]); assert.equal(n.assertions.length, 2);
    assert.equal(n.attrs.present_in_pinned_ledger, true, "the crosswalk's stub attr survives"); assert.equal(n.attrs.claim_id, id); assert.equal(n.attrs.registry_hint, "factory-ledger");
    assert.equal(n.attrs.attr_conflicts, undefined); assert.equal(n.evidence_state.vocabulary, "factory-ledger");
    assert.equal([...I.nodes.keys()].filter((l) => l.endsWith(":" + id)).length, 1, `${id} is one node across every namespace`);
  }
  assert.equal(I.faults.filter((f) => f.code === "CONTRADICTION").length, 0); assert.equal(I.faults.filter((f) => f.code === "DUPLICATE_ID").length, 0);
  assert.deepEqual([...I.nodes.values()].filter((n) => registries(n).includes("factory") && registries(n).some((r) => r !== "factory")).map((n) => n.lid).sort(), ["cell:cells:27a", "claim:factory:EMB-AUTH-NONAMP", "claim:factory:EMB-CUT-EMPTY", "claim:factory:TAX-FLOW", "claim:factory:TAX-RELATIONAL-2"], "exactly the node-level folds R12 predicted");
});

test("(b) namespace collision: S4 is obligation:inv:S4 and the factory's 'S4' search-space label never becomes a node or an edge; likewise F1/F4/F5; the factory's INC- claims and its INC-R incidents never meet", () => {
  assert.ok(I.nodes.has("obligation:inv:S4")); assert.deepEqual([...I.nodes.keys()].filter((l) => /:(S4|F1|F4|F5)$/.test(l)), ["obligation:inv:S4"]);
  assert.ok(!I.nodes.has("claim:factory:S4") && !I.nodes.has("finding:factory:S4") && !I.nodes.has("finding:computedriven:S4"));
  assert.equal(I.rels.filter((r) => /factory:(S4|F1|F4|F5)(:|$)/.test(r.lid)).length, 0);
  assert.ok(I.nodes.has("claim:factory:FED-Q3-HYP-S4"), "the claim whose id ENDS in S4 is a different token");
  assert.ok([...I.nodes.keys()].filter((l) => /^claim:factory:INC-/.test(l)).length === 3 && ![...I.nodes.keys()].some((l) => /factory:INC-R\d/.test(l)));
  // the factory's statuses and the crosswalk's tokens are two vocabularies on evidence_state, never merged
  const vocab = {}; for (const n of I.nodes.values()) if (n.evidence_state) vocab[n.evidence_state.vocabulary] = (vocab[n.evidence_state.vocabulary] || 0) + 1;
  assert.deepEqual(vocab, { crosswalk: 56, "factory-ledger": 208 });
});

test("(c) same-looking claims stay distinct: E-40 (name == 'EMB-CUT-EMPTY') and claim:factory:EMB-CUT-EMPTY are two nodes joined only by the CITES the crosswalk states; E-41 and TAX-RELATIONAL-2 (a paraphrase) likewise — text equality is never identity", () => {
  const e40 = I.nodes.get("claim:crosswalk:E-40"); assert.equal(e40.attrs.name, "EMB-CUT-EMPTY"); assert.ok(I.nodes.has("claim:factory:EMB-CUT-EMPTY"));
  const between = (a, b) => I.rels.filter((r) => (r.source === a && r.target === b) || (r.source === b && r.target === a));
  const j = between("claim:crosswalk:E-40", "claim:factory:EMB-CUT-EMPTY"); assert.equal(j.length, 1); assert.equal(j[0].kind, "CITES"); assert.equal(j[0].source, "claim:crosswalk:E-40"); assert.deepEqual(registries(j[0]), ["crosswalk"]);
  const k = between("claim:crosswalk:E-41", "claim:factory:TAX-RELATIONAL-2"); assert.equal(k.length, 1); assert.equal(k[0].kind, "CITES");
  assert.ok(I.nodes.get("claim:factory:TAX-RELATIONAL-2").attrs.statement.startsWith("The strong reading of cell 27a is a 2-safety property")); assert.equal(I.nodes.get("claim:crosswalk:E-41").attrs.name, "cell 27a strong reading is 2-safety");
  assert.equal(I.rels.filter((r) => ["EQUIVALENT_TO", "SUPERSEDES"].includes(r.kind) && r.lid.includes("crosswalk:E-4")).length, 0, "no identity or replacement was inferred from wording");
});

test("(d) cross-source propositions: ZERO relations carry assertions from both a crosswalk-side registry and the factory at this pin (measured, as R12 found); the two-assertion mechanism is demonstrated intra-factory — 8 of the 14 SUPERSEDES propositions are stated from both sides, 45 of 52 typed ASSUMES by both assumption_refs and cited_by, 20 of 45 SRC CITES by two or three fields", () => {
  const both = I.rels.filter((r) => registries(r).includes("factory") && registries(r).some((x) => x !== "factory")); assert.deepEqual(both.map((r) => r.lid), []);
  const sup = I.rels.filter((r) => r.kind === "SUPERSEDES"); assert.equal(sup.length, 14);
  const two = sup.filter((r) => r.assertions.length === 2); assert.equal(two.length, 8);
  for (const r of two) { const o = asrtAttrs(r); assert.deepEqual(o.map((x) => x.stated_by).sort(), ["superseded_by", "supersedes"]); assert.equal(new Set(o.map((x) => x.location)).size, 2); assert.deepEqual(r.attrs, {}); }
  assert.ok(sup.some((r) => r.source === "claim:factory:SUPPORT-CHANNEL-COMPLETE" && r.target === "claim:factory:LINEAGE-COMPLETE" && r.assertions.length === 2));
  assert.equal(sup.filter((r) => r.target === "claim:factory:SUPPORT-CHANNEL-COMPLETE").length, 2, "a split supersession is two propositions");
  const one = sup.filter((r) => r.assertions.length === 1); assert.equal(one.length, 6); assert.deepEqual(one.map((r) => asrtAttrs(r)[0].stated_by).sort(), ["superseded_by", "superseded_by", "superseded_by", "superseded_by", "superseded_by", "supersedes"]);
  const asm = I.rels.filter((r) => r.kind === "ASSUMES" && r.target.startsWith("assumption:factory:")); assert.equal(asm.length, 52); assert.equal(asm.filter((r) => r.assertions.length === 2).length, 45);
  assert.equal(asm.filter((r) => asrtAttrs(r).every((o) => o.stated_by === "cited_by")).length, 6, "six cited_by statements the ledger does not reciprocate"); assert.equal(asm.filter((r) => asrtAttrs(r).every((o) => o.stated_by === "assumption_refs")).length, 1);
  const cit = I.rels.filter((r) => r.kind === "CITES" && r.target.startsWith("artifact:factory:SRC-")); assert.equal(cit.length, 45); assert.equal(cit.filter((r) => r.assertions.length >= 2).length, 20);
  assert.equal(cit.filter((r) => asrtAttrs(r).some((o) => o.stated_by === "prior_art")).reduce((n, r) => n + asrtAttrs(r).filter((o) => o.stated_by === "prior_art").length, 0), 26, "26 SRC mentions in prior_art resolve (R12)");
});

test("(e) free-text assumptions share the `text` namespace: 105 assumption:text:* nodes (97 factory, 8 crosswalk), ZERO shared verbatim at this pin — measured, and the co-reference is by construction: the factory mints through the same Emitter.lid rule", () => {
  const ta = [...I.nodes.values()].filter((n) => n.lid.startsWith("assumption:text:"));
  assert.equal(ta.length, 105); assert.equal(ta.filter((n) => registries(n).includes("factory")).length, 97); assert.equal(ta.filter((n) => registries(n).includes("crosswalk")).length, 8);
  assert.equal(ta.filter((n) => registries(n).length > 1).length, 0, "no sentence is shared verbatim between the two registries at this pin");
  const E = new Emitter({ snapshot: "snapshot:g0:x", registry: "registry:x:y", namespace: "x", pinned_identity: "0".repeat(40), path: "p" });
  for (const n of ta) { assert.equal(E.lid("ASSUMPTION", "text", n.attrs.text), n.lid, "the lid is a pure function of the sentence"); assert.equal(n.attrs.unnormalized, true); }
  assert.equal(ta.filter((n) => /:h\.[0-9a-f]{16}$/.test(n.lid)).length, 82, "long sentences hash (raw kept as text)");
});

test("(f) faults census: SETTLED_WITHOUT_WITNESS 8 (KNOWN 6 + REFUTED 2, the ids R12 lists), STATUS_OUTSIDE_VOCABULARY 0, DANGLING_CELL_BINDING 0, DANGLING_WITNESS 0 from the factory (the 2 are the crosswalk's), HEADING_WITHOUT_NUMBER 0, UNRESOLVED_LINK 14 from the factory (10 supersedes prose incl. 2 that mention an id, 1 superseded_by prose, 2 SRC-MUTATION-ADEQUACY, 1 receipt lineage prose), no UNQUALIFIED_REFERENCE/AMBIGUOUS_IDENTIFIER/SCHEMA_UNEXPECTED_FIELD from the factory; the baseline's 64 faults are all still there", () => {
  const f = I.faults.filter((x) => x.rule.startsWith("factory.")); const c = codes(f);
  assert.deepEqual(c, { SETTLED_WITHOUT_WITNESS: 8, UNRESOLVED_LINK: 14 });
  assert.deepEqual(f.filter((x) => x.code === "SETTLED_WITHOUT_WITNESS").map((x) => `${x.concerns[0].split(":").pop()}/${x.attrs.status}`).sort(), ["ASR-DEFEATER-ACTIVITY/KNOWN", "EMB-UNLEARN-VERIF/KNOWN", "FED-1PA-DEC/KNOWN", "FED-PAIRWISE/KNOWN", "LED-DP-COMP/REFUTED", "LED-FILTER-ODOMETER/REFUTED", "LINEAGE-AFFECTEDNESS/KNOWN", "MEDIATION-UNIVERSE-BOUND/KNOWN"]);
  const ul = {}; for (const x of f.filter((y) => y.code === "UNRESOLVED_LINK")) ul[x.rule] = (ul[x.rule] || 0) + 1;
  assert.deepEqual(ul, { "factory.claims.supersedes": 10, "factory.claims.superseded_by": 1, "factory.claims.citations": 2, "factory.receipts.lineage.supersedes": 1 });
  assert.ok(f.filter((x) => x.rule === "factory.claims.citations").every((x) => x.attrs.text === "SRC-MUTATION-ADEQUACY"));
  assert.ok(f.filter((x) => x.rule.startsWith("factory.claims.supersede")).every((x) => x.attrs.reason === "prose"), "prose is reported, never parsed (D-021) — including the two prose values that mention a resolvable id");
  for (const code of ["STATUS_OUTSIDE_VOCABULARY", "DANGLING_CELL_BINDING", "HEADING_WITHOUT_NUMBER", "DANGLING_SUPERSESSION", "SCHEMA_UNEXPECTED_FIELD", "CONTRADICTION", "BAD_LID"]) assert.equal(c[code], undefined, code);
  assert.equal(codes(I.faults.filter((x) => !x.rule.startsWith("factory."))).UNQUALIFIED_REFERENCE, 3); assert.equal(I.faults.filter((x) => x.code === "UNQUALIFIED_REFERENCE" && x.rule.startsWith("factory")).length, 0);
  const base = index(BASE); assert.equal(base.faults.length, 64); assert.deepEqual(codes(I.faults), { ...codes(base.faults), UNRESOLVED_LINK: codes(base.faults).UNRESOLVED_LINK + 14, SETTLED_WITHOUT_WITNESS: 8 });
  assert.equal(I.manifest.faults.count, 86);
});

test("witness parity across adapters: the crosswalk's bare witness:factory:scripts/emb-support.mjs and the factory's #1/#2/#3 witnesses of the same file are distinct lids over the same blob, their LOCATED_IN targets differ (file vs line) and share the pinned identity, and the factory-tree locations carry the TREE registry (a function of where the file is, not of who cited it)", () => {
  const bare = I.nodes.get("witness:factory:scripts/emb-support.mjs"); assert.deepEqual(registries(bare), ["crosswalk", "evstate"]);
  const sec = ["1", "2", "3"].map((s) => I.nodes.get(`witness:factory:scripts/emb-support.mjs#${s}`)); for (const w of sec) { assert.deepEqual(registries(w), ["factory"]); assert.equal(w.attrs.blob, bare.attrs.blob); assert.equal(w.attrs.kind, bare.attrs.kind); assert.equal(w.attrs.commit, bare.attrs.commit); }
  const locsOf = (lid) => I.rels.filter((r) => r.kind === "LOCATED_IN" && r.source === lid).map((r) => I.locs.get(r.target));
  assert.equal(locsOf(bare.lid)[0].precision, "file"); for (const w of sec) { const [l] = locsOf(w.lid); assert.equal(l.precision, "line"); assert.equal(l.pinned_identity, bare.attrs.blob); assert.equal(l.registry, "registry:factory:invariant-factory@d217ee29a332"); }
  for (const l of I.locs.values()) if (l.lid.startsWith("loc:factory:")) assert.equal(l.registry, "registry:factory:invariant-factory@d217ee29a332");
  assert.equal(I.rels.filter((r) => r.kind === "WITNESSES" && r.source.startsWith("witness:factory:") && registries(r).includes("factory") && registries(r).length > 1).length, 0, "no witness proposition is shared with the factory: the lids do not overlap (R12 §4e)");
});

test("section resolver: a §n anchor resolves to the first SECTION BANNER line, not to a mid-sentence mention; every one of the 48 (path, §) pairs at the pin resolved; the two `*   §1  …` banners of check-irreversible-ledger.mjs resolve as banners", () => {
  assert.equal(sectionLine("// ═══ §1 · monotone ═══\nx\n// ═══ §2 · next ═══\n", "2"), 3);
  assert.equal(sectionLine(" * Three sections, and §2 is the one\n// ═══ §2 · here\n", "2"), 2, "the mention on line 1 is skipped");
  assert.equal(sectionLine("*   §1  the WITNESS reproduces\n", "1"), 1); assert.equal(sectionLine("// §4b · x\n// §4 · y\n", "4"), 2); assert.equal(sectionLine("// §4b · x\n", "4b"), 1); assert.equal(sectionLine("nothing\n", "9"), null);
  assert.deepEqual(parseWitness("scripts/x.mjs §4b"), { path: "scripts/x.mjs", section: "4b", raw: "scripts/x.mjs §4b" }); assert.deepEqual(parseWitness("mosaic/embodiment.json"), { path: "mosaic/embodiment.json", section: null, raw: "mosaic/embodiment.json" }); assert.equal(parseWitness("a b c"), null);
  const secWitnesses = [...I.nodes.values()].filter((n) => n.lid.startsWith("witness:factory:") && n.attrs.section); assert.equal(secWitnesses.length, 48); assert.ok(secWitnesses.every((n) => Number.isInteger(n.attrs.line) && n.attrs.line > 0));
  assert.ok(I.nodes.get("witness:factory:scripts/check-irreversible-ledger.mjs#1").attrs.line > 0);
  assert.equal(I.faults.filter((f) => f.code === "HEADING_WITHOUT_NUMBER" && f.rule.startsWith("factory")).length, 0);
});

test("attrValue: source objects keep their keys; a key outside the attrs grammar is re-encoded as keyed_entries in source order (the four local_bindings objects at the pin), decimal strings and nested lists pass through", () => {
  assert.deepEqual(attrValue({ a: 1, b: [true, null, "x"], c: { decimal_string: "1.5" } }), { a: 1, b: [true, null, "x"], c: { decimal_string: "1.5" } });
  assert.deepEqual(attrValue({ "join tree": "the union hypergraph" }), { keyed_entries: [{ key: "join tree", value: "the union hypergraph" }] });
  const fs = I.nodes.get("claim:factory:FED-SEP-PROTOCOL"); assert.ok(fs.attrs.evidence_qualifiers.applicability.local_bindings.keyed_entries.some((e) => e.key === "join tree"));
  const rekeyed = [...I.nodes.values()].filter((n) => n.lid.startsWith("claim:factory:") && JSON.stringify(n.attrs).includes('"keyed_entries"'));
  assert.deepEqual(rekeyed.map((n) => n.lid.split(":").pop()).sort(), ["EMB-UNLEARN-VERIF", "FED-SEP-PROTOCOL", "LINEAGE-AFFECTEDNESS"]); const entries = rekeyed.flatMap((c) => c.attrs.evidence_qualifiers.applicability.local_bindings.keyed_entries); assert.equal(entries.length, 5); assert.equal(entries.filter((e) => /\s/.test(e.key)).length, 4, "the four phrase keys R12 could not spell, plus the one grammatical key that shared an object with them (an object is re-keyed whole)");
});

test("synthetic refusal paths through the real adapter: STATUS_OUTSIDE_VOCABULARY, SETTLED_WITHOUT_WITNESS, DANGLING_CELL_BINDING, DANGLING_WITNESS, HEADING_WITHOUT_NUMBER (a § with no banner → a heading-precision location), DANGLING_SUPERSESSION, UNRESOLVED_LINK (prose supersedes, absent ASM/SRC), SCHEMA_UNEXPECTED_FIELD; and a status outside the settled policy yields outcome not-stated", () => {
  const ledger = { _statuses: { PROVED: "p", OPEN: "o" }, _settled: { statuses: ["PROVED"] }, _round: { id: "INV-T1", date: "2026-01-01", receipt_ref: "mosaic/receipts/INV-T1.json" }, _registries: {}, _revisions: {}, claims: [
    { claim_id: "A-ONE", statement: "s", status: "PROVED", evidence: "e", last_verified: "d", assumptions: ["free text"], witnesses: ["w/a.mjs §1", "w/a.mjs §7", "w/missing.mjs", "bad form here"], prior_art: "see SRC-GONE-1 and SRC-OK-1", implementation_binding: "cell:99", assumption_refs: ["ASM-OK", "ASM-GONE"], supersedes: ["A-TWO", "NOPE-ID", "prose about A-TWO"], obligation: "existence" },
    { claim_id: "A-TWO", statement: "s", status: "WEIRD", evidence: "e", last_verified: "d", assumptions: [], witnesses: ["w/a.mjs"], prior_art: null, implementation_binding: "cell:01", superseded_by: "A-ONE", extra_field: 1 },
    { claim_id: "A-THREE", statement: "s", status: "PROVED", evidence: "e", last_verified: "d", assumptions: [], witnesses: [], prior_art: null, implementation_binding: null },
  ] };
  const repo = fakeRepo("invariant-factory", { "CLAIM_LEDGER.json": ledger, "mosaic/assumptions.json": { assumptions: [{ id: "ASM-OK", kind: "theorem", statement: "x", cited_by: ["A-ONE", "A-NOPE"] }] }, "mosaic/sources.json": { sources: [{ id: "SRC-OK-1", citation: "c", used_by: ["A-TWO", "A-NOPE"] }] },
    "opensentience.org/_invariants/data/cells.json": { cells: [{ num: "01" }] }, "mosaic/receipts/INV-T1.json": { receipt_version: 4, transition: { id: "INV-T0 -> INV-T1", from: "INV-T0", to: "INV-T1", parents: ["INV-T0"], operation: "op" }, invariants: { before: 2, after: 3, established: ["A-THREE", "A-GONE"] }, lineage: { supersedes: "prose" } }, "w/a.mjs": "// ═══ §1 · one\nmentions §7 here\n" });
  assert.deepEqual(factoryFiles(repo), ["CLAIM_LEDGER.json", "mosaic/assumptions.json", "mosaic/receipts/INV-T1.json", "mosaic/sources.json", "opensentience.org/_invariants/data/cells.json", "w/a.mjs"]);
  const out = ingestFactory({ snapshot: "snapshot:g0:synthetic", repos: { factory: repo }, treeRegistries: { factory: "registry:factory:t@0" } }).factory;
  const c = codes(out.faults);
  assert.deepEqual(c, { STATUS_OUTSIDE_VOCABULARY: 1, SETTLED_WITHOUT_WITNESS: 1, DANGLING_CELL_BINDING: 1, DANGLING_WITNESS: 1, HEADING_WITHOUT_NUMBER: 1, UNSUPPORTED_SOURCE_FORM: 1, DANGLING_SUPERSESSION: 1, UNRESOLVED_LINK: 7, SCHEMA_UNEXPECTED_FIELD: 1 });
  assert.equal(out.faults.find((f) => f.code === "STATUS_OUTSIDE_VOCABULARY").attrs.text, "WEIRD"); assert.equal(out.faults.find((f) => f.code === "SETTLED_WITHOUT_WITNESS").concerns[0], "claim:factory:A-THREE");
  assert.deepEqual(out.faults.filter((f) => f.code === "UNRESOLVED_LINK").map((f) => f.rule).sort(), ["factory.assumptions.cited_by", "factory.claims.assumption_refs", "factory.claims.citations", "factory.claims.supersedes", "factory.receipts.established", "factory.receipts.lineage.supersedes", "factory.sources.used_by"]);
  // the § with no banner: a heading-precision location carrying the raw §7, no line
  const w7 = out.nodes.find((n) => n.lid === "witness:factory:w/a.mjs#7"); assert.equal(w7.attrs.section, "7"); assert.equal(w7.attrs.line, undefined);
  const l7 = out.relations.find((r) => r.kind === "LOCATED_IN" && r.source === w7.lid); assert.ok(l7.target.endsWith("#" + encodeLocal("§7"))); assert.equal(out.locations.find((l) => l.lid === l7.target).precision, "heading");
  const w1 = out.nodes.find((n) => n.lid === "witness:factory:w/a.mjs#1"); assert.equal(w1.attrs.line, 1);
  // supersedes: the exact id → one relation (also stated by A-TWO.superseded_by → two assertions); the absent id dangles; the prose is reported
  const sup = out.relations.filter((r) => r.kind === "SUPERSEDES"); assert.equal(new Set(sup.map((r) => r.lid)).size, 1); assert.equal(sup.length, 2); assert.deepEqual(sup.map((r) => r.assertion.attrs.stated_by).sort(), ["superseded_by", "supersedes"]);
  assert.equal(out.faults.find((f) => f.code === "DANGLING_SUPERSESSION").attrs.text, "NOPE-ID");
  // binds: cell:01 binds, cell:99 dangles with no edge and no node
  assert.ok(out.relations.some((r) => r.kind === "BINDS" && r.target === "cell:cells:01")); assert.ok(!out.nodes.some((n) => n.lid === "cell:cells:99"));
  // outcomes: PROVED → pass; a status outside the settled policy → not-stated; the raw status is kept either way
  const wit = out.relations.filter((r) => r.kind === "WITNESSES"); assert.deepEqual(wit.map((r) => [r.target.split(":").pop(), JSON.stringify(r.assertion.attrs.outcome), r.assertion.attrs.raw_status]).sort(), [["A-ONE", '"pass"', "PROVED"], ["A-ONE", '"pass"', "PROVED"], ["A-TWO", '{"unknown":"not-stated"}', "WEIRD"]]);
  assert.equal(wit.find((r) => r.target.endsWith("A-ONE")).assertion.attrs.obligation, "existence");
  // the ASM node comes from the mosaic file, the CITES from prior_art resolves only the id the sources file has, the receipt binds established → PRODUCED_BY
  assert.ok(out.nodes.some((n) => n.lid === "assumption:factory:ASM-OK" && n.attrs.kind === "theorem")); assert.ok(out.relations.some((r) => r.kind === "CITES" && r.source === "claim:factory:A-ONE" && r.target === "artifact:factory:SRC-OK-1"));
  assert.ok(out.relations.some((r) => r.kind === "PRODUCED_BY" && r.source === "claim:factory:A-THREE" && r.target === "round:factory:INV-T1")); assert.ok(out.relations.some((r) => r.kind === "PRODUCED_BY" && r.source === "receipt:factory:mosaic/receipts/INV-T1.json"));
  assert.equal(out.relations.filter((r) => r.kind === "SUPERSEDES" && r.source.startsWith("round:")).length, 0, "lineage.supersedes prose never becomes a ROUND SUPERSEDES ROUND");
  assert.equal(out.nodes.find((n) => n.lid === "claim:factory:A-TWO").assertion.attrs.evidence_state.token, "WEIRD", "the raw vocabulary rides on the assertion even when outside _statuses");
});

test("A8 for the multi projection (needs the real tree; skipped from the zip): plain, reversed adapters, and two seeded shuffles give the shipped root and byte-identical records; the Python twin recomputes the root; g0 verify resolves every entry", (t) => {
  const tmp = mkdtempSync(join(tmpdir(), "g0-multi-")); process.on("exit", () => rmSync(tmp, { recursive: true, force: true }));
  const snap = resolve(V, "snapshots/multi.json"); const dirs = { a: join(tmp, "a"), b: join(tmp, "b"), c: join(tmp, "c"), d: join(tmp, "d") }; let ra;
  try { ra = project(snap, { out: dirs.a }); } catch (e) { t.skip("the pinned registries are not reachable here: " + e.message); return; }
  const rb = project(snap, { out: dirs.b, shuffleSeed: 7, reverseAdapters: true }), rc = project(snap, { out: dirs.c, shuffleSeed: 987654321 }), rd = project(snap, { out: dirs.d, reverseAdapters: true });
  const shipped = readFileSync(join(MULTI, "ROOT"), "utf8").trim(); assert.equal(ra.root, shipped, "the rebuild reproduces the shipped multi root");
  for (const r of [rb, rc, rd]) assert.equal(r.root, ra.root);
  const files = ["manifest.json", "records_index.json", "snapshot.json", "records/node.jsonl", "records/relation.jsonl", "records/assertion.jsonl", "records/source_location.jsonl", "records/fault.jsonl", "records/adapter_run.jsonl"];
  for (const f of files) for (const [k, label] of [["b", "shuffle+reverse"], ["c", "second seed"], ["d", "reverse only"]]) assert.ok(readFileSync(join(dirs.a, f)).equals(readFileSync(join(dirs[k], f))), `${f} differs under ${label}`);
  for (const f of files) assert.ok(readFileSync(join(dirs.a, f)).equals(readFileSync(join(MULTI, f))), `${f} differs from the shipped projection`);
  const runs = readLines(dirs.d, "adapter_run"); assert.deepEqual(runs.map((r) => [r.adapter.uri, r.params.order_index]).sort(), [["file:adapters/crosswalk.mjs", 0], ["file:adapters/factory.mjs", 1]], "order_index is the DECLARED position (data), so a reversed run order leaves the record — and the root — unchanged");
  assert.equal(JSON.parse(readFileSync(join(dirs.d, "witness.json"), "utf8")).reverse_adapters, true, "the run order is a witness, outside the digest");
  const v = verify(dirs.a); assert.deepEqual(v.problems, []); assert.equal(v.checked, v.entries); assert.equal(v.entries, 7639);
  const twin = JSON.parse(execFileSync("python3", [resolve(HERE, "canon_twin.py"), "--manifest", dirs.a]).toString("utf8")); assert.deepEqual(twin.problems, []); assert.equal(twin.root_twin, ra.root);
  // the baseline snapshot still reconstructs to the frozen root under the two-adapter projector
  const base = project(resolve(V, "snapshots/baseline.json"), { out: join(tmp, "base") }); assert.equal(base.root, FROZEN.baseline); assert.equal(readLines(join(tmp, "base"), "adapter_run").length, 1);
});
