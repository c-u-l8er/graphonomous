/* closure.mjs — the REQUIRED SCHEMA CLOSURE for `GRAPHONOMOUS-PROJECTION-v1` (GPT Adjudication v6 §6, D-068).
 *
 * WHAT v0 BOUND, AND WHY IT WAS WRONG. `schemaSetId()` hashes every `schemas/*.schema.json` in the checkout, keyed on
 * BASENAME. So adding v1 vocabulary re-minted the certificates of frozen v0 projections whose source bytes, roots,
 * commitments and records had not moved; and a rename of a schema the projection DOES use would move the id even
 * though the schema resource did not change. v0 keeps that meaning — narrowing it inside v0 would break the D-060
 * freeze. v1 replaces it.
 *
 * WHAT v1 BINDS. The exact versioned schema artifacts the VERIFIER determines are required by the projection's active,
 * trusted contracts:
 *
 *     the projection's own adapter_run records          →  which adapters ran        (artifact-supplied SELECTOR)
 *     contracts/projection.v1.json                      →  what that IMPLIES          (local, trusted CONTRACT)
 *     schemas/*.schema.json indexed by $id              →  the artifacts themselves   (local, content-addressed)
 *
 * This is in-toto's link/layout split (R16 §4): the artifact says what it DID; a versioned local contract says what
 * that implies. The bundle can select a point in the contract's space and can never supply or widen the space —
 * `requiredSchemaClosure` is not given the bundle as a parameter, so it is structurally unable to read it (D-068 law
 * 8). A bundle that carries a closure of its own is COMPARED against this derivation, never consumed as input.
 *
 * IDENTITY. Logical identity is the schema's `$id` (all twelve already carry one); the version is its content digest.
 * The pair is R16's ADOPT from OCI descriptors and in-toto ResourceDescriptors. Keying on `$id` rather than basename
 * makes the closure PATH-INDEPENDENT — moving `schemas/node.schema.json` no longer moves the id. That is correct
 * (logical identity is not location) and it is a deliberate behaviour change from v0.
 *
 * ORDER AND DUPLICATES. Members are sorted by `$id` INSIDE the hash function, so no caller can move the id by changing
 * traversal order (law 6), and a strict-increase assertion runs immediately before hashing so a duplicate reaching the
 * hasher crashes rather than quietly collapsing. Duplicate logical identity is refused at INDEX time — even when the
 * two files are byte-identical, because two files that agree today can diverge tomorrow, and at that moment the
 * closure would become order-dependent (law 7).
 *
 * THE `$ref` SWEEP IS VACUOUS TODAY, AND IS IMPLEMENTED ANYWAY. Measured: every `$ref` in all twelve schemas is a
 * local `#/$defs/...` pointer, because `schemas/build_schemas.mjs` INLINES `common.schema.json`'s `$defs` into each
 * output. So a $ref-derived closure would return {self} for every schema and discriminate nothing (R16 §0a). The
 * declared roots are the source of the closure; the sweep exists so that the day someone writes a real cross-document
 * `$ref` it is pulled in rather than silently omitted (protoc `--include_imports`, R16 §1).
 *
 * WHAT THIS DOES NOT SOLVE — stated, not papered over:
 *   · def granularity. Because the generator inlines `common.$defs` everywhere, changing one shared def moves the
 *     bytes of all twelve schemas, so every closure that touches any schema re-mints — even one that never used the
 *     changed def. Law 2 (an unrelated new FILE) holds; "an unrelated def changed" does not, and cannot without
 *     abandoning the inlining for genuine cross-file `$ref`s. That is a v2 move (R16 §6 Q2).
 *   · a read-only verifier cannot observe what the producer actually LOADED, only recompute what the contract implies.
 *   · there is no cryptographic trust boundary: producer and verifier are one codebase. The guarantee is that the
 *     closure cannot change without moving a pinned code identity — the same strength `adapter_contract_id` claims.
 */
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalBytesG0, sha256Hex, G0Error } from "./canon.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(HERE, "..");
const H = (...parts) => sha256Hex(Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : Buffer.from(p, "utf8")))));

export const CONTRACT_FILE = "contracts/projection.v1.json";
export const SCHEMA_DIR = "schemas";

/** Refusal codes this module raises. They surface through the certificate as `gproj-schema-closure-refused`. */
export const CLOSURE_CODES = Object.freeze([
  "gschema-no-id", "gschema-duplicate-id", "gschema-unresolved", "gschema-unknown-adapter", "gschema-unknown-kind",
  "gschema-contract-malformed",
]);

class ClosureRefusal extends G0Error {
  constructor(code, detail) { super("SCHEMA_CLOSURE_REFUSED", `${code}: ${detail}`); this.closure_code = code; this.detail = detail; }
}
const refuse = (code, detail) => { throw new ClosureRefusal(code, detail); };

/** The trusted local contract, read from disk. Never from a bundle. */
export function loadContract(file = CONTRACT_FILE) {
  const path = resolve(ROOT_DIR, file);
  if (!existsSync(path)) refuse("gschema-contract-malformed", `${file} is not on disk`);
  let c; try { c = JSON.parse(readFileSync(path, "utf8")); } catch (e) { refuse("gschema-contract-malformed", `${file} does not parse: ${String(e.message).split("\n")[0]}`); }
  for (const k of ["contract_version", "record_kinds", "structural", "ruleset", "adapters"])
    if (c[k] === undefined) refuse("gschema-contract-malformed", `${file} has no ${k}`);
  return c;
}

/**
 * Index `schemas/*.schema.json` by LOGICAL identity. A file with no `$id` is unaddressable and refuses; a second file
 * claiming an existing `$id` refuses even when the bytes are identical (law 7 lands HERE, not in the hasher).
 */
export function schemaIndex(dir = SCHEMA_DIR) {
  const abs = resolve(ROOT_DIR, dir);
  const byId = new Map();
  for (const f of readdirSync(abs).filter((n) => n.endsWith(".schema.json")).sort()) {
    const bytes = readFileSync(join(abs, f));
    let doc; try { doc = JSON.parse(bytes.toString("utf8")); } catch (e) { refuse("gschema-contract-malformed", `${dir}/${f} does not parse: ${String(e.message).split("\n")[0]}`); }
    const id = doc?.$id;
    if (typeof id !== "string" || !id) refuse("gschema-no-id", `${dir}/${f} declares no $id, so it has no logical identity`);
    const prev = byId.get(id);
    if (prev) refuse("gschema-duplicate-id", `${id} is declared by ${prev.file} and by ${dir}/${f}${prev.digest === "sha256:" + sha256Hex(bytes) ? " (byte-identical — still refused: two files that agree today can diverge tomorrow)" : ""}`);
    byId.set(id, { file: `${dir}/${f}`, digest: "sha256:" + sha256Hex(bytes), doc });
  }
  return byId;
}

/** Every `$ref` in a document that leaves the document (i.e. is not a local `#/...` pointer). */
function externalRefs(node, out = []) {
  if (!node || typeof node !== "object") return out;
  if (Array.isArray(node)) { for (const x of node) externalRefs(x, out); return out; }
  for (const [k, v] of Object.entries(node)) {
    if (k === "$ref" && typeof v === "string" && !v.startsWith("#")) out.push(v);
    else externalRefs(v, out);
  }
  return out;
}

/**
 * The required closure, as sorted `[$id, digest]` pairs.
 * `selector` is `{ adapters: string[] , ruleset: boolean }` — derived from the projection directory, never the bundle.
 */
export function requiredSchemaClosure(index, contract, selector) {
  const kinds = new Set();
  for (const uri of [...selector.adapters].sort()) {
    const a = contract.adapters[uri];
    if (!a) refuse("gschema-unknown-adapter", `the projection ran ${uri}, which ${CONTRACT_FILE} does not declare — a projection may not activate an adapter the contract has never seen`);
    for (const k of a.emits) kinds.add(k);
  }
  const roots = [];
  for (const k of [...kinds].sort()) {
    const id = contract.record_kinds[k];
    if (!id) refuse("gschema-unknown-kind", `an adapter declares it emits ${JSON.stringify(k)}, which ${CONTRACT_FILE} maps to no schema`);
    roots.push(id);
  }
  roots.push(...contract.structural);
  if (selector.ruleset) roots.push(...contract.ruleset);

  /* declared roots, then a transitive external-$ref sweep (vacuous today; see the header) */
  const members = new Map(); const stack = [...roots];
  while (stack.length) {
    const id = stack.pop();
    const e = index.get(id);
    if (!e) refuse("gschema-unresolved", `${id} is required by the contract and is not declared by any schema on disk`);
    const seen = members.get(id);
    if (seen !== undefined) { if (seen !== e.digest) refuse("gschema-duplicate-id", `${id} resolved to two different digests in one closure`); continue; }
    members.set(id, e.digest);
    for (const r of externalRefs(e.doc)) stack.push(new URL(r, id).toString().split("#")[0]);
  }
  const sorted = [...members].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  for (let i = 1; i < sorted.length; i++) if (sorted[i][0] === sorted[i - 1][0]) refuse("gschema-duplicate-id", `${sorted[i][0]} reached the hasher twice`);
  return sorted;
}

/** `gschema-`: the content identity of the closure. Sorting happens in requiredSchemaClosure, before this is called. */
export const schemaClosureId = (members) => "gschema-" + H(canonicalBytesG0(members));

/** `gpcon-`: contract version + the ACTIVE adapter set + the closure it implies. Moves when an adapter is activated
 *  even if the closure does not — see the law-5 sharpening in D-072. */
export const projectionContractId = (contract, activeAdapters, closureId) =>
  "gpcon-" + H(canonicalBytesG0([contract.contract_version, [...activeAdapters].sort(), closureId]));

/**
 * The whole derivation, from a projection's own adapter_run records and its manifest. Returns
 * `{ closure_id, contract_id, members, adapters, contract_version, problems }`; `problems` is a list of
 * `{code, detail}` rather than a throw, so a checker can still say which coordinate disagreed.
 */
export function deriveClosure(runs, { ruleset = true, contractFile = CONTRACT_FILE, schemaDir = SCHEMA_DIR } = {}) {
  const problems = [];
  try {
    const contract = loadContract(contractFile);
    const index = schemaIndex(schemaDir);
    const adapters = [...new Set(runs.map((r) => {
      const uri = r?.adapter?.uri ?? "";
      return uri.startsWith("file:") ? uri.slice(5) : uri;
    }))].sort();
    const members = requiredSchemaClosure(index, contract, { adapters, ruleset });
    const closure_id = schemaClosureId(members);
    return { closure_id, contract_id: projectionContractId(contract, adapters, closure_id), members, adapters, contract_version: contract.contract_version, indexed: index.size, problems };
  } catch (e) {
    problems.push({ code: e.closure_code ?? "gschema-contract-malformed", detail: e.detail ?? String(e?.message ?? e) });
    return { closure_id: null, contract_id: null, members: [], adapters: [], contract_version: null, indexed: 0, problems };
  }
}
