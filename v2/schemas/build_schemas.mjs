// Regenerates the record schemas from the parts below so every schema carries the same common $defs.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
const HERE = dirname(fileURLToPath(import.meta.url));
const common = JSON.parse(readFileSync(resolve(HERE, "common.schema.json"), "utf8")).$defs;
const S = "https://json-schema.org/draft/2020-12/schema", BASE = "https://graphonomous.com/g0/schemas/";
const doc = (name, title, body, witness = []) => ({ $schema: S, $id: BASE + name + ".schema.json", title, "x-g0-witness": witness, ...body, $defs: common });
const lid = { $ref: "#/$defs/lid" }, hash = { $ref: "#/$defs/hash" }, attrs = { $ref: "#/$defs/attrs" }, snap = { $ref: "#/$defs/snapshot_id" };
/** G0-E derivation (spec §10.3, JTMS shape): conclusion and premises are ground atoms `[rel, ...args]`; a negated premise
 *  is `{absent: atom}`; the id binds {rule, conclusion, premises}. `rule` is `<g0rule-…>#<name>` — content-bound. */
const atom = { type: "array", minItems: 1, items: {} };
const derivationItem = {
  type: "object", required: ["id", "rule", "conclusion", "premises", "bindings", "depth"], additionalProperties: false,
  properties: {
    id: hash, rule: { type: "string", pattern: "^g0rule-[0-9a-f]{64}#[a-z][a-z0-9_]*$" }, conclusion: atom,
    premises: { type: "array", items: { anyOf: [atom, { type: "object", required: ["absent"], additionalProperties: false, properties: { absent: atom } }] } },
    bindings: { type: "object", propertyNames: { pattern: "^[A-Z][a-z0-9_]*$" } }, depth: { type: "integer", minimum: 1 },
  },
};
const derivation = { type: "array", minItems: 1, items: derivationItem };
const schemas = {
  node: doc("node", "G0 node record", {
    type: "object", required: ["lid", "kind", "basis", "snapshot", "attrs"], additionalProperties: false,
    properties: {
      lid, kind: { $ref: "#/$defs/node_kind" }, basis: { $ref: "#/$defs/basis" }, snapshot: snap, attrs,
      evidence_state: { $ref: "#/$defs/evidence_state" }, aliases: { type: "array", "x-g0-set": true, items: lid },
      assertions: { type: "array", "x-g0-set": true, items: lid, minItems: 1 }, derivation, wrl: { type: "object", properties: { object_id: { type: "string" }, role: { type: "string" } }, additionalProperties: false },
    },
    oneOf: [{ required: ["assertions"], properties: { basis: { const: "observed" } } }, { required: ["derivation"], properties: { basis: { enum: ["derived", "proposed"] } } }],
  }),
  relation: doc("relation", "G0 relation record", {
    type: "object", required: ["lid", "kind", "source", "target", "basis", "snapshot", "attrs"], additionalProperties: false,
    properties: {
      lid, kind: { $ref: "#/$defs/relation_kind" }, source: lid, target: lid, qualifier: { type: "string", pattern: "^[a-z][a-z0-9_]*=[A-Za-z0-9._/@+~#%-]+$" }, basis: { $ref: "#/$defs/basis" }, snapshot: snap, attrs,
      assertions: { type: "array", "x-g0-set": true, items: lid, minItems: 1 }, derivation,
      wrl: { type: "object", properties: { rev: { type: "string", pattern: "^rev-[0-9a-f]{64}$" }, rel: { type: "string", pattern: "^rel-[0-9a-f]{64}$" }, statement: { type: "string" } }, additionalProperties: false },
    },
    oneOf: [{ required: ["assertions"], properties: { basis: { const: "observed" } } }, { required: ["derivation"], properties: { basis: { enum: ["derived", "proposed"] } } }],
  }),
  assertion: doc("assertion", "G0 assertion: one source stating one subject at one location", {
    type: "object", required: ["lid", "subject", "location", "asserted_by", "precision", "snapshot"], additionalProperties: false,
    properties: { lid, subject: lid, location: lid, asserted_by: lid, precision: { $ref: "#/$defs/precision" }, snapshot: snap, attrs },
  }),
  source_location: doc("source_location", "G0 source location at a pinned identity", {
    type: "object", required: ["lid", "kind", "registry", "pinned_identity", "path", "precision", "snapshot"], additionalProperties: false,
    properties: { lid, kind: { const: "SOURCE_LOCATION" }, registry: lid, pinned_identity: { $ref: "#/$defs/pinned_identity" }, path: { type: "string", minLength: 1 }, fragment: { type: "string", minLength: 1 }, precision: { $ref: "#/$defs/precision" }, snapshot: snap },
  }),
  fault: doc("fault", "G0 fault: a malformed, ambiguous, contradictory or unsupported source state", {
    type: "object", required: ["lid", "code", "rule", "message", "concerns", "snapshot"], additionalProperties: false,
    properties: {
      lid, code: { enum: ["SOURCE_MOVED", "SCHEMA_UNEXPECTED_FIELD", "SCHEMA_MISSING_FIELD", "DANGLING_WITNESS", "DANGLING_SUPERSESSION", "DANGLING_CELL_BINDING", "UNRESOLVED_LINK", "TRUNCATED_FIELD", "UNPARSEABLE_CITATION", "HEADING_WITHOUT_NUMBER", "DUPLICATE_SECTION_NUMBER", "UNKNOWN_TOKEN", "DUPLICATE_ID", "AMBIGUOUS_IDENTIFIER", "WORKTREE_DIFFERS", "UNSUPPORTED_SOURCE_FORM", "UNQUALIFIED_REFERENCE", "NONDETERMINISM", "CONTRADICTION", "BAD_LID", "DUPLICATE_KEY", "LONE_SURROGATE", "CONTROL_IN_STRING", "INVALID_UTF8", "MALFORMED", "TYPED_COUNT_DISAGREES", "STALE_FIELD", "STATUS_OUTSIDE_VOCABULARY", "SETTLED_WITHOUT_WITNESS"] },
      rule: { type: "string", minLength: 1 }, source: { $ref: "#/$defs/resource_descriptor" }, pointer: { type: "string" }, anchor: { type: "string" },
      range: { type: "object", properties: { start: { type: "object", properties: { line: { type: "integer" }, column: { type: "integer" }, offset: { type: "integer" } }, additionalProperties: false }, end: { type: "object", properties: { line: { type: "integer" }, column: { type: "integer" }, offset: { type: "integer" } }, additionalProperties: false } }, additionalProperties: false },
      message: { type: "string", minLength: 1 }, concerns: { type: "array", "x-g0-set": true, items: lid }, snapshot: snap, attrs,
    },
  }),
  snapshot: doc("snapshot", "G0 snapshot: the pinned source identities one projection was built from", {
    type: "object", required: ["id", "spec", "sources"], additionalProperties: false,
    properties: {
      id: snap, spec: { type: "string", minLength: 1 }, label: { type: "string" }, params: attrs, taken_at: { type: "string" }, host: { type: "string" },
      sources: { type: "array", "x-g0-set": true, minItems: 1, items: { type: "object", required: ["namespace", "registry", "repo", "commit", "files"], additionalProperties: false,
        properties: { namespace: { type: "string", pattern: "^[a-z0-9][a-z0-9.-]*$" }, registry: lid, repo: { type: "string", minLength: 1 }, repo_dir: { type: "string", minLength: 1 }, commit: { $ref: "#/$defs/git_oid" }, branch: { type: "string" }, tree: { $ref: "#/$defs/git_oid" },
          files: { type: "array", "x-g0-set": true, minItems: 1, items: { type: "object", required: ["path", "blob"], additionalProperties: false, properties: { path: { type: "string", minLength: 1 }, blob: { $ref: "#/$defs/git_oid" }, sha256: { $ref: "#/$defs/hex64" }, bytes: { type: "integer", minimum: 0 } } } } } } },
    },
  }, ["taken_at", "host"]),
  adapter_run: doc("adapter_run", "G0 adapter run: the identity part is hashed, the witness part is not", {
    type: "object", required: ["lid", "adapter", "inputs", "params", "snapshot", "outputs"], additionalProperties: false,
    properties: { lid, adapter: { $ref: "#/$defs/resource_descriptor" }, inputs: { type: "array", "x-g0-set": true, items: { $ref: "#/$defs/resource_descriptor" } }, params: { $ref: "#/$defs/attrs" }, snapshot: snap,
      outputs: { type: "object", required: ["records", "faults"], additionalProperties: false, properties: { records: { type: "integer", minimum: 0 }, faults: { type: "integer", minimum: 0 }, records_digest: hash, faults_digest: hash } },
      started_at: { type: "string" }, finished_at: { type: "string" }, host: { type: "string" }, run_id: { type: "string" }, exit_code: { type: "integer" } },
  }, ["started_at", "finished_at", "host", "run_id", "exit_code"]),
  manifest: doc("manifest", "G0 projection manifest: sorted (lid, hash) entries; its CAS root is the projection root", {
    type: "object", required: ["kind", "spec", "snapshot", "entries", "count", "per_kind", "faults"], additionalProperties: false,
    properties: {
      kind: { const: "graphonomous.projection" }, spec: { type: "string", minLength: 1 }, snapshot: snap, ruleset: { type: "string", pattern: "^g0rule-[0-9a-f]{64}$" },
      entries: { type: "array", items: { type: "array", prefixItems: [lid, hash], minItems: 2, maxItems: 2 } }, count: { type: "integer", minimum: 0 },
      per_kind: { type: "array", items: { type: "array", prefixItems: [{ type: "string", minLength: 1 }, hash], minItems: 2, maxItems: 2 } },
      faults: { type: "object", required: ["count", "digest", "by_code"], additionalProperties: false, properties: { count: { type: "integer", minimum: 0 }, digest: hash, by_code: { type: "array", items: { type: "array", prefixItems: [{ type: "string" }, { type: "integer" }], minItems: 2, maxItems: 2 } } } },
      adapter_runs: { type: "array", "x-g0-set": true, items: hash },
    },
  }),
  derived_fact: doc("derived_fact", "G0-E derived fact: a ground atom with its derivations; basis derived, never a TRVM derivation", {
    type: "object", required: ["key", "rel", "args", "basis", "depth", "derivations", "snapshot", "inputs", "evaluator", "trvm_derivation"], additionalProperties: false,
    properties: { key: hash, rel: { type: "string", pattern: "^[a-z][a-z0-9_]*$" }, args: { type: "array", items: {} }, basis: { const: "derived" }, depth: { type: "integer", minimum: 1 }, derivations: derivation, snapshot: snap,
      inputs: { type: "array", "x-g0-set": true, minItems: 1, items: { type: "string", pattern: "^root-[0-9a-f]{64}$" } }, evaluator: { type: "string", minLength: 1 }, trvm_derivation: { const: false } },
  }),
  evaluation: doc("evaluation", "G0-E evaluation manifest: derived facts bound to one projection root and one rule program", {
    type: "object", required: ["kind", "spec", "snapshot", "projection_root", "ruleset", "evaluator", "trvm_derivation", "count", "by_rule", "digest", "entries", "checker"], additionalProperties: false,
    properties: {
      kind: { const: "graphonomous.rule-evaluation" }, spec: { type: "string", minLength: 1 }, snapshot: snap, projection_root: { type: "string", pattern: "^root-[0-9a-f]{64}$" }, ruleset: { type: "string", pattern: "^g0rule-[0-9a-f]{64}$" },
      evaluator: { type: "string", minLength: 1 }, trvm_derivation: { const: false }, count: { type: "integer", minimum: 0 }, by_rule: { type: "object", propertyNames: { pattern: "^[a-z][a-z0-9_]*$" }, additionalProperties: { type: "integer", minimum: 0 } }, digest: hash,
      entries: { type: "array", items: { type: "array", prefixItems: [hash, hash], minItems: 2, maxItems: 2 } },
      checker: { type: "object", required: ["checked", "ok", "failures"], additionalProperties: false, properties: { checked: { type: "integer", minimum: 0 }, ok: { const: true }, failures: { const: 0 } } },
    },
  }),
  rules: doc("rules", "G0 rule set as data (spec §13, D-022 names)", {
    type: "object", required: ["ruleset", "version", "facts", "rules"], additionalProperties: false,
    properties: {
      ruleset: { const: "G0-RULESET-v1" }, version: { type: "integer", minimum: 1 }, comment: { type: "string" },
      facts: { type: "object", propertyNames: { pattern: "^[a-z][a-z0-9_]*$" }, additionalProperties: { type: "object", required: ["arity", "doc"], additionalProperties: false, properties: { arity: { type: "integer", minimum: 1 }, doc: { type: "string" } } } },
      rules: { type: "array", minItems: 1, items: { type: "object", required: ["name", "stratum", "head", "body"], additionalProperties: false,
        properties: { name: { type: "string", pattern: "^[a-z][a-z0-9_]*$" }, stratum: { type: "integer", minimum: 0 }, doc: { type: "string" }, reports: { type: "string", pattern: "^[A-Z][A-Z0-9_]*$" },
          head: { type: "object", required: ["rel", "args"], additionalProperties: false, properties: { rel: { type: "string", pattern: "^[a-z][a-z0-9_]*$" }, args: { type: "array", items: { type: "string" } } } },
          body: { type: "array", minItems: 1, items: { type: "object", required: ["rel", "args"], additionalProperties: false, properties: { rel: { type: "string", pattern: "^[a-z][a-z0-9_]*$" }, args: { type: "array", items: { anyOf: [{ type: "string" }, { type: "boolean" }, { type: "null" }, { $ref: "#/$defs/safe_int" }] } }, neg: { type: "boolean" } } } } } } },
    },
  }),
};
for (const [name, schema] of Object.entries(schemas)) writeFileSync(resolve(HERE, name + ".schema.json"), JSON.stringify(schema, null, 1) + "\n");
console.log("wrote", Object.keys(schemas).join(", "));
