/* emit.mjs — what an adapter produces: ASSERTIONS about nodes and relations, plus faults. The projector folds many
 * assertions into one node or relation (spec §4.3–4.4: one statement, many assertions); an adapter never merges,
 * never guesses, and never writes a registry. Lids are minted through lid.mjs; a local part outside the grammar is
 * percent-encoded when short and hashed when long, and the raw text is always kept (D-026). */
import { createHash } from "node:crypto";
import { makeLid, relationLid, assertionLid, locationLid, parseLid, RELATION_KINDS } from "./lid.mjs";

const SAFE_LOCAL = /[A-Za-z0-9._/@+~#:-]/;
/** Percent-encode a local part deterministically (RFC 3986 style, uppercase hex); `%` itself is encoded. */
export function encodeLocal(raw) {
  let out = "";
  for (const ch of String(raw)) {
    if (SAFE_LOCAL.test(ch) && ch !== "%") out += ch;
    else for (const b of Buffer.from(ch, "utf8")) out += "%" + b.toString(16).toUpperCase().padStart(2, "0");
  }
  return out;
}
const h16 = (s) => createHash("sha256").update(Buffer.from(s, "utf8")).digest("hex").slice(0, 16);

export class Emitter {
  constructor({ snapshot, registry, namespace, pinned_identity, path, treeRegistries = {} }) {
    this.snapshot = snapshot; this.registry = registry; this.namespace = namespace; this.pinned = pinned_identity; this.path = path;
    /** namespace → the registry lid of the pinned TREE a foreign location lives in (from the snapshot), so a location's
     *  `registry` is a function of where the file is, never of which emitter cited it first. */
    this.treeRegistries = treeRegistries;
    this.nodes = []; this.relations = []; this.faults = []; this.locations = new Map(); this.faultSeq = new Map(); this._byAsrt = new Map();
  }
  /** Mint a lid for a kind in a namespace; long or unspellable locals hash (raw kept by the caller in attrs). */
  lid(kind, namespace, local) {
    const enc = encodeLocal(local);
    if (enc.length <= 120) { const r = makeLid(kind, namespace, enc); if (!r.fallback) return r.lid; }
    return makeLid(kind, namespace, "h." + h16(String(local))).lid;
  }
  /** A source location in a pinned file. PRECISION IS A FUNCTION OF THE FRAGMENT so the record is a pure function
   *  of its lid: `/…` → pointer, `L<n>` → line (or `symbol` when the caller verified a symbol there), other text →
   *  heading, none → file. An empty pointer ("" — the whole document) is the file. */
  loc(fragment, precision = null, { path = this.path, pinned = this.pinned, namespace = this.namespace } = {}) {
    if (fragment === "" || fragment === undefined) fragment = null;
    const computed = fragment == null ? "file" : fragment.startsWith("/") ? "pointer" : /^L\d+(-L?\d+)?$/.test(fragment) ? (precision === "symbol" ? "symbol" : "line") : "heading";
    const { lid } = locationLid(namespace, pinned, encodeLocal(path), fragment == null ? null : encodeLocal(fragment));
    const registry = this.treeRegistries[namespace] ?? this.registry;
    if (!this.locations.has(lid)) this.locations.set(lid, { lid, kind: "SOURCE_LOCATION", registry, pinned_identity: pinned, path, ...(fragment ? { fragment } : {}), precision: computed, snapshot: this.snapshot });
    else if (precision === "symbol" && this.locations.get(lid).precision === "line") this.locations.get(lid).precision = "symbol";
    return lid;
  }
  /** Two assertions with one lid must be one assertion: merge attrs; a conflicting key is an adapter bug, thrown. */
  _dedupe(list, item) {
    const prev = this._byAsrt.get(item.assertion.lid);
    if (!prev) { this._byAsrt.set(item.assertion.lid, item); list.push(item); return item; }
    for (const [k, v] of Object.entries(item.attrs || {})) {
      if (!(k in prev.attrs)) prev.attrs[k] = v;
      else if (JSON.stringify(prev.attrs[k]) !== JSON.stringify(v)) throw new Error(`emitter: ${item.assertion.lid} asserted twice with different ${k}: ${JSON.stringify(prev.attrs[k]).slice(0, 80)} vs ${JSON.stringify(v).slice(0, 80)}`);
    }
    if (item.assertion.attrs) { prev.assertion.attrs = prev.assertion.attrs || {}; for (const [k, v] of Object.entries(item.assertion.attrs)) { if (!(k in prev.assertion.attrs)) prev.assertion.attrs[k] = v; else if (JSON.stringify(prev.assertion.attrs[k]) !== JSON.stringify(v)) throw new Error(`emitter: ${item.assertion.lid} extra ${k} conflicts`); } }
    return prev;
  }
  /** Assert a node. `at` is a location lid (from loc()); `attrs` are this assertion's contribution. */
  node(kind, lid, attrs, at, { precision = "pointer", extra = {} } = {}) {
    parseLid(lid);
    const prec = this.locations.get(at)?.precision || precision;
    this._dedupe(this.nodes, { lid, kind, attrs: { ...(attrs || {}) }, assertion: { lid: assertionLid(lid, at), subject: lid, location: at, asserted_by: this.registry, precision: prec, snapshot: this.snapshot, ...(Object.keys(extra).length ? { attrs: extra } : {}) } });
    return lid;
  }
  /** Assert a relation (D-029). The relation is the PROPOSITION `(kind, source, target)`; `attrs` are the few fields
   *  true of the proposition itself (the source's spelling of the kind, a transition's from/to text). Everything that
   *  describes THIS OCCURRENCE — role, outcome, what, part, note, the citing token, wording — goes in `asrt` and lands
   *  on the assertion record, so two citations of one statement are one relation with two assertions. A `qualify`
   *  must be a declared typed semantic qualifier (lid.mjs RELATION_QUALIFIERS); the emitter never derives one from
   *  the location. */
  rel(kind, source, target, at, { attrs = {}, asrt = {}, precision = "pointer", qualify = null } = {}) {
    if (!RELATION_KINDS.includes(kind)) throw new Error(`unknown relation kind ${kind}`);
    // D-037: relationLid() refuses a SUPERSEDES / STATE_TRANSITION_OF whose endpoint kinds (from the lid prefixes) are
    // not an allowed pair (LidError ENDPOINT_REFUSED) — a transition → claim SUPERSEDES cannot be emitted at all.
    if (typeof at !== "string") throw new Error(`emitter.rel(${kind}): the 4th argument is the asserting location lid (B.1 signature)`);
    const lid = relationLid(kind, source, target, qualify);
    const prec = this.locations.get(at)?.precision || precision;
    this._dedupe(this.relations, { lid, kind, source, target, ...(qualify ? { qualifier: qualify } : {}), attrs: { ...attrs }, assertion: { lid: assertionLid(lid, at), subject: lid, location: at, asserted_by: this.registry, precision: prec, snapshot: this.snapshot, ...(Object.keys(asrt).length ? { attrs: { ...asrt } } : {}) } });
    return lid;
  }
  /** A typed fault attached to what it concerns. Lids are `fault:<ns>:<CODE>:<n>` in emission order, which the
   *  projector re-sorts by content; the sequence exists only so two faults with one message stay distinct. */
  fault(code, rule, message, concerns = [], extra = {}) {
    const n = (this.faultSeq.get(code) || 0) + 1; this.faultSeq.set(code, n);
    const lid = makeLid("FAULT", this.namespace, `${code}:${n}`).lid;
    this.faults.push({ lid, code, rule, message, concerns: [...new Set(concerns)].sort(), snapshot: this.snapshot, ...extra });
    return lid;
  }
  output() { return { nodes: this.nodes, relations: this.relations, faults: this.faults, locations: [...this.locations.values()] }; }
}
