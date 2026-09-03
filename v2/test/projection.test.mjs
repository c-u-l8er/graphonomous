/* projection.test.mjs — the G0-B / G0-B.1 projection gates over the REAL pinned registries (git required).
 * A1–A7 here are record-level checks of what the adapter observed; their executable QUERY form lives in
 * test/query.test.mjs (G0-E). B1-1…B1-10 are the GPT Adjudication v2 acceptance gates for identity normalization. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, mkdtempSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { project, verify } from "../lib/project.mjs";
import { relationLid } from "../lib/lid.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const V = resolve(HERE, "..");
const BASE = resolve(V, "snapshots/baseline.json");
const HIST = resolve(V, "snapshots/historical.json");
const TWIN = resolve(HERE, "canon_twin.py");
const readLines = (dir, kind) => readFileSync(join(dir, `records/${kind}.jsonl`), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const files = ["manifest.json", "records_index.json", "snapshot.json", "records/node.jsonl", "records/relation.jsonl", "records/assertion.jsonl", "records/source_location.jsonl", "records/fault.jsonl", "records/adapter_run.jsonl"];
const PRE_B1 = { baseline: "root-d1dd775671c2ad5bf8ffd788c8d2723edc7f73be2a3941528796f8ec78516131", historical: "root-5051394e34e92b8b27ad5b6ad306d9bb5f26fd9819ee5dd4ae7c1ce1bacbc6a4" };
/** D-037: the roots built BEFORE the D-034 ruling (transition→claim SUPERSEDES), preserved under projections/pre-d034/. */
const PRE_D034 = { baseline: "root-0eea954b5fb07e8a29e88f808c0902abe8fce90b9b04b68864297986769579e3", historical: "root-2424d836f0742f39ff4089d50cd07341deb9ad2c625347a64e2e815e77b84b3c" };

const tmp = mkdtempSync(join(tmpdir(), "g0-projection-"));
const A = join(tmp, "a"), B = join(tmp, "b"), C = join(tmp, "c"), D = join(tmp, "d"), H = join(tmp, "h");
const ra = project(BASE, { out: A });
const rb = project(BASE, { out: B, shuffleSeed: 7, reverseAdapters: true });
const rc = project(BASE, { out: C, shuffleSeed: 987654321 });
const rd = project(BASE, { out: D, reverseAdapters: true });
const rh = project(HIST, { out: H });
process.on("exit", () => rmSync(tmp, { recursive: true, force: true }));
const index = (dir) => ({ nodes: new Map(readLines(dir, "node").map((n) => [n.lid, n])), rels: readLines(dir, "relation"), asrts: new Map(readLines(dir, "assertion").map((a) => [a.lid, a])), locs: new Map(readLines(dir, "source_location").map((l) => [l.lid, l])), faults: readLines(dir, "fault") });
const IA = index(A), IH = index(H);
const asrtAttrs = (I, rel) => rel.assertions.map((a) => I.asrts.get(a)).map((a) => ({ location: a.location.split("#")[1] || "", asserted_by: a.asserted_by, ...(a.attrs || {}) }));

test("A8 / B1-8 reconstruction: plain, reversed adapters, and two seeded shuffles give the identical root and byte-identical records", () => {
  for (const r of [rb, rc, rd]) assert.equal(ra.root, r.root);
  assert.match(ra.root, /^root-[0-9a-f]{64}$/);
  for (const f of files) for (const [dir, label] of [[B, "shuffle+reverse"], [C, "second seed"], [D, "reverse only"]]) assert.ok(readFileSync(join(A, f)).equals(readFileSync(join(dir, f))), `${f} differs under ${label}`);
  assert.equal(readFileSync(join(A, "ROOT"), "utf8"), readFileSync(join(D, "ROOT"), "utf8"));
});

test("B1-9 / CAS: every record and the manifest resolve through the TRVM CAS; the Python twin recomputes the same root for both snapshots", () => {
  for (const [dir, r] of [[A, ra], [H, rh]]) {
    const v = verify(dir); assert.deepEqual(v.problems, []); assert.equal(v.checked, v.entries); assert.equal(v.root, r.root);
    const out = JSON.parse(execFileSync("python3", [TWIN, "--manifest", dir]).toString("utf8"));
    assert.deepEqual(out.problems, []); assert.equal(out.root_twin, r.root); assert.equal(out.checked, v.entries);
  }
});

test("B1-7: the pre-B.1 projections are preserved as receipts with their original roots, still CAS-verifiable, and superseded by different roots", () => {
  for (const [name, root] of Object.entries(PRE_B1)) {
    const dir = resolve(V, "projections/pre-b1", name);
    assert.equal(readFileSync(join(dir, "ROOT"), "utf8").trim(), root, `${name} pre-B.1 root unchanged`);
    const v = verify(dir); assert.deepEqual(v.problems, []); assert.equal(v.root, root);
  }
  assert.notEqual(ra.root, PRE_B1.baseline); assert.notEqual(rh.root, PRE_B1.historical);
  const evidence = readFileSync(resolve(V, "projections/pre-b1/EVIDENCE.md"), "utf8");
  assert.ok(evidence.includes(PRE_B1.baseline) && evidence.includes(PRE_B1.historical), "the pre-B.1 evidence document names both roots");
});

test("D-037: the pre-D-034 projections (transition→claim SUPERSEDES) are preserved as receipts with their original roots, still CAS-verifiable, and superseded by different roots", () => {
  for (const [name, root] of Object.entries(PRE_D034)) {
    const dir = resolve(V, "projections/pre-d034", name);
    assert.equal(readFileSync(join(dir, "ROOT"), "utf8").trim(), root, `${name} pre-D-034 root unchanged`);
    const v = verify(dir); assert.deepEqual(v.problems, []); assert.equal(v.root, root);
    const rels = readLines(dir, "relation"); assert.equal(rels.filter((r) => r.kind === "SUPERSEDES").length, 14, "the preserved receipt still says what it said"); assert.equal(rels.filter((r) => r.kind === "STATE_TRANSITION_OF").length, 0);
  }
  assert.notEqual(ra.root, PRE_D034.baseline); assert.notEqual(rh.root, PRE_D034.historical);
  const evidence = readFileSync(resolve(V, "projections/pre-d034/EVIDENCE.md"), "utf8");
  assert.ok(evidence.includes(PRE_D034.baseline) && evidence.includes(PRE_D034.historical) && /superseded by D-037/i.test(evidence), "the pre-D-034 evidence document names both roots and says they are superseded by D-037");
});

test("read-only gate: the git adapter issues only read commands, no adapter imports a writer, and nothing run-dependent enters the digest", () => {
  const git = readFileSync(resolve(V, "adapters/git.mjs"), "utf8");
  const calls = [...git.matchAll(/git(?:Text)?\(dir, \[("[^"]+")/g)].map((m) => JSON.parse(m[1]));
  assert.ok(calls.length >= 4, "the git adapter's commands are visible to this gate");
  for (const c of calls) assert.ok(["rev-parse", "ls-tree", "show", "branch"].includes(c), `git ${c} is not a read command`);
  for (const f of readdirSync(resolve(V, "adapters"))) { const src = readFileSync(resolve(V, "adapters", f), "utf8"); assert.ok(!/writeFileSync|appendFileSync|mkdirSync|rmSync|renameSync|from "node:fs"|from 'node:fs'/.test(src), `${f} must not write`); }
  const witness = JSON.parse(readFileSync(join(A, "witness.json"), "utf8"));
  assert.ok(witness.started_at && witness.host, "witness fields exist outside the digest");
  const manifest = JSON.parse(readFileSync(join(A, "manifest.json"), "utf8"));
  assert.equal(JSON.stringify(manifest).includes(witness.host), false, "the host name never enters the manifest");
  assert.equal(manifest.kind, "graphonomous.projection"); assert.equal(manifest.count, manifest.entries.length);
  assert.match(manifest.ruleset, /^g0rule-[0-9a-f]{64}$/);
  const run = readLines(A, "adapter_run")[0]; assert.equal(run.started_at, undefined); assert.equal(run.host, undefined);
});

test("B1-10 authority gate: everything observed, no `sem-`, no TRVM derivation claim, no registry writeback path", () => {
  for (const dir of [A, H]) {
    for (const n of readLines(dir, "node")) assert.equal(n.basis, "observed", n.lid);
    for (const r of readLines(dir, "relation")) assert.equal(r.basis, "observed", r.lid);
    for (const f of files) { const text = readFileSync(join(dir, f), "utf8"); assert.ok(!/"sem-[0-9a-f]{8}/.test(text), `${f} mints no sem-`); assert.ok(!/"trvm_derivation":\s*true/.test(text), `${f} claims no TRVM derivation`); }
  }
});

test("B1-1 / B1-2: two citations of one (kind, source, target) are one relation with two assertions whose role, what and location stay distinguishable", () => {
  const R085 = "receipt:sha256:6ba8544cbf7c91ef526ddde97943d54845e1f352814173b8fa9a64f86867a913";
  const e14 = IA.rels.filter((x) => x.kind === "WITNESSES" && x.source === R085 && x.target === "claim:crosswalk:E-14");
  assert.equal(e14.length, 1, "ONE relation: the R0.8.5 handback witnesses E-14");
  const occ = asrtAttrs(IA, e14[0]);
  assert.deepEqual(occ.map((o) => o.role).sort(), ["repair", "sensitivity"]);
  assert.deepEqual(occ.map((o) => o.location).sort(), ["/promotions/1/repair_witness", "/promotions/1/sensitivity_witness"]);
  assert.deepEqual(occ.map((o) => o.sensitivity_type).sort(), ["pre-fix-fail", "repair"]);
  assert.ok(occ.every((o) => typeof o.what === "string" && o.executed === true));
  assert.deepEqual(e14[0].attrs, {}, "the relation record carries only the proposition");
  assert.ok(!e14[0].lid.includes("loc:"), "no citation location in the relation lid");
  // E-50b names EXP-6 twice (run 1 and C1): one PRODUCED_BY, two assertions with their parts
  const p = IA.rels.filter((x) => x.kind === "PRODUCED_BY" && x.source === "claim:crosswalk:E-50b" && x.target === "experiment:r10:EXP-6");
  assert.equal(p.length, 1); assert.deepEqual(asrtAttrs(IA, p[0]).map((o) => o.part).sort(), ["C1", "run 1"]);
  // E-13b's R0.8.6 handback: pre-fix, repair and sensitivity in one relation
  const R086 = "receipt:sha256:cffc0218fc450884ad2bf4d1630468c675b262e8260ef72b8c90dbf061016303";
  const e13b = IA.rels.filter((x) => x.kind === "WITNESSES" && x.source === R086 && x.target === "claim:crosswalk:E-13b");
  assert.equal(e13b.length, 1); assert.deepEqual(asrtAttrs(IA, e13b[0]).map((o) => o.role).sort(), ["pre-fix", "repair", "sensitivity"]);
  // no relation lid of any kind embeds a location; no relation carries an occurrence attribute
  const occurrenceKeys = ["role", "what", "part", "outcome", "note", "source_id", "cited_as", "section", "listed_as", "mention", "text", "executed", "sensitivity_type", "type", "declared", "disposition", "as_of", "asserted_by_record", "raw_token"];
  for (const r of IA.rels) { assert.equal(r.lid, relationLid(r.kind, r.source, r.target), "the lid IS the proposition: no qualifier, no location suffix"); assert.equal(r.qualifier, undefined); for (const k of occurrenceKeys) assert.ok(!(k in r.attrs), `${r.lid} carries occurrence attribute ${k}`); }
  const multi = IA.rels.filter((r) => r.assertions.length > 1).length;
  assert.ok(multi >= 150, `many propositions have several assertions after folding (${multi})`);
});

test("B1-3 query preservation: the relation and assertion counts fold as predicted and nothing A1–A8 needs was lost", () => {
  const kinds = {}; for (const r of IA.rels) kinds[r.kind] = (kinds[r.kind] || 0) + 1;
  assert.equal(IA.asrts.size, 1272, "assertions are unchanged by folding (pre-B.1 baseline had 1,272)");
  assert.equal(IA.rels.length, 588, "786 per-citation relations fold to 588 propositions at the baseline");
  assert.equal(kinds.WITNESSES, 105); assert.equal(kinds.LOCATED_IN, 137); assert.equal(kinds.PRODUCED_BY, 20); assert.equal(kinds.ADJUDICATED_BY, 20); assert.equal(kinds.CITES, 26);
  for (const k of ["OPENS", "CLOSES", "STATES", "IMPLEMENTS", "DERIVES_FROM", "REDUCES_TO", "STATE_TRANSITION_OF", "MEMBER_OF", "SCOPED_BY", "TESTED_UNDER", "ASSUMES", "SPLIT_FROM", "BINDS", "DEFINES", "REPRESENTS", "CROSS_CUTS"]) assert.ok(kinds[k] >= 1, k);
  assert.equal(kinds.STATE_TRANSITION_OF, 14, "D-037: the 14 transitions each MOVE THE STATE OF their claim"); assert.equal(kinds.SUPERSEDES, undefined, "D-037: no SUPERSEDES is inferred from the transition chain");
  for (const r of IA.rels) if (r.kind === "STATE_TRANSITION_OF") { assert.ok(r.source.startsWith("transition:") && r.target.startsWith("claim:")); assert.ok(!("record" in r.attrs)); }
  // every relation assertion still points at a location with a precision
  for (const r of IA.rels) for (const a of r.assertions) { const as = IA.asrts.get(a); assert.ok(as && IA.locs.has(as.location), a); }
});

test("B1-4 / B1-5 on real data: the unnamed R0.8 finding is context-bound, asserted by both registries, and keeps its raw sentence", () => {
  const opens = IA.rels.filter((x) => x.kind === "OPENS" && x.source === "round:computedriven:R0.8");
  assert.equal(opens.length, 1);
  const f = IA.nodes.get(opens[0].target);
  assert.match(f.lid, /^finding:inv:h\.[0-9a-f]{16}$/); assert.equal(f.attrs.unnamed, true); assert.equal(f.attrs.container, "round:computedriven:R0.8");
  assert.ok(f.attrs.text.startsWith("NC29/NC30 executed"));
  assert.deepEqual(asrtAttrs(IA, opens[0]).map((o) => o.asserted_by.split(":")[1]).sort(), ["crosswalk", "evstate"]);
  assert.notEqual(f.lid, "finding:inv:h." + require_sha(f.attrs.text), "the identity is NOT the hash of the sentence alone");
});
function require_sha(text) { return execFileSync("python3", ["-c", "import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])"], { input: text }).toString().trim(); }

test("B1-6 on real data: the three bare factory ids resolve with a recorded basis and raise UNQUALIFIED_REFERENCE; the raw token is preserved", () => {
  const bare = IA.rels.filter((x) => x.kind === "CITES" && x.target.startsWith("claim:factory:") && asrtAttrs(IA, x).some((o) => o.qualified === false));
  assert.deepEqual(bare.map((x) => x.target).sort(), ["claim:factory:EMB-CUT-EMPTY", "claim:factory:TAX-FLOW", "claim:factory:TAX-RELATIONAL-2"]);
  for (const x of bare) { const o = asrtAttrs(IA, x)[0]; assert.equal(o.resolution_basis, "unique-pinned-match"); assert.equal(o.raw_token, x.target.split(":").pop()); assert.match(o.resolved_in, /^invariant-factory@d217ee29/); }
  const unq = IA.faults.filter((f) => f.code === "UNQUALIFIED_REFERENCE");
  assert.equal(unq.length, 3); assert.deepEqual(unq.map((f) => f.attrs.text).sort(), ["EMB-CUT-EMPTY", "TAX-FLOW", "TAX-RELATIONAL-2"]);
  assert.ok(unq.every((f) => f.concerns.length === 2 && f.attrs.resolution_basis === "unique-pinned-match"));
  // the qualified `claim-ledger:` form raises no such fault
  const qualified = IA.rels.filter((x) => x.kind === "CITES" && x.target.startsWith("claim:factory:") && asrtAttrs(IA, x).some((o) => o.qualified === true));
  assert.ok(qualified.length >= 1);
});

test("A1: S6? reduces to S1 by an observed relation whose assertion points at the crosswalk's resolved_candidates", () => {
  const r = IA.rels.find((x) => x.kind === "REDUCES_TO" && x.source === "obligation:inv:S6%3F" && x.target === "obligation:inv:S1");
  assert.ok(r, "REDUCES_TO S6? → S1 exists"); assert.equal(r.basis, "observed");
  assert.ok(r.assertions.some((a) => a.includes("#/resolved_candidates/S6%3F")), r.assertions.join(","));
  assert.match(asrtAttrs(IA, r)[0].disposition, /S1\(/, "the source's wording rides on the assertion");
  assert.equal(IA.nodes.get("obligation:inv:S6%3F").attrs.promotion, "resolved-into");
  const e44 = IA.nodes.get("claim:crosswalk:E-44"); assert.equal(e44.evidence_state.token, "TESTED");
  assert.ok(IA.rels.some((x) => x.kind === "DERIVES_FROM" && x.source === "claim:crosswalk:E-44" && x.target === "obligation:inv:S1"));
  assert.ok(IA.rels.some((x) => x.kind === "CITES" && x.source === "obligation:inv:S6%3F" && x.target === "claim:crosswalk:E-44"));
  assert.ok(IA.rels.some((x) => x.kind === "PRODUCED_BY" && x.source === "claim:crosswalk:E-44" && x.target === "experiment:r10:S6-falsifier"));
  const witnesses = IA.rels.filter((x) => x.kind === "WITNESSES" && x.target === "claim:crosswalk:E-44").map((x) => x.source);
  assert.ok(witnesses.some((w) => w.includes("S6_locus_birth.md")) && witnesses.some((w) => w.includes("cf_s6_world_admission_reuse.rs")), witnesses.join(","));
});

test("A2 is snapshot-relative: R0.8's open finding cites F36/F37 at the baseline; F35 is the open finding at the historical snapshot", () => {
  const opens = (I) => I.rels.filter((x) => x.kind === "OPENS" && x.source === "round:computedriven:R0.8").map((x) => x.target).sort();
  const citesOf = (I, from) => I.rels.filter((x) => x.kind === "CITES" && x.source === from).map((x) => x.target);
  const base = opens(IA), hist = opens(IH);
  const baseCited = new Set(base.flatMap((f) => citesOf(IA, f)));
  assert.ok(baseCited.has("finding:computedriven:F36") && baseCited.has("finding:computedriven:F37"), [...baseCited].join(","));
  assert.ok(hist.includes("finding:computedriven:F35"), hist.join(","));
  assert.ok(!base.includes("finding:computedriven:F35") && !baseCited.has("finding:computedriven:F35"), "F35 is neither open nor cited by an open finding at the baseline");
  assert.equal(new Set(base).size, base.length); assert.equal(hist.length, 5);
  assert.ok(base.every((f) => /^finding:(computedriven:F\d+|inv:h\.[0-9a-f]{16})$/.test(f)), base.join(","));
  assert.notEqual(ra.root, rh.root, "two snapshots, two roots");
  const closes = IA.rels.filter((x) => x.kind === "CLOSES").map((x) => x.target);
  for (const f of ["F31", "F32", "F33", "F34", "F22", "F30", "F23", "F24"]) assert.ok(closes.includes(`finding:computedriven:${f}`), `${f} closed by the v3 adjudication`);
  const f24 = IA.rels.find((x) => x.kind === "CLOSES" && x.target === "finding:computedriven:F24");
  assert.equal(f24.assertions.length, 2, "Q-25: F24 is closed under two sentences — one relation, two assertions");
});

test("A3: what supports S5 — E-48 implements it with an executed, hash-verified receipt; E-50a/E-50b/E-51 derive from it", () => {
  assert.ok(IA.rels.some((x) => x.kind === "IMPLEMENTS" && x.source === "claim:crosswalk:E-48" && x.target === "obligation:inv:S5"));
  const e48 = IA.nodes.get("claim:crosswalk:E-48"); assert.equal(e48.attrs.executed, true); assert.equal(e48.attrs.token_family, "TESTED");
  const rc = IA.rels.find((x) => x.kind === "WITNESSES" && x.target === "claim:crosswalk:E-48" && x.source.startsWith("receipt:sha256:21569669"));
  assert.ok(rc, "the sensitivity receipt witnesses E-48");
  const occ = asrtAttrs(IA, rc); assert.equal(occ.length, 1); assert.equal(occ[0].sensitivity_type, "pre-fix-fail"); assert.equal(occ[0].executed, true);
  assert.equal(IA.nodes.get(rc.source).attrs.sha256_verified_at_pin, true);
  const serves = (id) => IA.rels.find((x) => ["DERIVES_FROM", "REPRESENTS", "STATES", "IMPLEMENTS"].includes(x.kind) && x.source === `claim:crosswalk:${id}` && x.target === "obligation:inv:S5");
  assert.equal(serves("E-50a").kind, "DERIVES_FROM"); assert.equal(serves("E-50b").kind, "REPRESENTS"); assert.equal(serves("E-51").kind, "REPRESENTS");
  assert.equal(IA.nodes.get("claim:crosswalk:E-50a").evidence_state.token, "FALSIFIED-KEPT-RED");
});

test("A4 is snapshot-relative too: the R0.8.5 handback witnesses E-13b and E-14 at v2.6, only E-14 at v2.7 where E-13b's sensitivity witness became the R0.8.6 handback", () => {
  const R085 = "receipt:sha256:6ba8544cbf7c91ef526ddde97943d54845e1f352814173b8fa9a64f86867a913", R086 = "receipt:sha256:cffc0218fc450884ad2bf4d1630468c675b262e8260ef72b8c90dbf061016303";
  const claimsOf = (I, rc) => [...new Set(I.rels.filter((x) => x.kind === "WITNESSES" && x.source === rc && x.target.startsWith("claim:")).map((x) => x.target))].sort();
  assert.deepEqual(claimsOf(IH, R085), ["claim:crosswalk:E-13b", "claim:crosswalk:E-14"]);
  assert.deepEqual(claimsOf(IA, R085), ["claim:crosswalk:E-14"]);
  assert.deepEqual(claimsOf(IA, R086), ["claim:crosswalk:E-13b"]);
  assert.ok(IA.rels.filter((x) => x.kind === "ASSUMES" && x.source === "claim:crosswalk:E-13b").length >= 2, "E-13b carries its conditions");
  assert.ok(IA.rels.some((x) => x.kind === "TESTED_UNDER" && x.source === "claim:crosswalk:E-13b"));
  assert.ok(IA.rels.some((x) => x.kind === "SCOPED_BY" && x.source === "claim:crosswalk:E-13b"));
  for (const I of [IA, IH]) for (const n of I.nodes.values()) if (n.kind === "RECEIPT") assert.equal(n.attrs.sha256_verified_at_pin, true, n.lid);
});

test("A5: mechanisms exist only where a source names a symbol, resolved to a line at the vendored commit; IMPLEMENTS only from `relation: mechanism` records (D-021)", () => {
  const mechs = [...IA.nodes.values()].filter((n) => n.kind === "MECHANISM");
  assert.deepEqual(mechs.map((m) => m.lid).sort(), ["mechanism:computedriven:LifecycleAdmission", "mechanism:computedriven:reconstruct"]);
  for (const m of mechs) { assert.ok(m.attrs.line > 0, m.lid); assert.equal(m.attrs.commit, "efa8881a5d44011c165b24276a17d07d6556c047"); }
  assert.equal(IA.rels.filter((x) => x.kind === "IMPLEMENTS" && x.source.startsWith("mechanism:")).length, 0);
  assert.equal(IA.rels.filter((x) => x.kind === "IMPLEMENTS").length, 8, "the eight relation:mechanism records");
  assert.ok(IA.faults.filter((f) => f.code === "UNSUPPORTED_SOURCE_FORM" && /prose mechanism/.test(f.message)).length >= 1, "prose mechanisms are reported, not minted");
});

test("A6 inputs: the D-022 partition is computable from records — token_family, receipts_typed, verified receipts and the assertion-level executed flag", () => {
  const tested = [...IA.nodes.values()].filter((n) => n.kind === "CLAIM" && n.attrs.token_family === "TESTED");
  assert.equal(tested.length, 22, "22 TESTED-family claims (R7A)");
  const observed = new Set(IA.rels.filter((x) => x.kind === "WITNESSES" && IA.nodes.get(x.source)?.kind === "RECEIPT" && IA.nodes.get(x.source).attrs.sha256_verified_at_pin === true && asrtAttrs(IA, x).some((o) => o.executed === true)).map((x) => x.target));
  const partition = { EXEC_RECEIPT_OBSERVED: [], NO_EXEC_RECEIPT_OBSERVED: [], EXEC_RECEIPT_UNDECIDABLE_FROM_SOURCE: [] };
  for (const c of tested) { if (observed.has(c.lid)) partition.EXEC_RECEIPT_OBSERVED.push(c.lid); else if (c.attrs.receipts_typed === true) partition.NO_EXEC_RECEIPT_OBSERVED.push(c.lid); else partition.EXEC_RECEIPT_UNDECIDABLE_FROM_SOURCE.push(c.lid); }
  assert.deepEqual(partition.EXEC_RECEIPT_OBSERVED.map((l) => l.split(":").pop()).sort(), ["E-13b", "E-14", "E-15", "E-48"]);
  assert.equal(partition.NO_EXEC_RECEIPT_OBSERVED.length, 0, "no crosswalk record types its receipts, so absence is never decidable here");
  assert.equal(partition.EXEC_RECEIPT_UNDECIDABLE_FROM_SOURCE.length, 18);
  assert.equal(JSON.stringify([...IA.nodes.values()]).includes('"unsupported"'), false, "the withdrawn word appears in no record");
});

test("A7: every observed record has assertions pointing at source locations with a stated precision", () => {
  for (const n of IA.nodes.values()) { assert.equal(n.basis, "observed"); assert.ok(n.assertions.length >= 1, n.lid); for (const a of n.assertions) { const as = IA.asrts.get(a); assert.ok(as, a); assert.ok(IA.locs.has(as.location), as.location); assert.ok(["pointer", "heading", "line", "symbol", "file"].includes(IA.locs.get(as.location).precision)); } }
  const precisions = {}; for (const l of IA.locs.values()) precisions[l.precision] = (precisions[l.precision] || 0) + 1;
  assert.ok(precisions.pointer > 500 && precisions.file > 50 && precisions.symbol === 2, JSON.stringify(precisions));
});

test("faults are typed, attached, and stable: no DUPLICATE_ID, CONTRADICTION or SOURCE_MOVED at the pins; the known source-quality findings appear by code", () => {
  const codes = {}; for (const f of IA.faults) codes[f.code] = (codes[f.code] || 0) + 1;
  assert.equal(codes.DUPLICATE_ID, undefined); assert.equal(codes.SOURCE_MOVED, undefined); assert.equal(codes.CONTRADICTION, undefined);
  assert.equal(codes.TRUNCATED_FIELD, 5, "Q-02"); assert.equal(codes.UNQUALIFIED_REFERENCE, 3, "Q-23 / D-031"); assert.equal(codes.AMBIGUOUS_IDENTIFIER, 1, "the cells.json:16 trailing text");
  assert.ok(codes.UNRESOLVED_LINK >= 30, "Q-01"); assert.ok(codes.DANGLING_WITNESS >= 1, "Q-13");
  assert.ok(IA.faults.every((f) => f.concerns.length >= 1 && f.rule && f.message));
  const manifest = JSON.parse(readFileSync(join(A, "manifest.json"), "utf8")); assert.equal(manifest.faults.count, IA.faults.length);
  const hc = {}; for (const f of IH.faults) hc[f.code] = (hc[f.code] || 0) + 1; assert.deepEqual(hc, codes, "both pins raise the same fault codes and counts");
});
