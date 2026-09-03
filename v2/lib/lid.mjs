/* lid.mjs — logical identifiers (spec §4.1, §4.3–4.4, D-026).
 *
 * A lid is a NAME, never a content hash: `<prefix>:<namespace>:<local>`. The prefix is one of the closed set below
 * (one per §3.1/§3.2 kind); the namespace names the SOURCE that owns the local id (crosswalk, factory, trvm, …) so
 * colliding identifiers across sources never meet (§3.3: computedriven's compile-fail `f15` is not the finding `F15`;
 * `S1` is an obligation here and a store label there); the local part is ASCII. A local part that cannot be spelled
 * in the grammar is replaced by `h.<sha256 prefix 16>` of its UTF-8 bytes with the raw text kept beside it, and the
 * caller raises a BAD_LID fault — never a silent transliteration.
 */
import { createHash } from "node:crypto";

export const KIND_PREFIX = Object.freeze({
  OBLIGATION: "obligation", ENFORCEMENT_PROPERTY: "eprop", CLAIM: "claim", LAW: "law", MECHANISM: "mechanism",
  DEFINITION: "definition", REPRESENTATION: "representation", PROFILE: "profile", ASSUMPTION: "assumption",
  WITNESS: "witness", FALSIFIER: "falsifier", FINDING: "finding", EXPERIMENT: "experiment", RECEIPT: "receipt",
  ARTIFACT: "artifact", ADJUDICATION: "adjudication", EVIDENCE_STATE_TRANSITION: "transition", ROUND: "round",
  CELL: "cell", REGISTRY: "registry", SOURCE_LOCATION: "loc", FAULT: "fault", PROPOSAL: "proposal",
  RELATION: "rel", ASSERTION: "asrt", SNAPSHOT: "snapshot", ADAPTER_RUN: "run",
});
export const PREFIX_KIND = Object.freeze(Object.fromEntries(Object.entries(KIND_PREFIX).map(([k, v]) => [v, k])));
export const PREFIXES = Object.freeze(Object.values(KIND_PREFIX));

/** Namespaces are lowercase tokens naming a source (or `g0` for what the projector mints). */
export const NAMESPACE_RE = /^[a-z0-9][a-z0-9.-]*$/;
/** The local part: ASCII, no whitespace, no quotes, no control characters. `:` is allowed so relation lids can embed
 *  lids; `/ ~ # %` so JSON pointers and anchors can appear in SOURCE_LOCATION lids. */
export const LOCAL_RE = /^[A-Za-z0-9._/@+~#%:-]+$/;
export const LID_RE = /^([a-z]+):([a-z0-9][a-z0-9.-]*):([A-Za-z0-9._/@+~#%:-]+)$/;

export class LidError extends Error { constructor(code, msg) { super(`${code}: ${msg}`); this.code = code; } }

const h16 = (s) => createHash("sha256").update(Buffer.from(s, "utf8")).digest("hex").slice(0, 16);

/** Build a lid. Returns {lid, kind, namespace, local, fallback, raw?}. */
export function makeLid(kind, namespace, local) {
  const prefix = KIND_PREFIX[kind];
  if (!prefix) throw new LidError("BAD_KIND", `unknown kind ${JSON.stringify(kind)}`);
  if (typeof namespace !== "string" || !NAMESPACE_RE.test(namespace)) throw new LidError("BAD_NAMESPACE", `namespace ${JSON.stringify(namespace)}`);
  if (typeof local !== "string" || local.length === 0) throw new LidError("BAD_LOCAL", `empty local part for ${kind}`);
  if (LOCAL_RE.test(local)) return { lid: `${prefix}:${namespace}:${local}`, kind, namespace, local, fallback: false };
  const fb = "h." + h16(local);
  return { lid: `${prefix}:${namespace}:${fb}`, kind, namespace, local: fb, fallback: true, raw: local };
}

/** Parse a lid back into its parts (the local part may itself contain `:`). */
export function parseLid(s) {
  if (typeof s !== "string") throw new LidError("BAD_LID", "not a string");
  const m = LID_RE.exec(s);
  if (!m) throw new LidError("BAD_LID", `does not match the lid grammar: ${JSON.stringify(s).slice(0, 120)}`);
  const kind = PREFIX_KIND[m[1]];
  if (!kind) throw new LidError("BAD_LID", `unknown prefix ${m[1]} in ${s}`);
  return { lid: s, kind, prefix: m[1], namespace: m[2], local: m[3] };
}
export const isLid = (s) => { try { parseLid(s); return true; } catch { return false; } };

/** The RELATION KINDS of spec §3.2 — closed. */
export const RELATION_KINDS = Object.freeze([
  "STATES", "IMPLEMENTS", "DERIVES_FROM", "REDUCES_TO", "REFINES", "SPLIT_FROM", "SUPERSEDES", "RETRACTS", "REQUIRES",
  "WITNESSES", "SUPPORTS", "FALSIFIES", "ATTACKS", "TESTED_UNDER", "SCOPED_BY", "ASSUMES", "CLOSES", "OPENS",
  "PRODUCED_BY", "ADJUDICATED_BY", "LOCATED_IN", "MEMBER_OF", "BINDS", "CITES", "INDEPENDENT_OF", "CONFLICTS_WITH",
  "EQUIVALENT_TO",
  // D-027: the crosswalk's `definition` / `representation` / `cross-cutting` relation values need their own kinds
  "DEFINES", "REPRESENTS", "CROSS_CUTS",
  // D-037 (the D-034 ruling, GPT adjudication v3 2026-09-03): a transition MOVES THE STATE OF a claim, it does not
  // replace it — transition → claim is STATE_TRANSITION_OF, never SUPERSEDES.
  "STATE_TRANSITION_OF",
]);
/** ENDPOINT CONSTRAINTS the kernel of G0 enforces at emission AND projection time (D-037). `SUPERSEDES` is frozen as a
 *  REPLACEMENT relation between semantically comparable entities — claim → claim, revision → revision, round → round,
 *  transition → transition — and only when a source explicitly states it; it is never inferred from temporal order.
 *  `STATE_TRANSITION_OF` is the transition → claim edge. Any other endpoint pair for these kinds is refused with
 *  ENDPOINT_REFUSED; a projection can therefore never silently contain a transition → claim SUPERSEDES. Kinds are
 *  derived from the lid prefix (parseLid(...).kind), so the check needs no lookup. The world profile
 *  (handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json) states the same pairs in its `endpoint_constraints`. */
export const RELATION_ENDPOINTS = Object.freeze({
  SUPERSEDES: Object.freeze([["CLAIM", "CLAIM"], ["ROUND", "ROUND"], ["EVIDENCE_STATE_TRANSITION", "EVIDENCE_STATE_TRANSITION"]]),
  STATE_TRANSITION_OF: Object.freeze([["EVIDENCE_STATE_TRANSITION", "CLAIM"]]),
});
export function checkRelationEndpoints(kind, sourceLid, targetLid) {
  const pairs = RELATION_ENDPOINTS[kind]; if (!pairs) return true;
  const s = parseLid(sourceLid).kind, t = parseLid(targetLid).kind;
  if (pairs.some(([a, b]) => a === s && b === t)) return true;
  throw new LidError("ENDPOINT_REFUSED", `${kind} ${s} → ${t} is not an allowed endpoint pair (D-037: ${pairs.map(([a, b]) => `${a}→${b}`).join(", ")}); ${sourceLid} → ${targetLid}`);
}
/** RELATION IDENTITY (spec §4.3 as amended by D-029, GPT Adjudication v2 Q1). A relation is the PROPOSITION
 *  `(kind, source, target[, explicit semantic qualifier])`. Every source occurrence that states it — a citation from
 *  one JSON pointer, a receipt listed once as a sensitivity witness and once as a repair witness, two registries
 *  quoting one sentence — is an ASSERTION on that one relation, never a second relation. Citation location is
 *  therefore NOT part of relation identity for any kind. The pre-B.1 `REPEATABLE_RELATION_KINDS` (one relation per
 *  citation for WITNESSES/SUPPORTS/FALSIFIES/ATTACKS/CITES/LOCATED_IN/ADJUDICATED_BY/PRODUCED_BY) is withdrawn.
 *
 *  A field that truly changes the proposition (not merely describes one citation of it) must be promoted to a TYPED
 *  SEMANTIC QUALIFIER declared here per kind, spelled `<name>=<value>`; an undeclared qualifier is refused, never
 *  improvised. The table is EMPTY at B.1: no field of the first source was found to change a proposition (D-029 lists
 *  the candidates examined — `role`, `part`, `what`, `outcome`, `section` — and why each is occurrence metadata). */
export const RELATION_QUALIFIERS = Object.freeze({});
export const QUALIFIER_RE = /^[a-z][a-z0-9_]*=[A-Za-z0-9._/@+~#%-]+$/;

/** `rel:g0:<KIND>:<source lid>:<target lid>[:<name=value>]` — a name; the parts are stored as fields on the record. */
export function relationLid(kind, sourceLid, targetLid, qualifier = null) {
  if (!RELATION_KINDS.includes(kind)) throw new LidError("BAD_RELATION_KIND", `${kind}`);
  parseLid(sourceLid); parseLid(targetLid); checkRelationEndpoints(kind, sourceLid, targetLid);
  if (qualifier !== null) {
    const declared = RELATION_QUALIFIERS[kind];
    if (!declared) throw new LidError("QUALIFIER_NOT_ALLOWED", `${kind} declares no semantic qualifier (D-029); citation metadata belongs on the assertion`);
    if (typeof qualifier !== "string" || !QUALIFIER_RE.test(qualifier) || !declared.includes(qualifier.split("=")[0])) throw new LidError("QUALIFIER_UNDECLARED", `${kind}: ${JSON.stringify(qualifier)} is not one of ${declared.join(", ")}`);
  }
  return `rel:g0:${kind}:${sourceLid}:${targetLid}` + (qualifier ? `:${qualifier}` : "");
}
/** Context-bound anonymous identity (D-030, GPT Adjudication v2 Q1b): an unnamed statement is identified by the
 *  nearest authoritative semantic CONTAINER that owns it plus its exact source sentence — never by the sentence alone,
 *  so one sentence under two containers is two things, and two registries quoting one sentence under one container
 *  meet. Input = TAG ‖ 0x00 ‖ UTF-8(container lid) ‖ 0x00 ‖ UTF-8(sentence); NUL cannot occur in a lid or a G0 string
 *  (§6.2), so the encoding is injective. Two byte-identical sentences in ONE container's list co-refer by design (the
 *  list ordinal is deliberately not identity, so reordering a list renames nothing). The sentence is the source JSON string value exactly (no case folding, no whitespace
 *  normalization, no LLM rewording). */
export const CONTEXT_BOUND_TAG = "G0-CONTEXT-BOUND-LID-v1";
export function contextBoundLid(kind, namespace, containerLid, sentence) {
  parseLid(containerLid);
  if (typeof sentence !== "string" || sentence.length === 0) throw new LidError("BAD_LOCAL", "empty sentence");
  // a fixed domain tag first (the Git / DSSE / RFC 6962 discipline, R9 §B): this hash can never collide with a hash of
  // the same bytes taken for another purpose; NUL-separated because neither a lid nor a G0 string may contain NUL
  const digest = createHash("sha256").update(Buffer.concat([Buffer.from(CONTEXT_BOUND_TAG, "utf8"), Buffer.from([0]), Buffer.from(containerLid, "utf8"), Buffer.from([0]), Buffer.from(sentence, "utf8")])).digest("hex");
  return makeLid(kind, namespace, "h." + digest.slice(0, 16)).lid;
}
/** `asrt:<subject lid>:<source location lid>` */
export function assertionLid(subjectLid, locLid) { parseLid(subjectLid); parseLid(locLid); return `asrt:g0:${subjectLid}:${locLid}`; }

/** Mint a SOURCE_LOCATION lid: registry lid, pinned identity (git OID or sha256:…), path, and an optional fragment
 *  (`#/json/pointer`, `#heading-anchor`, `#L12-L40`). */
export function locationLid(registryNamespace, pinnedIdentity, path, fragment = null) {
  const local = `${pinnedIdentity}:${path}` + (fragment ? `#${fragment}` : "");
  return makeLid("SOURCE_LOCATION", registryNamespace, local);
}

/** A table that refuses two DIFFERENT contents under one lid (spec §4.6) and is idempotent for identical content. */
export class LidTable {
  constructor() { this.map = new Map(); }
  /** Returns "new" | "same" ; throws LidError DUPLICATE_ID when the hash differs. */
  add(lid, contentHash) {
    parseLid(lid);
    const prev = this.map.get(lid);
    if (prev === undefined) { this.map.set(lid, contentHash); return "new"; }
    if (prev === contentHash) return "same";
    throw new LidError("DUPLICATE_ID", `${lid} already holds ${prev}, refusing ${contentHash}`);
  }
  has(lid) { return this.map.has(lid); }
  get size() { return this.map.size; }
}
