/* b1.test.mjs — G0-B.1 identity normalization on SYNTHETIC sources through the real adapter (D-029, D-030, D-031).
 * The pinned registries happen not to contain an ambiguous bare id or one sentence under two rounds; these tests
 * build a crosswalk that does, so the refusal paths are exercised rather than assumed. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { ingestCrosswalk, resolveBareToken, BARE_TOKEN } from "../adapters/crosswalk.mjs";
import { fakeRepo, sha256Of } from "./helpers/fake_repo.mjs";
import { contextBoundLid } from "../lib/lid.mjs";

const SENTENCE = "single-host only — no partition-tolerant consensus claim";
const receipt = '{"receipt":"synthetic","result":"pass"}\n';
const crosswalk = (extra = {}) => ({
  crosswalk_version: "synthetic-v1", status: "DRAFT synthetic", field_note: "", ontology: [],
  semantic_obligations: { S1: "Locus identity", CROSS: "cross-cutting", DEF: "definition", REPR: "representation" },
  factory_candidates: { "FAC-CONTROL-SENSITIVITY": { statement: "the factory must be control-sensitive", status: "candidate", source: "synthetic" } },
  records: [
    { record_id: "E-01", name: "one", source_registry: "claim-ledger", source_ids: ["FAC-CONTROL-SENSITIVITY", "TAX-FLOW", "NOPE-TOKEN-9"], relation: "direct", semantic_obligation: "S1", evidence_class: "TESTED synthetic", evidence_class_token: "TESTED", witness_paths: ["w/a.md"], scope_profile: "single host" },
    { record_id: "E-02", name: "two", source_registry: "claim-ledger", source_ids: ["TAX-FLOW"], relation: "direct", semantic_obligation: "S1", evidence_class: "TESTED synthetic", evidence_class_token: "TESTED", witness_paths: ["w/a.md", "w/a.md"] },
  ],
  promotions: [{ record_id: "E-01", promoted_in: "v1", from: "OPEN", to: "TESTED", executed: true, sensitivity_witness: { type: "pre-fix-fail", receipt: "w/r.json", sha256: sha256Of(receipt), what: "fails before" }, repair_witness: { receipt: "w/r.json", sha256: sha256Of(receipt), what: "passes after" } }],
  r0_8: { status: "OPEN", why: "synthetic", open_findings: [SENTENCE, "F35 leads this sentence and mentions F36"] },
  ...extra,
});
const evstate = (rounds) => ({ schema: "synthetic", source: "synthetic", records: [{ id: "E-01", class: "TESTED", receipts: [] }, { id: "E-02", class: "TESTED", receipts: [] }], statuses: rounds.map((id) => ({ id, status: "OPEN", open_findings: [SENTENCE] })) });

function run({ ledgerIds = ["TAX-FLOW", "FAC-CONTROL-SENSITIVITY"], rounds = ["R0.8", "R0.9"], cw = crosswalk() } = {}) {
  const r10 = fakeRepo("invariant-r10", { "pkg/CROSS_REGISTRY_CLAIM_MAP.json": cw, "pkg/evidence_state.json": evstate(rounds), "w/a.md": "# a witness\n", "w/r.json": receipt });
  const factory = fakeRepo("invariant-factory", { "CLAIM_LEDGER.json": { claims: ledgerIds.map((id) => ({ claim_id: id })) } });
  return ingestCrosswalk({ snapshot: "snapshot:g0:synthetic", repos: { r10, factory }, packageDir: "pkg", treeRegistries: {} });
}
const byLid = (items) => { const m = new Map(); for (const it of items) { if (!m.has(it.lid)) m.set(it.lid, []); m.get(it.lid).push(it); } return m; };

test("resolveBareToken: unique → one match; two namespaces → ambiguous; none → absent; input order is irrelevant", () => {
  const ns = (namespace, ids) => ({ namespace, pinned: `${namespace}@0`, ids: new Set(ids), lidFor: (id) => `claim:${namespace}:${id}` });
  assert.equal(resolveBareToken("TAX-FLOW", [ns("factory", ["TAX-FLOW"]), ns("other", ["X-1"])]).status, "unique");
  const amb = resolveBareToken("TAX-FLOW", [ns("factory", ["TAX-FLOW"]), ns("other", ["TAX-FLOW"])]);
  assert.equal(amb.status, "ambiguous"); assert.deepEqual(amb.matches.map((m) => m.lid), ["claim:factory:TAX-FLOW", "claim:other:TAX-FLOW"]);
  assert.deepEqual(resolveBareToken("TAX-FLOW", [ns("other", ["TAX-FLOW"]), ns("factory", ["TAX-FLOW"])]).matches.map((m) => m.lid), ["claim:factory:TAX-FLOW", "claim:other:TAX-FLOW"]);
  assert.equal(resolveBareToken("TAX-FLOW", [ns("factory", ["X"])]).status, "absent");
  assert.ok(BARE_TOKEN.test("EMB-CUT-EMPTY") && BARE_TOKEN.test("TAX-RELATIONAL-2") && !BARE_TOKEN.test("S1") && !BARE_TOKEN.test("claim-ledger:X-1") && !BARE_TOKEN.test("cells.json:27a"));
});

test("B1-6 through the adapter: unique bare id → CITES edge + UNQUALIFIED_REFERENCE; ambiguous → AMBIGUOUS_IDENTIFIER and NO edge; absent → UNRESOLVED_LINK", () => {
  const out = run().crosswalk;
  const rels = out.relations, faults = out.faults;
  const cites = rels.filter((r) => r.kind === "CITES" && r.source === "claim:crosswalk:E-01");
  assert.deepEqual(cites.map((r) => r.target), ["claim:factory:TAX-FLOW"], "exactly the unique token is linked");
  const a = cites[0].assertion.attrs;
  assert.deepEqual({ ...a, resolved_in: a.resolved_in.replace(/@[0-9a-f]{40}$/, "@<commit>") }, { source_id: "TAX-FLOW", raw_token: "TAX-FLOW", qualified: false, resolution_basis: "unique-pinned-match", resolved_namespace: "factory", resolved_in: "invariant-factory@<commit>" });
  const unq = faults.filter((f) => f.code === "UNQUALIFIED_REFERENCE");
  assert.equal(unq.length, 2, "E-01 and E-02 each cite TAX-FLOW bare");
  assert.ok(unq.every((f) => f.concerns.includes("claim:factory:TAX-FLOW") && f.attrs.resolved_to === "claim:factory:TAX-FLOW"));
  const amb = faults.filter((f) => f.code === "AMBIGUOUS_IDENTIFIER");
  assert.equal(amb.length, 1); assert.equal(amb[0].attrs.text, "FAC-CONTROL-SENSITIVITY");
  assert.deepEqual(amb[0].attrs.candidates, ["claim:factory:FAC-CONTROL-SENSITIVITY", "obligation:inv:FAC-CONTROL-SENSITIVITY"]);
  assert.ok(!rels.some((r) => r.source === "claim:crosswalk:E-01" && /FAC-CONTROL-SENSITIVITY$/.test(r.target)), "no edge for the ambiguous token");
  assert.ok(!out.nodes.some((n) => n.lid === "claim:factory:FAC-CONTROL-SENSITIVITY"), "no factory claim node was minted for it either");
  const absent = faults.filter((f) => f.code === "UNRESOLVED_LINK" && f.attrs?.reason === "bare-token-absent");
  assert.equal(absent.length, 1); assert.equal(absent[0].attrs.text, "NOPE-TOKEN-9");
  // when the ledger stops carrying the colliding id, the same token becomes unique (resolution is a function of the pins)
  const out2 = run({ ledgerIds: ["TAX-FLOW"] }).crosswalk;
  assert.equal(out2.faults.filter((f) => f.code === "AMBIGUOUS_IDENTIFIER").length, 0);
  assert.ok(out2.relations.some((r) => r.kind === "CITES" && r.source === "claim:crosswalk:E-01" && r.target === "obligation:inv:FAC-CONTROL-SENSITIVITY"));
});

test("B1-1/B1-2: one receipt cited as sensitivity and repair witness of one claim is ONE relation with TWO assertions that keep their roles", () => {
  const out = run().crosswalk;
  const groups = byLid(out.relations.filter((r) => r.kind === "WITNESSES" && r.target === "claim:crosswalk:E-01" && r.source.startsWith("receipt:")));
  assert.equal(groups.size, 1, "one proposition");
  const [items] = [...groups.values()];
  assert.equal(items.length, 2);
  assert.deepEqual(items.map((i) => i.assertion.attrs.role).sort(), ["repair", "sensitivity"]);
  assert.deepEqual(items.map((i) => i.assertion.attrs.what).sort(), ["fails before", "passes after"]);
  assert.ok(items.every((i) => i.assertion.attrs.executed === true && i.attrs && Object.keys(i.attrs).length === 0), "occurrence data is on the assertion, the relation carries only the proposition");
  assert.notEqual(items[0].assertion.lid, items[1].assertion.lid);
  assert.ok(items.every((i) => !i.lid.includes("#/promotions")), "no citation location inside the relation lid");
});

test("B1-4/B1-5: the same unnamed sentence under two rounds is two findings; the crosswalk and evidence_state quoting it under one round meet on one lid", () => {
  const { crosswalk: cw, evidence_state: es } = run();
  const opens = [...cw.relations, ...es.relations].filter((r) => r.kind === "OPENS");
  const r8 = contextBoundLid("FINDING", "inv", "round:computedriven:R0.8", SENTENCE), r9 = contextBoundLid("FINDING", "inv", "round:computedriven:R0.9", SENTENCE);
  assert.notEqual(r8, r9);
  const targetsOf = (round) => opens.filter((r) => r.source === round).map((r) => r.target);
  assert.ok(targetsOf("round:computedriven:R0.8").includes(r8) && !targetsOf("round:computedriven:R0.8").includes(r9));
  assert.deepEqual(targetsOf("round:computedriven:R0.9"), [r9]);
  const r8Assertions = opens.filter((r) => r.source === "round:computedriven:R0.8" && r.target === r8).map((r) => r.assertion.asserted_by).sort();
  assert.deepEqual(r8Assertions, ["registry:crosswalk:synthetic-v1", "registry:evstate:synthetic-v1"], "two registries, one relation, two assertions");
  const node = cw.nodes.find((n) => n.lid === r8);
  assert.equal(node.attrs.text, SENTENCE); assert.equal(node.attrs.container, "round:computedriven:R0.8");
  // a sentence LEADING with an F-id is that finding; the id it mentions is a citation, not an opened finding
  assert.ok(targetsOf("round:computedriven:R0.8").includes("finding:computedriven:F35"));
  assert.ok(!targetsOf("round:computedriven:R0.8").includes("finding:computedriven:F36"));
  assert.ok(cw.relations.some((r) => r.kind === "CITES" && r.source === "finding:computedriven:F35" && r.target === "finding:computedriven:F36"));
});

test("a witness path listed twice by one record is one relation with one assertion per distinct citing location", () => {
  const out = run().crosswalk;
  const groups = byLid(out.relations.filter((r) => r.kind === "WITNESSES" && r.target === "claim:crosswalk:E-02"));
  assert.equal(groups.size, 1);
  const [items] = [...groups.values()];
  assert.deepEqual(items.map((i) => i.assertion.location.split("#")[1]).sort(), ["/records/1/witness_paths/0", "/records/1/witness_paths/1"]);
});
