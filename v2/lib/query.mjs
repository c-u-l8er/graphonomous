/* query.mjs — the six-function G0 query surface (spec §10.1): node · neighbors · path · facts · explain · as_of.
 * One dependency-free ESM module for the CLI, the tests and (later) the page. Every answer is records with lids and
 * identities; prose is the caller's. Nothing here computes a fact the projection and its evaluation do not already
 * hold — `explain` UNFOLDS stored derivations and assertions, it never re-derives.
 *
 * Determinism: every list is sorted (by lid, or by canonical bytes); BFS adjacency is sorted by relation lid so `path`
 * returns the same shortest path on every host. */
import { canonicalBytesG0, sortSet } from "./canon.mjs";
import { loadProjection } from "./evaluation.mjs";

const factKey = (rel, args) => canonicalBytesG0([rel, ...args]).toString("utf8");
const byLid = (a, b) => (a.lid < b.lid ? -1 : a.lid > b.lid ? 1 : 0);
const NODE_KIND = /^[A-Z][A-Z_]*$/;

export class Graph {
  constructor(projection) {
    this.p = projection; this.root = projection.root; this.snapshot = projection.snapshot;
    this.nodes = new Map(projection.nodes.map((n) => [n.lid, n]));
    this.relations = new Map(projection.relations.map((r) => [r.lid, r]));
    this.assertions = new Map(projection.assertions.map((a) => [a.lid, a]));
    this.locations = new Map(projection.locations.map((l) => [l.lid, l]));
    this.out = new Map(); this.in = new Map();
    for (const r of [...projection.relations].sort(byLid)) { if (!this.out.has(r.source)) this.out.set(r.source, []); this.out.get(r.source).push(r); if (!this.in.has(r.target)) this.in.set(r.target, []); this.in.get(r.target).push(r); }
    this.faults = projection.faults.slice().sort(byLid);
    this.derived = projection.derived; // null until g0 eval ran
    this.byRule = new Map();
    if (this.derived) for (const f of this.derived.facts) { if (!this.byRule.has(f.rel)) this.byRule.set(f.rel, []); this.byRule.get(f.rel).push(f); }
    this.ruleNames = new Set(this.byRule.keys());
  }
  /** The record behind a lid — a node, a relation, an assertion or a source location — or null. */
  node(lid) { return this.nodes.get(lid) || this.relations.get(lid) || this.assertions.get(lid) || this.locations.get(lid) || this.faults.find((f) => f.lid === lid) || null; }
  /** Relations touching `lid`: [{relation, other, direction}] — direction ∈ out (lid is the source) · in (lid is the target). */
  neighbors(lid, kind = null, direction = "both") {
    const res = [];
    if (direction === "out" || direction === "both") for (const r of this.out.get(lid) || []) if (!kind || r.kind === kind) res.push({ relation: r, other: r.target, direction: "out" });
    if (direction === "in" || direction === "both") for (const r of this.in.get(lid) || []) if (!kind || r.kind === kind) res.push({ relation: r, other: r.source, direction: "in" });
    return res.sort((a, b) => byLid(a.relation, b.relation));
  }
  /** Shortest undirected path a → b over relations (optionally restricted to `kinds`); [] when a === b; null when none. */
  path(a, b, kinds = null) {
    if (!this.node(a) || !this.node(b)) return null;
    if (a === b) return [];
    const prev = new Map([[a, null]]); const queue = [a];
    while (queue.length) {
      const x = queue.shift();
      for (const { relation, other } of this.neighbors(x, null, "both")) {
        if (kinds && !kinds.includes(relation.kind)) continue;
        if (prev.has(other)) continue;
        prev.set(other, { relation, from: x });
        if (other === b) { const out = []; let cur = b; while (prev.get(cur)) { out.unshift(prev.get(cur).relation); cur = prev.get(cur).from; } return out; }
        queue.push(other);
      }
    }
    return null;
  }
  /** facts(rule name) → derived facts of that rule; facts(NODE_KIND) → nodes; facts(RELATION_KIND) → relations.
   *  `filter` matches top-level fields and `attrs` by canonical equality (e.g. {source: lid}, {attrs: {token_family: "TESTED"}}). */
  facts(what, filter = {}) {
    let items;
    if (this.ruleNames.has(what) || /^[a-z][a-z0-9_]*$/.test(what)) { if (!this.derived) throw new Error(`no evaluation stored for ${this.snapshot}: run g0 eval first`); items = (this.byRule.get(what) || []).slice(); }
    else if (what === "FAULT") items = this.faults.slice();
    else if (NODE_KIND.test(what)) items = [...this.nodes.values()].filter((n) => n.kind === what).concat([...this.relations.values()].filter((r) => r.kind === what));
    else throw new Error(`facts(): ${what} is neither a rule name nor a kind`);
    const eq = (x, y) => canonicalBytesG0(x).equals(canonicalBytesG0(y));
    return items.filter((it) => Object.entries(filter).every(([k, v]) => k === "attrs" ? Object.entries(v).every(([ak, av]) => it.attrs && ak in it.attrs && eq(it.attrs[ak], av)) : k in it && eq(it[k], v))).sort((a, b) => a.lid ? byLid(a, b) : Buffer.compare(canonicalBytesG0([a.rel, ...a.args]), canonicalBytesG0([b.rel, ...b.args])));
  }
  /** Explain a lid (observed record → its assertions and their pinned source locations) or a derived fact
   *  (`[rel, ...args]` or a stored fact record → its derivation tree, unfolding the FIRST derivation of each premise
   *  recursively, base facts rendered with their source, `{absent}` as leaves). Spec §10.3. */
  explain(subject, { maxDepth = 12 } = {}) {
    if (typeof subject === "string") { const rec = this.node(subject); if (!rec) return null; return this._explainRecord(rec); }
    const [rel, ...args] = Array.isArray(subject) ? subject : [subject.rel, ...subject.args];
    const f = this.derived?.byKey.get(factKey(rel, args));
    if (!f) return null;
    return { fact: [rel, ...args], basis: "derived", evaluator: f.evaluator, trvm_derivation: false, depth: f.depth, derivations: f.derivations.map((d) => this._tree(d, maxDepth, new Set([factKey(rel, args)]))) };
  }
  _explainRecord(rec) {
    if (rec.kind === "SOURCE_LOCATION") return { subject: rec.lid, basis: "location", record: rec };
    if (rec.subject) return { subject: rec.lid, basis: "assertion", record: rec, location: this.locations.get(rec.location) || null };
    const assertions = sortSet(rec.assertions || []).map((a) => { const as = this.assertions.get(a); return { lid: a, asserted_by: as.asserted_by, precision: as.precision, ...(as.attrs ? { attrs: as.attrs } : {}), location: this.locations.get(as.location) || { lid: as.location, missing: true } }; });
    return { subject: rec.lid, basis: rec.basis, kind: rec.kind, ...(rec.source ? { source: rec.source, target: rec.target } : {}), attrs: rec.attrs, ...(rec.evidence_state ? { evidence_state: rec.evidence_state } : {}), assertions };
  }
  _tree(d, budget, seen) {
    return { rule: d.rule, conclusion: d.conclusion, depth: d.depth, bindings: d.bindings, premises: d.premises.map((prem) => {
      if (prem && typeof prem === "object" && !Array.isArray(prem)) return { absent: prem.absent, basis: "absent" };
      const [rel, ...args] = prem; const key = factKey(rel, args); const derived = this.derived?.byKey.get(key);
      if (derived) { if (budget <= 0 || seen.has(key)) return { fact: prem, basis: "derived", elided: true }; const s = new Set(seen); s.add(key); return { fact: prem, basis: "derived", ...this._tree(derived.derivations[0], budget - 1, s) }; }
      return { fact: prem, basis: "base", source: this._baseSource(rel, args) };
    }) };
  }
  /** Where a base fact came from: the record it is about, with that record's assertions and locations. */
  _baseSource(rel, args) {
    const lid = args[0]; const rec = this.node(lid);
    if (!rec) return { lid, missing: true };
    if (rel === "asrt" || rel === "aattr") return { lid, basis: "assertion", location: this.locations.get(rec.location) || null, asserted_by: rec.asserted_by, ...(rec.attrs ? { attrs: rec.attrs } : {}) };
    const ex = this._explainRecord(rec); return { lid, kind: rec.kind, basis: rec.basis, assertions: ex.assertions };
  }
}

/** A set of projections keyed by snapshot id; `as_of` never mixes them — each Graph holds exactly one root. */
export class Projections {
  constructor(dirs) { this.graphs = new Map(); for (const d of dirs) { const g = new Graph(loadProjection(d)); if (this.graphs.has(g.snapshot)) throw new Error(`two projections for ${g.snapshot}`); this.graphs.set(g.snapshot, g); } }
  snapshots() { return [...this.graphs.keys()].sort(); }
  as_of(snapshotId) { const g = this.graphs.get(snapshotId); if (!g) throw new Error(`as_of(${snapshotId}): no projection loaded; have ${this.snapshots().join(", ")}`); return g; }
}
export const openGraph = (dir) => new Graph(loadProjection(dir));
