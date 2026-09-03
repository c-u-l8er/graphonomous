/* query.test.mjs — G0-E: A1–A7 as EXECUTABLE QUERIES through the public six-function surface over the SHIPPED
 * projections (projections/baseline, projections/historical, each with derived/), plus the six additional tests of the
 * B.1→E continuation prompt. No git, no adapter: everything here can be re-run from the handoff ZIP. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync, rmSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { Projections } from "../lib/query.mjs";
import { runEvaluation, verifyEvaluation, loadProjection, baseFactsOf } from "../lib/evaluation.mjs";
import { checkDerivation, makeFactStore } from "../lib/check.mjs";
import { loadRules } from "../lib/rules.mjs";
import { contextBoundLid, parseLid } from "../lib/lid.mjs";
import { canonicalBytesG0 } from "../lib/canon.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = resolve(V, "projections/baseline"), HIST = resolve(V, "projections/historical");
const P = new Projections([BASE, HIST]);
const [SB, SH] = ["snapshot:g0:baseline-ba4e625", "snapshot:g0:historical-699fbc2"];
const b = P.as_of(SB), h = P.as_of(SH);
const R085 = "receipt:sha256:6ba8544cbf7c91ef526ddde97943d54845e1f352814173b8fa9a64f86867a913", R086 = "receipt:sha256:cffc0218fc450884ad2bf4d1630468c675b262e8260ef72b8c90dbf061016303";
const S6 = "obligation:inv:S6%3F", S1 = "obligation:inv:S1", S5 = "obligation:inv:S5", R08 = "round:computedriven:R0.8";
const local = (lid) => lid.split(":").pop();
/** Walk an explanation tree and collect every leaf: base facts (with their sources) and absences. */
const leaves = (node, acc = []) => { if (!node) return acc; if (node.basis === "absent") acc.push(node); else if (node.basis === "base") acc.push(node); else if (node.premises) for (const p of node.premises) leaves(p, acc); else if (node.derivations) for (const d of node.derivations) leaves(d, acc); return acc; };

test("as_of: two snapshots, two roots, never mixed — every record and derived fact carries its own snapshot", () => {
  assert.deepEqual(P.snapshots(), [SB, SH]);
  assert.notEqual(b.root, h.root); assert.match(b.root, /^root-[0-9a-f]{64}$/);
  for (const g of [b, h]) { for (const r of [...g.nodes.values(), ...g.relations.values(), ...g.assertions.values()]) assert.equal(r.snapshot, g.snapshot); assert.equal(g.derived.manifest.projection_root, g.root); assert.equal(g.derived.manifest.snapshot, g.snapshot); for (const f of g.derived.facts) { assert.equal(f.snapshot, g.snapshot); assert.deepEqual(f.inputs, [g.root]); } }
  assert.notEqual(b.derived.root, h.derived.root); assert.notEqual(b.derived.manifest.digest, h.derived.manifest.digest);
  assert.throws(() => P.as_of("snapshot:g0:nope"), /no projection loaded/);
});

test("A1 — why isn't S6 a primitive? a DERIVED not_primitive whose explanation bottoms out in the crosswalk's resolved_candidates pointer", () => {
  assert.deepEqual(b.facts("not_primitive").map((f) => f.args[0]), [S6]);
  const ex = b.explain(["not_primitive", S6]);
  assert.equal(ex.basis, "derived"); assert.equal(ex.trvm_derivation, false); assert.equal(ex.depth, 2);
  const d = ex.derivations[0]; assert.match(d.rule, /#not_primitive$/);
  assert.equal(d.premises[0].basis, "derived"); assert.match(d.premises[0].rule, /#reduces_to_direct$/);
  const base = leaves(ex); assert.ok(base.every((l) => l.basis === "base"), "a positive derivation, never failure-to-find (spec §5.5)");
  const relLeaf = base.find((l) => l.fact[0] === "rel"); assert.equal(relLeaf.fact[2], "REDUCES_TO"); assert.equal(relLeaf.fact[3], S6); assert.equal(relLeaf.fact[4], S1);
  assert.ok(relLeaf.source.assertions.some((a) => a.location.fragment === "/resolved_candidates/S6?" && a.location.precision === "pointer" && a.location.lid.endsWith("#/resolved_candidates/S6%3F")), JSON.stringify(relLeaf.source.assertions.map((a) => a.location.fragment)));
  assert.deepEqual(b.neighbors(S6, "REDUCES_TO", "out").map((n) => n.other), [S1]);
  assert.equal(b.path(S6, "claim:crosswalk:E-44").length, 1, "S6? cites E-44 directly");
  assert.equal(b.node(S6).attrs.promotion, "resolved-into");
  assert.equal(b.node("claim:crosswalk:E-44").evidence_state.token, "TESTED");
});

test("A2 — what opens R0.8? snapshot-relative: F36/F37 cut at the baseline, F35 (+4 unnamed) at the historical pin; one OPENS relation carries both registries", () => {
  const opensB = b.neighbors(R08, "OPENS", "out"), opensH = h.neighbors(R08, "OPENS", "out");
  assert.equal(opensB.length, 1); assert.equal(opensH.length, 5);
  const fB = b.node(opensB[0].other); assert.equal(fB.attrs.unnamed, true); assert.equal(fB.attrs.container, R08);
  assert.deepEqual(b.neighbors(fB.lid, "CITES", "out").map((n) => local(n.other)).sort(), ["F36", "F37"]);
  assert.ok(opensH.some((n) => n.other === "finding:computedriven:F35")); assert.ok(!opensB.some((n) => n.other === "finding:computedriven:F35"));
  const ex = b.explain(opensB[0].relation.lid);
  assert.equal(ex.assertions.length, 2); assert.deepEqual(ex.assertions.map((a) => a.asserted_by.split(":")[1]).sort(), ["crosswalk", "evstate"]);
  assert.ok(ex.assertions.every((a) => a.attrs.text.startsWith("NC29/NC30")));
  assert.deepEqual(b.neighbors("finding:computedriven:F24", "CLOSES", "in").length, 1, "Q-25: F24 closed once, however many sentences");
  assert.equal(b.explain(b.neighbors("finding:computedriven:F24", "CLOSES", "in")[0].relation.lid).assertions.length, 2);
});

test("A3 — what supports S5? E-48 IMPLEMENTS it with an executed, hash-verified receipt (derived has_exec_receipt explains through the assertion's executed flag); E-50a/b, E-51 serve it", () => {
  const into = b.neighbors(S5, null, "in");
  const kindOf = (id) => into.find((n) => n.other === `claim:crosswalk:${id}`)?.relation.kind;
  assert.equal(kindOf("E-48"), "IMPLEMENTS"); assert.equal(kindOf("E-50a"), "DERIVES_FROM"); assert.equal(kindOf("E-50b"), "REPRESENTS"); assert.equal(kindOf("E-51"), "REPRESENTS");
  assert.ok(b.facts("exec_receipt_observed").some((f) => f.args[0] === "claim:crosswalk:E-48"));
  const ex = b.explain(["has_exec_receipt", "claim:crosswalk:E-48"]);
  const d = ex.derivations[0]; const relP = d.premises[0], aattrP = d.premises[4];
  assert.match(relP.fact[1], /^rel:g0:WITNESSES:receipt:sha256:21569669/);
  assert.deepEqual(aattrP.fact.slice(2), ["executed", true]);
  assert.equal(aattrP.source.attrs.sensitivity_type, "pre-fix-fail"); assert.equal(aattrP.source.attrs.role, "sensitivity");
  assert.equal(aattrP.source.location.fragment, "/promotions/3/sensitivity_witness");
  assert.equal(b.node(relP.fact[3]).attrs.sha256_verified_at_pin, true);
  assert.equal(b.node("claim:crosswalk:E-50a").evidence_state.token, "FALSIFIED-KEPT-RED");
});

test("A4 — how did E-13b's witness provenance change? the R0.8.5 handback witnesses E-13b+E-14 at v2.6 and E-14 alone at v2.7; roles stay on the assertions", () => {
  const claims = (g, rc) => g.neighbors(rc, "WITNESSES", "out").map((n) => n.other).filter((x) => x.startsWith("claim:")).sort();
  assert.deepEqual(claims(h, R085), ["claim:crosswalk:E-13b", "claim:crosswalk:E-14"]);
  assert.deepEqual(claims(b, R085), ["claim:crosswalk:E-14"]);
  assert.deepEqual(claims(b, R086), ["claim:crosswalk:E-13b"]);
  const rel = b.facts("WITNESSES", { source: R085, target: "claim:crosswalk:E-14" }); assert.equal(rel.length, 1);
  const ex = b.explain(rel[0].lid); assert.deepEqual(ex.assertions.map((a) => a.attrs.role).sort(), ["repair", "sensitivity"]);
  assert.ok(b.neighbors("claim:crosswalk:E-13b", "ASSUMES", "out").length >= 2); assert.equal(b.neighbors("claim:crosswalk:E-13b", "TESTED_UNDER", "out").length, 1);
  const hist = h.explain(h.facts("WITNESSES", { source: R085, target: "claim:crosswalk:E-13b" })[0].lid);
  assert.ok(hist.assertions.length >= 1 && hist.assertions.every((a) => ["sensitivity", "repair", "pre-fix"].includes(a.attrs.role)), "at v2.6 the R0.8.5 handback is E-13b's sensitivity (and repair) witness — one relation, one assertion per role");
  assert.equal(b.facts("WITNESSES", { source: R085, target: "claim:crosswalk:E-13b" }).length, 0, "at v2.7 that receipt no longer witnesses E-13b at all");
});

test("A5 — which mechanisms are represented, on what evidence? two MECHANISM nodes from symbols; mechanism_of derives only from the eight `relation: mechanism` records", () => {
  assert.deepEqual(b.facts("MECHANISM").map((m) => m.lid), ["mechanism:computedriven:LifecycleAdmission", "mechanism:computedriven:reconstruct"]);
  const mo = b.facts("mechanism_of"); assert.equal(mo.length, 8); assert.ok(mo.every((f) => f.args[0].startsWith("claim:crosswalk:")));
  const ex = b.explain(["mechanism_of", "claim:crosswalk:E-48", S5]); const leaf = leaves(ex)[0];
  assert.equal(leaf.fact[2], "IMPLEMENTS"); assert.ok(leaf.source.assertions.some((a) => /\/records\/\d+\/relation$/.test(a.location.fragment)));
  for (const m of b.facts("MECHANISM")) { const ex2 = b.explain(m.lid); assert.ok(ex2.assertions.length >= 1); assert.equal(b.neighbors(m.lid, "LOCATED_IN", "out").length, 1); assert.equal(b.locations.get(b.explain(b.neighbors(m.lid, "LOCATED_IN", "out")[0].other).record.lid).precision, "symbol"); }
});

test("A6 — the three-way execution-receipt partition as DERIVED facts (D-022 names), absence only where decidable, no authority inflation", () => {
  const names = (rule) => b.facts(rule).map((f) => local(f.args[0])).sort();
  assert.deepEqual(names("exec_receipt_observed"), ["E-13b", "E-14", "E-15", "E-48"]);
  assert.deepEqual(names("no_exec_receipt_observed"), [], "no crosswalk record types its receipts: absence is never decidable here");
  assert.equal(names("exec_receipt_undecidable_from_source").length, 18);
  assert.equal(names("tested_claim").length, 22);
  const ex = b.explain(["exec_receipt_undecidable_from_source", "claim:crosswalk:E-10"]);
  const abs = leaves(ex).filter((l) => l.basis === "absent"); assert.deepEqual(abs.map((l) => l.absent), [["has_exec_receipt", "claim:crosswalk:E-10"]]);
  assert.ok(leaves(ex).some((l) => l.basis === "base" && l.fact[0] === "attr" && l.fact[2] === "receipts_typed" && l.fact[3] === false), "the undecidability premise is the source's own untyped receipts");
  const text = JSON.stringify(b.derived.facts); assert.ok(!text.includes('"unsupported"'));
  for (const f of b.derived.facts) { assert.equal(f.basis, "derived"); assert.equal(f.trvm_derivation, false); }
  assert.deepEqual(h.facts("exec_receipt_observed").map((f) => local(f.args[0])).sort(), ["E-13b", "E-14", "E-15", "E-48"], "same partition at the historical pin (its receipts differ, its verdict does not)");
});

test("A7 — every answer explains down to exact source assertions and locations: all relations, all derived facts", () => {
  for (const g of [b, h]) {
    for (const r of g.relations.values()) { const ex = g.explain(r.lid); assert.ok(ex.assertions.length >= 1, r.lid); for (const a of ex.assertions) { assert.ok(!a.location.missing, a.lid); assert.ok(["pointer", "heading", "line", "symbol", "file"].includes(a.location.precision)); assert.match(a.location.pinned_identity, /^[0-9a-f]{40}$|^sha256:/); } }
    for (const f of g.derived.facts) { const ex = g.explain([f.rel, ...f.args]); const ls = leaves(ex); assert.ok(ls.length >= 1, f.rel); for (const l of ls) if (l.basis === "base") { assert.ok(l.source && !l.source.missing, JSON.stringify(l.fact).slice(0, 120)); if (l.source.assertions) assert.ok(l.source.assertions.length >= 1); else assert.ok(l.source.location, "an assertion-level base fact points at its location"); } }
  }
});

test("E-1/E-2 — two source citations of one relation: one relation, two assertions; explain returns both occurrences", () => {
  const rels = b.facts("WITNESSES", { source: R085, target: "claim:crosswalk:E-14" }); assert.equal(rels.length, 1);
  const ex = b.explain(rels[0].lid); assert.equal(ex.assertions.length, 2);
  assert.deepEqual(ex.assertions.map((a) => a.location.fragment).sort(), ["/promotions/1/repair_witness", "/promotions/1/sensitivity_witness"]);
  const e13b = b.explain(b.facts("WITNESSES", { source: R086, target: "claim:crosswalk:E-13b" })[0].lid); assert.equal(e13b.assertions.length, 3);
  const multi = [...b.relations.values()].filter((r) => r.assertions.length > 1).length; assert.ok(multi >= 150);
  assert.equal(b.explain(["has_exec_receipt", "claim:crosswalk:E-14"]).derivations.length, 3, "three citations of receipts for E-14 → three derivations of ONE fact");
});

test("E-4 — a tampered derivation is rejected by the independent checker, in memory and from the stored artifact", () => {
  const rules = loadRules(); const p = loadProjection(BASE);
  const facts = new Map(); const key = (f) => canonicalBytesG0([f.rel, ...f.args]).toString("utf8");
  for (const f of baseFactsOf(p)) facts.set(key(f), { ...f, depth: 0 }); for (const f of p.derived.facts) facts.set(key(f), f);
  const store = makeFactStore(facts);
  const good = p.derived.byKey.get(key({ rel: "not_primitive", args: [S6] })).derivations[0];
  assert.equal(checkDerivation(rules.doc, rules.rule_sem_id, good, store).ok, true);
  const bad = JSON.parse(JSON.stringify(good)); bad.conclusion[1] = S1; const r = checkDerivation(rules.doc, rules.rule_sem_id, bad, store); assert.equal(r.ok, false); assert.ok(r.problems.length >= 1);
  // stored artifact: copy derived/, flip one premise, replay
  const tmp = mkdtempSync(join(tmpdir(), "g0-eval-")); try {
    const dir = join(tmp, "derived"); cpSync(join(BASE, "derived"), dir, { recursive: true });
    const lines = readFileSync(join(dir, "facts.jsonl"), "utf8").split("\n"); const i = lines.findIndex((l) => l.includes('"not_primitive"')); const rec = JSON.parse(lines[i]);
    rec.derivations[0].premises[0][1] = S1; lines[i] = canonicalBytesG0(rec).toString("utf8"); writeFileSync(join(dir, "facts.jsonl"), lines.join("\n"));
    const v = verifyEvaluation(BASE, dir); assert.ok(v.problems.some((x) => /is not a fact|does not match|hash differently/.test(x)), v.problems.join("\n"));
    assert.deepEqual(verifyEvaluation(BASE).problems, [], "the shipped artifact replays clean");
  } finally { rmSync(tmp, { recursive: true, force: true }); }
});

test("E-3/E-5 — the shipped evaluation is reproducible (same digest and root from a fresh run); the unnamed finding's identity is container-bound", () => {
  const tmp = mkdtempSync(join(tmpdir(), "g0-eval2-")); try {
    const r = runEvaluation(BASE, { out: join(tmp, "d") }); assert.equal(r.manifest.digest, b.derived.manifest.digest); assert.equal(r.root, b.derived.root);
  } finally { rmSync(tmp, { recursive: true, force: true }); }
  const f = b.node(b.neighbors(R08, "OPENS", "out")[0].other);
  assert.equal(f.lid, contextBoundLid("FINDING", "inv", R08, f.attrs.text));
  assert.notEqual(f.lid, contextBoundLid("FINDING", "inv", "round:computedriven:R0.9", f.attrs.text), "the same sentence under another round would be another finding");
});

test("E-6 — an unqualified unique factory id is resolved AND faulted; the raw token and resolution basis are on the assertion", () => {
  const cites = b.facts("CITES", { target: "claim:factory:TAX-FLOW" }); assert.equal(cites.length, 1);
  const ex = b.explain(cites[0].lid); assert.equal(ex.assertions.length, 1);
  assert.equal(ex.assertions[0].attrs.qualified, false); assert.equal(ex.assertions[0].attrs.raw_token, "TAX-FLOW"); assert.equal(ex.assertions[0].attrs.resolution_basis, "unique-pinned-match");
  const faults = b.facts("FAULT", { code: "UNQUALIFIED_REFERENCE" }); assert.equal(faults.length, 3);
  assert.ok(faults.some((f) => f.concerns.includes("claim:factory:TAX-FLOW") && f.concerns.includes("claim:crosswalk:E-41")));
  assert.equal(b.facts("FAULT", { code: "AMBIGUOUS_IDENTIFIER" }).length, 1, "the only ambiguity in the real data is a cells.json trailing text; the bare-id ambiguous path is exercised in test/b1.test.mjs");
});

test("D-037 (the D-034 ruling): transition → claim is STATE_TRANSITION_OF (14 at both pins), no SUPERSEDES is inferred from the chain (0 at both pins), so the frozen `superseded` rule derives nothing and `current` keeps every claim with a recorded transition", () => {
  for (const g of [b, h]) {
    assert.equal(g.facts("STATE_TRANSITION_OF").length, 14, `${g.snapshot}: STATE_TRANSITION_OF`);
    assert.equal(g.facts("SUPERSEDES").length, 0, `${g.snapshot}: SUPERSEDES`);
    for (const r of g.facts("STATE_TRANSITION_OF")) { assert.ok(r.source.startsWith("transition:") && r.target.startsWith("claim:"), r.lid); assert.ok(("typed" in r.attrs) || ("from_text" in r.attrs && "to_text" in r.attrs), "the from_text/to_text or typed attrs ride on STATE_TRANSITION_OF now"); }
    assert.deepEqual(g.facts("superseded"), [], `${g.snapshot}: superseded derives nothing on this data — the rule text is unchanged`);
    const cur = new Set(g.facts("current").map((f) => f.args[0]));
    for (const id of ["E-12", "E-13a", "E-13b", "E-13c", "E-14", "E-15", "E-48", "E-51"]) assert.ok(cur.has(`claim:crosswalk:${id}`), `${g.snapshot}: ${id} is current`);
    assert.ok(cur.has("claim:crosswalk:E-10"));
    assert.equal(g.facts("current").length, g.nodes.size, "with nothing superseded or retracted, every node is current");
  }
  const ex = b.explain(["current", "claim:crosswalk:E-14"]); assert.equal(ex.basis, "derived");
  assert.ok(leaves(ex).some((l) => l.basis === "absent" && l.absent[0] === "superseded"), "E-14 is current because no SUPERSEDES targets it — an {absent} premise, recorded");
  assert.equal(b.derived.manifest.by_rule.superseded, undefined); assert.equal(b.derived.manifest.by_rule.current, b.nodes.size);
});

test("D-037 regression: has_exec_receipt is GENERIC over its subject (rule variable `Subject`): at least one CLAIM and one EVIDENCE_STATE_TRANSITION satisfy it on the shipped baseline, while the A6 partition is unchanged", () => {
  const rules = loadRules(); const her = rules.doc.rules.find((r) => r.name === "has_exec_receipt");
  assert.deepEqual(her.head.args, ["Subject"]); assert.ok(her.body.some((x) => x.rel === "rel" && x.args[3] === "Subject")); assert.ok(!/claim-only|the claim\b/.test(her.doc));
  assert.equal(b.derived.manifest.ruleset, rules.rule_sem_id, "the shipped evaluation is bound to the current (moved) ruleset id");
  const byKind = {}; for (const f of b.facts("has_exec_receipt")) { const k = parseLid(f.args[0]).kind; byKind[k] = (byKind[k] || 0) + 1; }
  assert.ok(byKind.CLAIM >= 1, JSON.stringify(byKind)); assert.ok(byKind.EVIDENCE_STATE_TRANSITION >= 1, JSON.stringify(byKind));
  assert.deepEqual(Object.keys(byKind).sort(), ["CLAIM", "EVIDENCE_STATE_TRANSITION"]);
  const names = (g, rule) => g.facts(rule).map((f) => local(f.args[0])).sort();
  for (const g of [b, h]) {
    assert.deepEqual(names(g, "exec_receipt_observed"), ["E-13b", "E-14", "E-15", "E-48"], g.snapshot);
    assert.deepEqual(names(g, "no_exec_receipt_observed"), [], g.snapshot);
    assert.equal(names(g, "exec_receipt_undecidable_from_source").length, 18, g.snapshot);
    for (const f of g.facts("exec_receipt_observed")) assert.equal(parseLid(f.args[0]).kind, "CLAIM", "the A6 rules restrict the subject through tested_claim, not through has_exec_receipt");
  }
});
