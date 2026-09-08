/* linkage.mjs — G1 LINKAGE: derived cross-family identity resolution (GPT Adjudication v7 §8 → D-076).
 *
 * THE ONTOLOGY CORRECTION THIS LAYER EXISTS FOR. The first G1 round reported 13
 * `CROSS_REGISTRY_COREFERENCE_UNLINKED` cases as consistency findings. They are not contradictions, not drift, not
 * stale coordinates, and not genuinely unresolved references: both source families are present and deterministically
 * name the SAME EXACT EXTERNAL QUALIFIED IDENTITY. What was missing was a Graphonomous-derived cross-family link —
 * and neither authoritative source should be forced to own that edge. So the architecture is three layers, not two:
 *
 *     projection    observed source-specific records          (the sources own these)
 *         ↓
 *     linkage       derived cross-family identity resolution  (GRAPHONOMOUS owns this, as derived knowledge)
 *         ↓
 *     consistency   actual disagreement / staleness / unresolved cases
 *
 * WHAT A LINK MEANS, AND ONLY THIS:
 *
 *   > these two source-specific records independently name the same exact external qualified identity under
 *   > deterministic source grammars.
 *
 * It is NOT `EQUIVALENT_TO` in every semantic attribute. It is NOT a source-authored relation. It is NOT authority to
 * merge or fold the nodes. It is NOT permission to rewrite either source. Each node keeps its own lid, its own
 * attributes, and its own source.
 *
 * THE SPELLING, DELIBERATELY NOT AN ADMITTED WRL RELATION KIND. `COREFERS_WITH` is not one of the 32 kinds
 * `graphonomous.semantic.v2` admits, and it must not become one. A linkage record is DERIVED and lives under its own
 * root, outside the projection and outside WRL sealing — exactly like a consistency finding. Minting it as a
 * projection relation would (a) put a Graphonomous inference inside the observed record set, and (b) require a
 * semantic.v3 obligation for a statement no source ever made. The closest admitted kind, `EQUIVALENT_TO [CLAIM,
 * CLAIM]`, means something stronger and different, which is why it is not reused.
 *
 * REFUSAL RATHER THAN GUESSING. If one namespace carries the same external identity on two or more nodes, the
 * canonical target is ambiguous and NO link is emitted — the ambiguity is recorded so a consistency rule can decide
 * whether it is reportable. If an external identity has no owning target at all, that is not a link either;
 * `LAW_REFERENCE_UNRESOLVED` in the consistency layer already covers the current law case.
 */
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { canonicalBytesG0, sha256Hex, sortSet, artifactRoot } from "./canon.mjs";

const H = (b) => sha256Hex(Buffer.isBuffer(b) ? b : Buffer.from(b, "utf8"));
export const RULEPACK_ID = "graphonomous.linkage.rules.v0";
/** The derived relation label. Lives in THIS layer only — see the header. */
export const LINK_RELATION = "COREFERS_WITH";

export const RULES = Object.freeze([
  { id: "EXACT_EXTERNAL_COREFERENCE", version: 1, relation: LINK_RELATION,
    states: "Two source-specific records in different source families carry the same exact external qualified identity, each under its own source's deterministic grammar. The link resolves them to one external identity; it does not merge them, equate their attributes, or give either source authority over the other.",
    refuses: "A namespace carrying the identity on more than one node makes the canonical target ambiguous; no link is emitted and the ambiguity is recorded instead of guessed. An identity with no owning target is not a link either — an unresolved-reference consistency rule covers that.",
    evidence: "each side's `citation` attribute, and the source location of the assertion that carries it" },
]);

/** A premise is an OBSERVED thing: a record lid with the source location that asserted it. */
const premise = (p) => ({ kind: p.kind, ref: p.ref, ...(p.at ? { at: p.at } : {}), ...(p.observed !== undefined ? { observed: p.observed } : {}) });

/** `clink-`: content-bound over (rulepack, rule, version, snapshot, external identity, canonical sorted endpoints). */
export function linkageId(l) {
  return "clink-" + H(canonicalBytesG0({
    rulepack: RULEPACK_ID, rule: l.rule, rule_version: l.rule_version, snapshot: l.snapshot,
    external_identity: l.external_identity, endpoints: [...l.endpoints].sort(),
  }));
}

/**
 * Derive the links. `ctx` is the consistency layer's context (same observed inputs, same discipline).
 * Returns `{ links, ambiguous, counts }`.
 */
export function runLinkage(ctx) {
  const spec = RULES[0];
  /* group every node carrying an external `citation` by (identity → namespace → [nodes]) */
  const byIdentity = new Map();
  for (const n of ctx.nodes) {
    const c = n.attrs?.citation;
    if (typeof c !== "string" || !c) continue;
    const ns = n.lid.split(":")[1];
    if (!byIdentity.has(c)) byIdentity.set(c, new Map());
    const byNs = byIdentity.get(c);
    if (!byNs.has(ns)) byNs.set(ns, []);
    byNs.get(ns).push(n);
  }

  const links = []; const ambiguous = [];
  for (const [identity, byNs] of [...byIdentity].sort()) {
    if (byNs.size < 2) continue;                                   // one family names it: nothing to link
    const multi = [...byNs].filter(([, ns]) => ns.length > 1);
    if (multi.length) {                                            // REFUSE rather than guess
      ambiguous.push({
        external_identity: identity,
        namespaces: [...byNs.keys()].sort(),
        ambiguous_in: multi.map(([ns, list]) => ({ namespace: ns, candidates: list.map((n) => n.lid).sort() })).sort((a, b) => (a.namespace < b.namespace ? -1 : 1)),
        reason: "more than one node in one source family carries this external identity, so the canonical target is ambiguous; a link would be a guess",
      });
      continue;
    }
    /* exactly one node per family. Link every unordered pair, canonically ordered by lid. */
    const nodes = [...byNs.values()].map(([n]) => n).sort((a, b) => (a.lid < b.lid ? -1 : 1));
    for (let i = 0; i < nodes.length; i++) for (let k = i + 1; k < nodes.length; k++) {
      const [a, b] = [nodes[i], nodes[k]];
      const l = {
        rule: spec.id, rule_version: spec.version, rulepack: RULEPACK_ID, relation: LINK_RELATION,
        snapshot: ctx.where.snapshot, projection_root: ctx.where.projection_root,
        external_identity: identity,
        endpoints: [a.lid, b.lid].sort(),
        families: [a.lid.split(":")[1], b.lid.split(":")[1]].sort(),
        roles: sortSet([{ lid: a.lid, role: a.kind }, { lid: b.lid, role: b.kind }], "roles"),
        premises: sortSet([a, b].map((n) => premise({ kind: "node", ref: n.lid, at: ctx.firstLocation(n.lid), observed: { role: n.kind, citation: identity } })), "premises"),
        explain: [
          `${a.lid} (role ${a.kind}) carries citation ${identity}, asserted from ${ctx.firstLocation(a.lid) ?? "an unrecorded location"}`,
          `${b.lid} (role ${b.kind}) carries citation ${identity}, asserted from ${ctx.firstLocation(b.lid) ?? "an unrecorded location"}`,
          `Each source family states this identity itself, under its own grammar; exactly one node in each family carries it, so the resolution is not a guess.`,
          `${LINK_RELATION} means ONLY that these two records name one external identity. It does not merge them, does not claim their attributes are equivalent, and gives neither source authority over the other. Graphonomous owns this link as derived knowledge.`,
        ],
        basis: "derived", trvm_derivation: false, authority: "none",
      };
      l.lid = linkageId(l);
      links.push(l);
    }
  }
  const sorted = sortSet(links, "links");
  return { links: sorted, ambiguous: sortSet(ambiguous, "ambiguous"), counts: { [spec.id]: sorted.length, ambiguous: ambiguous.length } };
}

/** Write `<dir>/linkage/` — its OWN root, derived, never a member of the projection root. */
export function writeLinkage(dir, ctx, out = join(dir, "linkage")) {
  const r = runLinkage(ctx);
  const manifest = {
    kind: "g0-linkage", rulepack: RULEPACK_ID, relation: LINK_RELATION,
    snapshot: ctx.where.snapshot, projection_root: ctx.where.projection_root,
    rules: RULES.map((x) => ({ id: x.id, version: x.version, relation: x.relation })),
    counts: Object.entries(r.counts).sort(),
    entries: sortSet(r.links.map((l) => [l.lid, "sha256:" + H(canonicalBytesG0(l))]), "entries"),
    ambiguous: r.ambiguous,
    count: r.links.length,
    means: "two source-specific records independently name the same exact external qualified identity under deterministic source grammars",
    does_not_mean: ["semantic equivalence of attributes", "a source-authored relation", "authority to merge or fold the nodes", "permission to rewrite either source"],
    scope: { authority: "none", basis: "derived", trvm_derivation: false, nodes_merged: 0, registry_written: false },
  };
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "links.jsonl"), r.links.map((l) => canonicalBytesG0(l).toString("utf8")).join("\n") + (r.links.length ? "\n" : ""));
  writeFileSync(join(out, "manifest.json"), canonicalBytesG0(manifest));
  const root = artifactRoot(manifest);
  writeFileSync(join(out, "ROOT"), root + "\n");
  return { ...r, root, manifest };
}

/** Read a written linkage layer back, or null. Used by the consistency layer and the inspector build. */
export function readLinkage(dir, at = join(dir, "linkage")) {
  if (!existsSync(join(at, "manifest.json"))) return null;
  return {
    root: readFileSync(join(at, "ROOT"), "utf8").trim(),
    manifest: JSON.parse(readFileSync(join(at, "manifest.json"), "utf8")),
    links: readFileSync(join(at, "links.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)),
  };
}
