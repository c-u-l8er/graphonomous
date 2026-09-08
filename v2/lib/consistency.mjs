/* consistency.mjs — G1-A: CROSS-REGISTRY CONSISTENCY FINDINGS (GPT Adjudication v6 §10/§12 → D-071).
 *
 * A FINDING IS NOT A FAULT, and the two must never merge:
 *   FAULT               the adapter could not deterministically normalize or resolve a source AS WRITTEN.
 *   CONSISTENCY_FINDING the sources normalized successfully, but an explicit cross-registry rule detects incompatible
 *                       or stale semantic coordinates between them.
 * A fault lives in the projection (it is part of what was observed). A finding lives HERE, under its own root, and is
 * visibly DERIVED: `basis: "derived"`, `trvm_derivation: false`, no authority effect, and no path by which it can
 * promote, rewrite or repair a source. There is no repair button and no proposal object — a write surface is a
 * separate authority milestone that has not been opened.
 *
 * EVERY FINDING CARRIES: a content-bound id, the selected snapshot and projection root, rule id and version, the
 * exact observed premises (record lids and source locations, so `explain` bottoms out in what a source ASSERTED), the
 * affected source families, a deterministic explanation, and its CLASS — because "this old receipt names an older
 * verifier" and "these two registries contradict each other" are different news:
 *   contradiction  two sources assert incompatible things about one subject
 *   drift          one subject is read at two coordinates that are not the same bytes
 *   stale          a historical record names coordinates the live system has moved past — a STATUS, never an
 *                  invalidity claim (GPT v6 §12.5)
 *   unresolved     a structured cross-registry reference has no target under the owning source's contract
 *
 * ORDER INDEPENDENCE. A finding's id is the hash of (rule, version, snapshot, sorted premises). Two equivalent input
 * orders give identical ids, which test/consistency.test.mjs measures by shuffling the record files.
 *
 * WHAT IS NOT A FINDING. Textual similarity is not a contradiction. "GPT thinks these disagree" is not a finding.
 * And ABSENCE IS NOT CONFLICT unless absence is DECIDABLE under the owning source's contract — each rule below states
 * its decidability condition, and a rule with no decidable absence does not emit on absence.
 */
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalBytesG0, sha256Hex, sortSet, artifactRoot } from "./canon.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(HERE, "..");
const H = (b) => sha256Hex(Buffer.isBuffer(b) ? b : Buffer.from(b, "utf8"));
/* TWO rulepacks, and v0 is kept rather than mutated (GPT v7 §11 → D-076).
 *   v0  the six rules of the first G1 round. TESTED PRE-LINKAGE, never frozen. Its roots and its 13
 *       CROSS_REGISTRY_COREFERENCE_UNLINKED findings are preserved as receipts of what the layer saw BEFORE linkage
 *       existed, and `projections/pre-v2/tri/consistency/` is where they live.
 *   v1  the five rules that survive. Exact deterministic co-reference is now REPRESENTED by lib/linkage.mjs, so it is
 *       no longer classified as a source inconsistency. Nothing was added to keep the count at six. */
export const RULEPACK_V0 = "graphonomous.consistency.rules.v0";
export const RULEPACK_V1 = "graphonomous.consistency.rules.v1";
export const RULEPACK_ID = RULEPACK_V1;
export const DEFAULT_RULEPACK = RULEPACK_V1;
export const CLASSES = Object.freeze(["contradiction", "drift", "stale", "unresolved"]);

/* ─────────────────────────── the rules, and the reductions ─────────────────────────── */

/** The v0 rule set, kept intact so its receipts stay reproducible. Do NOT edit it. */
const RULES_V0 = Object.freeze([
  { id: "REFERENCE_TARGET_DRIFT", version: 1, class: "drift",
    states: "One snapshot pins the SAME file of the SAME repository at two different blobs, so two source families read two different versions of one authority.",
    decidable_absence: "n/a — this rule fires only on a positive match of (repo, path) across two source declarations; it never fires on absence." },
  { id: "SOURCE_PIN_DIVERGENCE", version: 1, class: "drift",
    states: "One snapshot names one repository at two different commits. Legal — different source families may legitimately read different revisions — but it is the coordinate a reader must know before comparing anything the two families say.",
    decidable_absence: "n/a — positive match only." },
  { id: "CROSS_REGISTRY_COREFERENCE_UNLINKED", version: 1, class: "unresolved",
    states: "Two source families represent ONE external qualified identity as two separate statements, and no relation in the projection links them. The graph therefore holds the same proposition twice under two names.",
    decidable_absence: "decidable: both statements are present in this projection, and the absence of a linking relation is observable in the projection's own relation set." },
  { id: "LAW_REFERENCE_UNRESOLVED", version: 1, class: "unresolved",
    states: "A structured law citation made by one source family has no canonical target in the owning TRVM registry at the pinned coordinate.",
    decidable_absence: "decidable: governance/invariant-grid.json is a CLOSED registry — grid_check refuses any citation that does not resolve, so absence from it is a statement, not a gap (R15 section 1)." },
  { id: "CERTIFICATE_COORDINATE_STALE", version: 1, class: "stale",
    states: "A preserved certificate is structurally about the selected projection but names verifier coordinates different from the live verifier's. THIS IS A STATUS, NOT AN INVALIDITY CLAIM: the old receipt remains valid evidence of the reconstruction performed under the coordinates that minted it (D-060).",
    decidable_absence: "n/a — positive comparison only." },
  { id: "PROFILE_DECLARATION_DRIFT", version: 1, class: "contradiction",
    states: "Graphonomous's SUBMITTED semantic profile declaration and WRL's ADMITTED row differ in a contract facet.",
    decidable_absence: "decidable: both declarations enumerate every facet, so a facet present in one and absent from the other is a difference, not a gap." },
]);

/** The v1 rule set: v0 minus CROSS_REGISTRY_COREFERENCE_UNLINKED. Carried forward exactly, in the order GPT v7 §11
 *  listed them, and with no replacement rule invented to keep the count at six. */
const CARRIED_FORWARD = Object.freeze(["REFERENCE_TARGET_DRIFT", "SOURCE_PIN_DIVERGENCE", "LAW_REFERENCE_UNRESOLVED", "CERTIFICATE_COORDINATE_STALE", "PROFILE_DECLARATION_DRIFT"]);
const RULES_V1 = Object.freeze(CARRIED_FORWARD.map((id) => RULES_V0.find((r) => r.id === id)));
/** Why a v0 rule is not in v1. A removal states its reason, exactly as a rejection does. */
export const RETIRED = Object.freeze([
  { id: "CROSS_REGISTRY_COREFERENCE_UNLINKED", retired_in: RULEPACK_V1, ruled: "GPT Adjudication v7 §8 (D-076)",
    why: "The 13 cases were never contradictions, drift, stale coordinates or genuinely unresolved references: both source families are present and deterministically name the same exact external qualified identity. What was missing was a Graphonomous-derived cross-family link, and neither authoritative source should be forced to own that edge. It is now REPRESENTED by graphonomous.linkage.rules.v0 rather than reported as a source problem.",
    superseded_by: "graphonomous.linkage.rules.v0 / EXACT_EXTERNAL_COREFERENCE",
    still_a_finding_when: "the external identity has no owning target (LAW_REFERENCE_UNRESOLVED), or linkage refuses because one family carries the identity on more than one node and the ambiguity is decidable" },
]);
export const RULEPACKS = Object.freeze({ [RULEPACK_V0]: RULES_V0, [RULEPACK_V1]: RULES_V1 });
/** The rules of a rulepack. Defaults to v1. */
export const rulesOf = (rulepack = DEFAULT_RULEPACK) => RULEPACKS[rulepack] ?? (() => { throw new Error("unknown consistency rulepack " + rulepack); })();
/** Back-compat for callers that just want the current set. */
export const RULES = RULES_V1;

/** REDUCED AND REJECTED, with the measurement that rejected each. A rule is not implemented because its English
 *  sounds useful (GPT v6 section 12). These are re-openable the moment a source supplies the missing data. */
export const REJECTED = Object.freeze([
  { id: "QUALIFIED_ID_COLLISION",
    why: "No data, and the architecture prevents it. Every statement lid carries its source namespace (law:trvm:... vs law:trvm-gov:...), so two families cannot mint one qualified identity with incompatible meanings. Within one namespace the projector's own fold already raises DUPLICATE_ID as a FAULT before a finding could exist. What the data DOES show is co-reference without collision, which is why CROSS_REGISTRY_COREFERENCE_UNLINKED exists instead.",
    reopen_when: "two families are given a shared qualified identity space." },
  { id: "AUTHORITY_STATE_CONFLICT",
    why: "Reduced to zero on the real data. The rule needs two sources that BOTH explicitly own one state dimension and assert incompatible states. Measured: the crosswalk's 13 TRVM law nodes carry only citation and registry_hint — no status, no revision resolution, no canonicality — so there is nothing for the governance family's status/canonical to conflict WITH. Emitting a conflict here would be inventing an assertion the crosswalk never made.",
    reopen_when: "a second family asserts a law's status, an evidence state, or a release's revision." },
  { id: "VOCABULARY_MEANING_CONFLICT",
    why: "Reduced to zero on the real data. The refusal codes, id prefixes, status words and child protocols are declared by exactly ONE owning registry each (nested-composition-v2.json or the grid). A conflict needs two owners of one vocabulary id, and there is not one in this snapshot.",
    reopen_when: "a second registry declares a term the TRVM schema also declares." },
]);

/* ─────────────────────────────────── identity ─────────────────────────────────── */

/** A premise is an OBSERVED thing: a record lid, a source location, or a pinned coordinate — never a conclusion. */
const premise = (p) => ({ kind: p.kind, ref: p.ref, ...(p.at ? { at: p.at } : {}), ...(p.observed !== undefined ? { observed: p.observed } : {}) });

/** cfind-: content-bound over (rulepack, rule, version, snapshot, sorted premises). Order-independent by construction. */
export function findingId(f) {
  return "cfind-" + H(canonicalBytesG0({
    rulepack: f.rulepack ?? DEFAULT_RULEPACK, rule: f.rule, rule_version: f.rule_version, snapshot: f.snapshot,
    premises: sortSet(f.premises.map(premise), "premises"),
  }));
}

const mkFinding = (rule, { snapshot, projection_root, families, premises, explain, detail, rulepack = DEFAULT_RULEPACK }) => {
  const spec = rulesOf(rulepack).find((r) => r.id === rule);
  if (!spec) throw new Error(`unknown consistency rule ${rule} in ${rulepack}`);
  const f = {
    rule, rule_version: spec.version, rulepack, class: spec.class,
    snapshot, projection_root, families: [...new Set(families)].sort(),
    premises: sortSet(premises.map(premise), "premises"), explain, detail,
    basis: "derived", trvm_derivation: false, authority: "none",
  };
  f.lid = findingId(f);
  return f;
};

/* ─────────────────────────────────── the rules ─────────────────────────────────── */

function ruleReferenceTargetDrift(ctx) {
  const out = [];
  const byRepoPath = new Map();
  for (const s of ctx.snapshot.sources) for (const f of s.files) {
    const k = s.repo + " " + f.path;
    if (!byRepoPath.has(k)) byRepoPath.set(k, []);
    byRepoPath.get(k).push({ namespace: s.namespace, commit: s.commit, blob: f.blob, sha256: f.sha256, bytes: f.bytes, path: f.path, repo: s.repo });
  }
  for (const [, seen] of [...byRepoPath].sort()) {
    if (seen.length < 2) continue;
    if (new Set(seen.map((x) => x.blob)).size === 1) continue;
    const s = seen.slice().sort((a, b) => (a.namespace < b.namespace ? -1 : 1));
    out.push(mkFinding("REFERENCE_TARGET_DRIFT", {
      ...ctx.where, rulepack: ctx.rulepack ?? DEFAULT_RULEPACK, families: s.map((x) => x.namespace),
      premises: s.map((x) => ({ kind: "pinned_file", ref: "git:" + x.repo + "@" + x.commit + ":" + x.path, observed: { namespace: x.namespace, blob: x.blob, sha256: x.sha256, bytes: x.bytes } })),
      detail: s[0].repo + ":" + s[0].path + " is pinned by " + s.length + " source declarations at " + new Set(s.map((x) => x.blob)).size + " different blobs",
      explain: s.map((x) => "source " + x.namespace + " reads git:" + x.repo + "@" + x.commit + ":" + x.path + " — blob " + x.blob + ", " + x.bytes + " bytes")
        .concat(["The snapshot record states both. Everything either family says about that file is true of ITS coordinate and of no other, so no statement derived from one may be compared with a statement derived from the other without naming which blob it came from."]),
    }));
  }
  return out;
}

function ruleSourcePinDivergence(ctx) {
  const out = [];
  const byRepo = new Map();
  for (const s of ctx.snapshot.sources) {
    if (!byRepo.has(s.repo)) byRepo.set(s.repo, []);
    byRepo.get(s.repo).push(s);
  }
  for (const [repo, list] of [...byRepo].sort()) {
    if (new Set(list.map((s) => s.commit)).size < 2) continue;
    const s = list.slice().sort((a, b) => (a.namespace < b.namespace ? -1 : 1));
    out.push(mkFinding("SOURCE_PIN_DIVERGENCE", {
      ...ctx.where, rulepack: ctx.rulepack ?? DEFAULT_RULEPACK, families: s.map((x) => x.namespace),
      premises: s.map((x) => ({ kind: "source_pin", ref: repo + "@" + x.commit, observed: { namespace: x.namespace, registry: x.registry, tree: x.tree, files: x.files.length } })),
      detail: repo + " is read at " + new Set(s.map((x) => x.commit)).size + " different commits by " + s.length + " source declarations in one snapshot",
      explain: s.map((x) => "source " + x.namespace + " pins " + repo + "@" + x.commit + " (" + x.files.length + " files, registry " + x.registry + ")")
        .concat(["This is LEGAL — different families may legitimately read different revisions — and it is recorded because it is the coordinate a reader must know before comparing what the two families say. It is not a contradiction."]),
    }));
  }
  return out;
}

function ruleCoreferenceUnlinked(ctx) {
  /* A qualified external identity is a `citation` attribute: the source's own spelling of a foreign id. Two nodes in
     different namespaces carrying the same citation are the same proposition under two names. */
  const byCitation = new Map();
  for (const n of ctx.nodes) {
    const c = n.attrs?.citation;
    if (typeof c !== "string" || !c) continue;
    const ns = n.lid.split(":")[1];
    if (!byCitation.has(c)) byCitation.set(c, new Map());
    byCitation.get(c).set(ns, n);
  }
  const linked = new Set();
  for (const r of ctx.relations) { linked.add(r.source + " " + r.target); linked.add(r.target + " " + r.source); }
  const out = [];
  for (const [citation, byNs] of [...byCitation].sort()) {
    if (byNs.size < 2) continue;
    const nodes = [...byNs.values()].sort((a, b) => (a.lid < b.lid ? -1 : 1));
    let anyLink = false;
    for (let i = 0; i < nodes.length; i++) for (let k = i + 1; k < nodes.length; k++) if (linked.has(nodes[i].lid + " " + nodes[k].lid)) anyLink = true;
    if (anyLink) continue;
    out.push(mkFinding("CROSS_REGISTRY_COREFERENCE_UNLINKED", {
      ...ctx.where, rulepack: ctx.rulepack ?? DEFAULT_RULEPACK, families: nodes.map((n) => n.lid.split(":")[1]),
      premises: nodes.map((n) => ({ kind: "node", ref: n.lid, at: ctx.firstLocation(n.lid), observed: { role: n.kind, citation } })),
      detail: nodes.length + " statements name the external identity " + citation + ", in " + nodes.length + " namespaces, and no relation links them",
      explain: nodes.map((n) => n.lid + " (role " + n.kind + ") carries citation " + citation + ", asserted from " + (ctx.firstLocation(n.lid) ?? "an unrecorded location"))
        .concat(["Both statements are in this projection and both name the same external id, but this projection contains no relation between them, so a query that follows edges will see two propositions where the sources meant one. This is UNRESOLVED, not a contradiction: neither source is wrong, and nothing here proposes a repair."]),
    }));
  }
  return out;
}

function ruleLawReferenceUnresolved(ctx) {
  /* The owning registry is the CLOSED law registry the governance family observed. Absence from it is decidable
     because grid_check refuses any citation that does not resolve (R15 section 1). */
  const owning = new Map();      // law:<id>@<rev> -> node
  const byLawId = new Map();     // <id> -> [{revision, canonical, lid}]
  for (const n of ctx.nodes) {
    if (n.kind !== "LAW" || n.lid.split(":")[1] !== "trvm-gov") continue;
    const c = n.attrs?.citation; if (!c) continue;
    owning.set(c, n);
    const id = n.attrs.law_id;
    if (!byLawId.has(id)) byLawId.set(id, []);
    byLawId.get(id).push({ revision: n.attrs.revision, canonical: n.attrs.canonical, lid: n.lid });
  }
  if (!owning.size) return [];   // no owning registry in this projection: the rule has nothing to decide against
  const out = [];
  for (const n of ctx.nodes) {
    const ns = n.lid.split(":")[1];
    if (ns === "trvm-gov") continue;
    const c = n.attrs?.citation;
    if (typeof c !== "string" || !/^law:[a-z0-9_.\-]+@\d+$/.test(c)) continue;
    if (owning.has(c)) continue;
    const id = c.slice(4).replace(/@\d+$/, "");
    const known = byLawId.get(id);
    out.push(mkFinding("LAW_REFERENCE_UNRESOLVED", {
      ...ctx.where, rulepack: ctx.rulepack ?? DEFAULT_RULEPACK, families: [ns, "trvm-gov"],
      premises: [
        { kind: "node", ref: n.lid, at: ctx.firstLocation(n.lid), observed: { citation: c, role: n.kind } },
        { kind: "registry", ref: ctx.owningRegistry ?? "registry:trvm-gov:invariant-grid", observed: { entries: owning.size, id_known: !!known, revisions_present: known ? known.map((k) => k.revision).sort() : [] } },
      ],
      detail: known
        ? c + " names revision " + c.replace(/^.*@/, "") + " of a law the registry knows only at revision(s) " + known.map((k) => k.revision).sort().join(", ")
        : c + " names a law id the registry does not contain at all",
      explain: [
        n.lid + " cites " + c + ", asserted from " + (ctx.firstLocation(n.lid) ?? "an unrecorded location"),
        "the owning registry observed in this projection holds " + owning.size + " law entries and does not contain " + c,
        known ? "it does hold " + id + " at revision(s) " + known.map((k) => k.revision).sort().join(", ") + " — so the id is real and the REVISION is the coordinate that does not resolve"
              : "it holds no entry whose id is " + id,
        "Absence is decidable here: the law registry is a closed set whose own checker refuses an unresolvable citation.",
      ],
    }));
  }
  return out;
}

function ruleCertificateCoordinateStale(ctx) {
  const out = [];
  for (const r of ctx.preserved) {
    const moved = [];
    for (const k of ["trvm_commit", "trvm_blobs", "projector", "checker"]) {
      if (JSON.stringify(r.bundle.chain_ids?.[k]) !== JSON.stringify(ctx.liveChain[k])) moved.push(k);
    }
    if (!moved.length) continue;
    out.push(mkFinding("CERTIFICATE_COORDINATE_STALE", {
      ...ctx.where, rulepack: ctx.rulepack ?? DEFAULT_RULEPACK, families: ["graphonomous"],
      premises: [
        { kind: "certificate", ref: r.vclaim, at: r.at, observed: { protocol: r.bundle.protocol, projection_root: r.bundle.claim.projection_root, chain_ids: r.bundle.chain_ids } },
        { kind: "verifier", ref: "graphonomous.g0.certificate", observed: ctx.liveChain },
      ],
      detail: r.at + ": a " + r.bundle.protocol + " receipt whose " + moved.join(" + ") + " differ" + (moved.length === 1 ? "s" : "") + " from the live verifier",
      explain: [
        r.at + " holds " + r.vclaim + ", minted over projection root " + String(r.bundle.claim.projection_root).slice(0, 24) + "...",
        ...moved.map((k) => "chain_ids." + k + ": the receipt names " + JSON.stringify(r.bundle.chain_ids?.[k]).slice(0, 90) + "; this verifier's live value is " + JSON.stringify(ctx.liveChain[k]).slice(0, 90)),
        "THIS IS A STATUS, NOT AN INVALIDITY CLAIM. The receipt remains valid evidence of the reconstruction performed under the coordinates that minted it (D-060). The current checker refuses it because those coordinates moved, and that refusal does not make the old projection root, source commitment or aggregate retroactively false.",
      ],
    }));
  }
  return out;
}

function ruleProfileDeclarationDrift(ctx) {
  const out = [];
  for (const { id, submitted, admitted, at } of ctx.profiles) {
    const diffs = [];
    for (const facet of ["rulepack_id", "roles", "kinds", "endpoint_pairs", "policies"]) {
      const a = submitted[facet], b = admitted[facet];
      if (JSON.stringify(a) !== JSON.stringify(b)) diffs.push({ facet, submitted: a, admitted: b });
    }
    if (!diffs.length) continue;
    out.push(mkFinding("PROFILE_DECLARATION_DRIFT", {
      ...ctx.where, rulepack: ctx.rulepack ?? DEFAULT_RULEPACK, families: ["graphonomous", "wrl"],
      premises: [
        { kind: "declaration", ref: "submitted:" + id, at, observed: Object.fromEntries(diffs.map((d) => [d.facet, d.submitted])) },
        { kind: "declaration", ref: "admitted:" + id, at: ctx.wrlAt, observed: Object.fromEntries(diffs.map((d) => [d.facet, d.admitted])) },
      ],
      detail: id + ": " + diffs.map((d) => d.facet).join(", ") + " differ between the submitted declaration and WRL's admitted row",
      explain: diffs.map((d) => d.facet + ": submitted " + JSON.stringify(d.submitted).slice(0, 80) + ", admitted " + JSON.stringify(d.admitted).slice(0, 80))
        .concat(["Both declarations enumerate every facet, so a difference is a difference and not a gap."]),
    }));
  }
  return out;
}

const IMPL = Object.freeze({
  REFERENCE_TARGET_DRIFT: ruleReferenceTargetDrift,
  SOURCE_PIN_DIVERGENCE: ruleSourcePinDivergence,
  CROSS_REGISTRY_COREFERENCE_UNLINKED: ruleCoreferenceUnlinked,
  LAW_REFERENCE_UNRESOLVED: ruleLawReferenceUnresolved,
  CERTIFICATE_COORDINATE_STALE: ruleCertificateCoordinateStale,
  PROFILE_DECLARATION_DRIFT: ruleProfileDeclarationDrift,
});

/* ─────────────────────────────────── the run ─────────────────────────────────── */

const lines = (p) => (existsSync(p) ? readFileSync(p, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)) : []);
export const PRESERVED_ROOTS = Object.freeze(["pre-b1", "pre-d034", "pre-g0f", "pre-trvmp01", "pre-v1", "pre-trvm", "pre-v2"]);

/** Build the context a rule sees. Everything in it is OBSERVED: records from the projection, the snapshot record, the
 *  live verifier chain, and the preserved receipts this tree keeps. Nothing is inferred and nothing is fetched. */
export function contextFor(dir, { preservedRoots = PRESERVED_ROOTS, liveChain, profiles = [], linkageRoot = null, rulepack } = {}) {
  const manifest = JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  const snapshot = JSON.parse(readFileSync(join(dir, "snapshot.json"), "utf8"));
  const nodes = lines(join(dir, "records/node.jsonl"));
  const relations = lines(join(dir, "records/relation.jsonl"));
  const assertions = lines(join(dir, "records/assertion.jsonl"));
  const bySubject = new Map();
  for (const a of assertions) { if (!bySubject.has(a.subject)) bySubject.set(a.subject, []); bySubject.get(a.subject).push(a.location); }
  const firstLocation = (lid) => (bySubject.get(lid) ?? []).slice().sort()[0] ?? null;

  /* the preserved receipts, from this tree's own re-mint directories */
  const preserved = [];
  const name = dir.replace(/\/+$/, "").split("/").pop();
  for (const root of preservedRoots) {
    for (const cdir of ["certificate", "certificate-v1"]) {
      const p = join(ROOT_DIR, "projections", root, name, cdir);
      if (!existsSync(join(p, "bundle.json"))) continue;
      preserved.push({ at: "projections/" + root + "/" + name + "/" + cdir, bundle: JSON.parse(readFileSync(join(p, "bundle.json"), "utf8")), vclaim: readFileSync(join(p, "VCLAIM"), "utf8").trim() });
    }
  }
  return {
    where: { snapshot: manifest.snapshot, projection_root: readFileSync(join(dir, "ROOT"), "utf8").trim() },
    snapshot, nodes, relations, firstLocation, preserved, liveChain, profiles, linkageRoot, rulepack,
    owningRegistry: nodes.find((n) => n.kind === "REGISTRY" && n.lid.startsWith("registry:trvm-gov:invariant-grid"))?.lid ?? null,
    wrlAt: "WRL relation-v2.js V2_PROFILES",
  };
}

/** Run every accepted rule. Returns findings sorted by content, plus per-rule counts INCLUDING the zeroes — a rule
 *  that ran and found nothing is a measurement, and it is reported. */
export function runConsistency(ctx, { rulepack = ctx.rulepack ?? DEFAULT_RULEPACK } = {}) {
  const rules = rulesOf(rulepack);
  ctx = { ...ctx, rulepack };
  const findings = []; const counts = {};
  for (const spec of rules) {
    const got = IMPL[spec.id](ctx);
    counts[spec.id] = got.length;
    findings.push(...got);
  }
  const sorted = sortSet(findings, "findings");
  const byClass = {};
  for (const f of sorted) byClass[f.class] = (byClass[f.class] ?? 0) + 1;
  return { findings: sorted, counts, by_class: byClass, rulepack, rules: rules.length, rejected: REJECTED.length, retired: rulepack === RULEPACK_V1 ? RETIRED.length : 0 };
}

/** Write <dir>/consistency/ — its OWN root, derived, never a member of the projection root. */
export function writeConsistency(dir, ctx, out = join(dir, "consistency"), { rulepack = DEFAULT_RULEPACK } = {}) {
  const r = runConsistency(ctx, { rulepack });
  const manifest = {
    kind: "g0-consistency", rulepack, snapshot: ctx.where.snapshot, projection_root: ctx.where.projection_root,
    rules: rulesOf(rulepack).map((x) => ({ id: x.id, version: x.version, class: x.class })),
    rejected: REJECTED.map((x) => x.id),
    retired: RETIRED.filter((x) => x.retired_in === rulepack).map((x) => ({ id: x.id, superseded_by: x.superseded_by })),
    linkage_root: ctx.linkageRoot ?? null,
    counts: Object.entries(r.counts).sort(), by_class: Object.entries(r.by_class).sort(),
    entries: sortSet(r.findings.map((f) => [f.lid, "sha256:" + H(canonicalBytesG0(f))]), "entries"),
    count: r.findings.length,
    scope: { authority: "none", basis: "derived", trvm_derivation: false, repairs_offered: 0, registry_written: false },
  };
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "findings.jsonl"), r.findings.map((f) => canonicalBytesG0(f).toString("utf8")).join("\n") + (r.findings.length ? "\n" : ""));
  writeFileSync(join(out, "manifest.json"), canonicalBytesG0(manifest));
  const root = artifactRoot(manifest);
  writeFileSync(join(out, "ROOT"), root + "\n");
  return { ...r, root, manifest };
}
