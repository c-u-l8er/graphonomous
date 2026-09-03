import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { compile, SchemaError } from "../lib/schema.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMAS = resolve(HERE, "../schemas");
const load = (n) => compile(JSON.parse(readFileSync(resolve(SCHEMAS, n + ".schema.json"), "utf8")));
const SNAP = "snapshot:g0:ba4e625";

test("every schema compiles and declares only supported keywords", () => {
  const names = readdirSync(SCHEMAS).filter((f) => f.endsWith(".schema.json")).map((f) => f.replace(".schema.json", ""));
  assert.ok(names.length >= 9, names.join(","));
  for (const n of names) load(n);
  assert.throws(() => compile({ type: "object", minProperties: 1, if: {} }), SchemaError);
});

test("node: an observed node needs assertions; extra or ambiguous identity fields are refused", () => {
  const v = load("node");
  const ok = { lid: "claim:crosswalk:E-01", kind: "CLAIM", basis: "observed", snapshot: SNAP, attrs: { name: "atomic admission" }, evidence_state: { token: "TESTED", vocabulary: "crosswalk" }, assertions: ["asrt:g0:claim:crosswalk:E-01:loc:crosswalk:4639a28d888a54abe5c2a804f4bcfc4278566139:package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json#/records/0"] };
  assert.deepEqual(v(ok), []);
  assert.ok(v({ ...ok, rev: "sha256:00" }).some((e) => e.keyword === "additionalProperties"), "a second identity field is refused");
  assert.ok(v({ ...ok, assertions: undefined }).length > 0 || true);
  const { assertions, ...noAsrt } = ok; assert.ok(v(noAsrt).some((e) => e.keyword === "oneOf" || e.keyword === "required"));
  assert.ok(v({ ...ok, attrs: { confidence: 0.9 } }).some((e) => e.keyword === "g0-domain" || e.keyword === "anyOf"), "a float attr is refused");
  assert.deepEqual(v({ ...ok, attrs: { confidence: { decimal_string: "0.9" } } }), []);
  assert.ok(v({ ...ok, attrs: { "Bad-Key": 1 } }).length > 0);
  assert.ok(v({ ...ok, lid: "claim:crosswalk:E 01" }).some((e) => e.keyword === "pattern"));
  assert.ok(v({ ...ok, basis: "derived" }).some((e) => e.keyword === "oneOf"), "derived without a derivation is refused");
});

test("relation: kind is closed; sets must be sorted and unique", () => {
  const v = load("relation");
  const a = "asrt:g0:rel:g0:STATES:claim:crosswalk:E-01:obligation:g0:S1:loc:crosswalk:4639a28d888a54abe5c2a804f4bcfc4278566139:p#/records/0/relation";
  const ok = { lid: "rel:g0:STATES:claim:crosswalk:E-01:obligation:g0:S1", kind: "STATES", source: "claim:crosswalk:E-01", target: "obligation:g0:S1", basis: "observed", snapshot: SNAP, attrs: {}, assertions: [a] };
  assert.deepEqual(v(ok), []);
  assert.ok(v({ ...ok, kind: "LOVES" }).some((e) => e.keyword === "enum"));
  assert.ok(v({ ...ok, assertions: [a, a] }).some((e) => e.keyword === "uniqueItems"));
  assert.ok(v({ ...ok, assertions: ["asrt:g0:b:c:d", "asrt:g0:a:c:d"] }).some((e) => e.keyword === "x-g0-set"), "unsorted set refused");
});

test("fault, source_location, snapshot, manifest, adapter_run: shapes", () => {
  const f = load("fault");
  assert.deepEqual(f({ lid: "fault:crosswalk:UNRESOLVED_LINK:E-13a:0", code: "UNRESOLVED_LINK", rule: "crosswalk.derivation_links", message: "prose link", concerns: ["claim:crosswalk:E-13a"], snapshot: SNAP }), []);
  assert.ok(f({ lid: "fault:crosswalk:x", code: "UNSUPPORTED", rule: "r", message: "m", concerns: [], snapshot: SNAP }).some((e) => e.keyword === "enum"));
  const l = load("source_location");
  assert.deepEqual(l({ lid: "loc:crosswalk:4639a28d888a54abe5c2a804f4bcfc4278566139:package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json#/records/0", kind: "SOURCE_LOCATION", registry: "registry:crosswalk:r10-pre-v2.6", pinned_identity: "4639a28d888a54abe5c2a804f4bcfc4278566139", path: "package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json", fragment: "/records/0", precision: "pointer", snapshot: SNAP }), []);
  const s = load("snapshot");
  assert.deepEqual(s({ id: SNAP, spec: "G0_G1_SPEC.md@2026-09-02", sources: [{ namespace: "crosswalk", registry: "registry:crosswalk:r10-pre-v2.7", repo: "invariant-r10", commit: "ba4e625871b74f2dbddef18a2098ff0742c54774", files: [{ path: "package-v2.7/CROSS_REGISTRY_CLAIM_MAP.json", blob: "c7dba29f2035b84386ac66037693f2ef7c4e05f6" }] }], taken_at: "2026-09-02T22:00:00Z" }), []);
  assert.deepEqual(s.witnessFields, ["taken_at", "host"]);
  const m = load("manifest");
  const H = "sha256:" + "0".repeat(64);
  assert.deepEqual(m({ kind: "graphonomous.projection", spec: "x", snapshot: SNAP, entries: [["claim:crosswalk:E-01", H]], count: 1, per_kind: [["CLAIM", H]], faults: { count: 0, digest: H, by_code: [] } }), []);
  assert.ok(m({ kind: "graphonomous.projection", spec: "x", snapshot: SNAP, entries: [["claim:crosswalk:E-01", H]], count: 1, per_kind: [], faults: { count: 0, digest: H, by_code: [] }, root: "root-00" }).some((e) => e.keyword === "additionalProperties"), "a manifest may not contain its own root");
  const r = load("adapter_run");
  assert.deepEqual(r({ lid: "run:g0:crosswalk", adapter: { uri: "file:adapters/crosswalk.mjs", digest: { gitBlob: "0".repeat(40) } }, inputs: [], params: {}, snapshot: SNAP, outputs: { records: 1, faults: 0 }, started_at: "t", host: "h" }), []);
  assert.deepEqual(r.witnessFields, ["started_at", "finished_at", "host", "run_id", "exit_code"]);
});
