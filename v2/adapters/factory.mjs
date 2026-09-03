/* factory.mjs — the SECOND authoritative adapter (G0-F, D-056): the invariant factory canonical ref
 * (`CLAIM_LEDGER.json` + `mosaic/{assumptions,sources}.json` + `mosaic/receipts/*.json` + the site's `cells.json`) at a
 * pinned commit of the bare repository `~/.invariant-factory/canonical.git`, read only through `<commit>:<path>`
 * (adapters/git.mjs; the stale worktree `wt-r9` is never consulted). Contract: handoff/INGESTION_CONTRACTS/factory-ledger.md
 * as amended by R12 / D-056 (its "Measured deviations" section records where this code departs from the designed text).
 *
 * SCOPE IS EXACTLY D-056 (1)–(7): REGISTRY + 208 CLAIM + MEMBER_OF; WITNESS/WITNESSES/LOCATED_IN with the `§n` anchor
 * resolved to a line in the pinned blob; ASSUMES (typed `ASM-*` → assumption:factory:*, free text → the crosswalk's `text`
 * namespace so one sentence co-refers across registries); BINDS → cell:cells:NN; SUPERSEDES from both `supersedes` and
 * `superseded_by` (one relation, two assertions — D-029); CITES → artifact:factory:SRC-* and cites_bound; ROUND/RECEIPT from
 * the 20 receipts with PRODUCED_BY and `invariants.established` → CLAIM PRODUCED_BY ROUND. Arguments, defeaters, incidents,
 * instruments, objectives, occupancy, operations, embodiment, `retyped` transitions and `mosaic/derived/` are DEFERRED to
 * the v1 proposal (handoff/G0F_V1_OBLIGATION.md) — nothing here mints a role, kind or endpoint pair the frozen
 * `graphonomous.semantic.v0` profile does not declare (D-050).
 *
 * Everything is OBSERVED. Prose (`statement`, `evidence`, `finding`, `gap`, `review_focus`, `prior_art`, …) is carried
 * verbatim as attributes and never parsed for facts; the ONLY tokens lifted out of prose are `SRC-*` citation ids in
 * `prior_art` (a typed id grammar, the same discipline as the crosswalk's F-ids), and even those only resolve against the
 * pinned `mosaic/sources.json`. `implementation_binding` stays an attribute (81 of 122 path bindings carry trailing prose;
 * no location is invented from it). The raw source vocabulary (`status`) rides on every assertion as `evidence_state`
 * {token, vocabulary: "factory-ledger"} and the WITNESSES assertion keeps `raw_status` beside the contract's `outcome`. */
import { parseStrictJson, G0Error } from "../lib/canon.mjs";
import { Emitter } from "../lib/emit.mjs";
import { makeLid } from "../lib/lid.mjs";
import { BARE_TOKEN } from "./crosswalk.mjs";

export const LEDGER_PATH = "CLAIM_LEDGER.json";
export const ASSUMPTIONS_PATH = "mosaic/assumptions.json";
export const SOURCES_PATH = "mosaic/sources.json";
export const CELLS_PATH = "opensentience.org/_invariants/data/cells.json";
export const RECEIPTS_PREFIX = "mosaic/receipts/";
export const VOCABULARY = "factory-ledger";
/** `<path>` or `<path> §<section>` — the only two witness forms the ledger uses (R12 §2: 132 + 137; zero `path#frag`). */
const WITNESS_RE = /^(\S+)(?:\s+§(\S+))?$/;
/** A `§n` SECTION BANNER: a line that begins (after an optional comment marker and box-drawing decoration) with `§<token>`.
 *  A `§n` mentioned mid-sentence is not a banner. */
const BANNER = /^\s*(?:\/\/|\/\*|\*|#)?\s*[═─=\-—·\s]*§\s*(\S+)/;
const TRAILING_PUNCT = /[·—\-:.,;)]+$/;
const SRC_ID = /\bSRC-[A-Z0-9](?:[A-Z0-9.-]*[A-Z0-9])?\b/g;
const CELL_BINDING = /^cell:(\S+)$/;
const ASM_ID = /^ASM-[A-Z0-9][A-Z0-9.-]*$/;
/** The crosswalk's witness-kind classifier, restated here so a witness node both registries name folds without a
 *  CONTRADICTION (the fold is the guard: a drift between the two copies would surface as a projector fault). */
const WITNESS_KIND = (p) => /compile-fail\//.test(p) ? "compile-fail-gate" : /\.tla$/.test(p) ? "tla-unexecuted" : /\.(py)$/.test(p) ? "model-check" : /\.(rs|ex|exs|mjs|js|sh)$/.test(p) ? "executable" : /\.md$/.test(p) ? "result-document" : /\.(json|log|txt)$/.test(p) ? "execution-output" : /\.tar\.gz$/.test(p) ? "bundle" : "file";
const KEY_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
/** Every top-level claim field the census saw (R12 §2). Anything else is reported as SCHEMA_UNEXPECTED_FIELD, never dropped silently. */
const CLAIM_FIELDS = new Set(["claim_id", "statement", "status", "evidence", "last_verified", "assumptions", "witnesses", "prior_art", "implementation_binding", "assumption_refs", "review_focus", "evidence_kind", "obligation", "gap", "imported_from", "readjudicated", "evidence_qualifiers", "refutation_scope", "supersedes", "superseded_by", "note", "finding", "bound", "cites_bound"]);
const PROSE_FIELDS = ["statement", "evidence", "finding", "gap", "note", "review_focus", "prior_art", "implementation_binding", "last_verified", "refutation_scope", "obligation", "evidence_kind"];

/** A source value as a G0 attribute value. Source objects keep their own keys; a key outside the attrs grammar (four
 *  `evidence_qualifiers.applicability.local_bindings` objects are keyed by phrases such as "join tree") is re-encoded as
 *  `{keyed_entries: [{key, value}]}` in source order — a structural re-keying, not a normalization of content. */
export function attrValue(v) {
  if (v === null || typeof v === "string" || typeof v === "boolean" || typeof v === "number") return v;
  if (Array.isArray(v)) return v.map(attrValue);
  if (typeof v === "object") {
    if ("decimal_string" in v && Object.keys(v).length === 1) return v;
    const keys = Object.keys(v);
    if (keys.every((k) => KEY_RE.test(k))) return Object.fromEntries(keys.map((k) => [k, attrValue(v[k])]));
    return { keyed_entries: keys.map((k) => ({ key: k, value: attrValue(v[k]) })) };
  }
  throw new G0Error("ATTR_VALUE", `unsupported source value ${typeof v}`);
}

/** Parse a witness string into {path, section, raw} or null when it is not one of the two forms. */
export function parseWitness(raw) { const m = WITNESS_RE.exec(String(raw)); return m ? { path: m[1], section: m[2] ?? null, raw: String(raw) } : null; }
/** Resolve a `§n` anchor to a 1-based line: the first SECTION BANNER whose token equals `sec`. Null when no banner carries it. */
export function sectionLine(text, sec) {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) { const m = BANNER.exec(lines[i]); if (m && m[1].replace(TRAILING_PUNCT, "") === sec) return i + 1; }
  return null;
}

/** Every file this adapter reads at a pin — the snapshot pins exactly this set (D-056: tree/blob identities of every file
 *  read). Witness paths come from the ledger itself; a path the tree lacks is a DANGLING_WITNESS at ingestion, not here. */
export function factoryFiles(repo) {
  if (!repo.has(LEDGER_PATH)) throw new G0Error("SOURCE_MISSING", `${repo.name}@${repo.commit.slice(0, 7)} has no ${LEDGER_PATH}`);
  const doc = parseStrictJson(repo.bytes(LEDGER_PATH)).value;
  const files = new Set([LEDGER_PATH, ASSUMPTIONS_PATH, SOURCES_PATH, CELLS_PATH, ...repo.under(RECEIPTS_PREFIX)]);
  for (const c of doc.claims || []) for (const w of c.witnesses || []) { const p = parseWitness(w); if (p && repo.has(p.path)) files.add(p.path); }
  return [...files].filter((p) => repo.has(p)).sort();
}

/**
 * @param ctx { snapshot, repos: {factory, …}, treeRegistries }
 * @returns { factory: Emitter output, meta }
 */
export function ingestFactory(ctx) {
  const { snapshot, repos, treeRegistries = {} } = ctx;
  const repo = repos.factory;
  if (!repo) throw new G0Error("SOURCE_MISSING", "the snapshot pins no `factory` source");
  for (const p of [LEDGER_PATH, ASSUMPTIONS_PATH, SOURCES_PATH, CELLS_PATH]) if (!repo.has(p)) throw new G0Error("SOURCE_MISSING", `${repo.name}@${repo.commit.slice(0, 7)} has no ${p}`);
  const ledger = parseStrictJson(repo.bytes(LEDGER_PATH));
  if (ledger.number_forms.length) throw new G0Error("UNEXPECTED_NUMBER_FORM", `${LEDGER_PATH} has non-integer numbers: ${JSON.stringify(ledger.number_forms.slice(0, 3))}`);
  const doc = ledger.value; const ledgerBlob = repo.blobOid(LEDGER_PATH);
  const asmDoc = parseStrictJson(repo.bytes(ASSUMPTIONS_PATH)).value, asmBlob = repo.blobOid(ASSUMPTIONS_PATH);
  const srcDoc = parseStrictJson(repo.bytes(SOURCES_PATH)).value, srcBlob = repo.blobOid(SOURCES_PATH);
  const cellsDoc = parseStrictJson(repo.bytes(CELLS_PATH)).value;
  const roundId = String(doc._round?.id || "");
  if (!roundId) throw new G0Error("SOURCE_SHAPE", `${LEDGER_PATH} has no _round.id`);
  const registryLid = makeLid("REGISTRY", "factory", `${VOCABULARY}@${roundId}`).lid;
  const E = new Emitter({ snapshot, registry: registryLid, namespace: "factory", pinned_identity: ledgerBlob, path: LEDGER_PATH, treeRegistries });
  const at = (ptr, path = LEDGER_PATH, pinned = ledgerBlob) => E.loc(ptr, null, { path, pinned, namespace: "factory" });
  const ptrTok = (s) => String(s).replace(/~/g, "~0").replace(/\//g, "~1");

  // ── the vocabulary and the policy ─────────────────────────────────────────────────────────────
  const statuses = doc._statuses && typeof doc._statuses === "object" ? Object.keys(doc._statuses) : [];
  const settled = new Set(Array.isArray(doc._settled?.statuses) ? doc._settled.statuses.map(String) : []);
  const claims = Array.isArray(doc.claims) ? doc.claims : [];
  const claimIds = new Set(claims.map((c) => String(c.claim_id)));
  const claimLid = (id) => makeLid("CLAIM", "factory", id).lid;
  const asmRecords = Array.isArray(asmDoc.assumptions) ? asmDoc.assumptions : []; const asmById = new Map(asmRecords.map((a, k) => [String(a.id), k]));
  const srcRecords = Array.isArray(srcDoc.sources) ? srcDoc.sources : []; const srcById = new Map(srcRecords.map((s, k) => [String(s.id), k]));
  const cellNums = new Set((Array.isArray(cellsDoc.cells) ? cellsDoc.cells : []).map((c) => String(c.num)));
  const asmLid = (id) => makeLid("ASSUMPTION", "factory", id).lid, srcLid = (id) => makeLid("ARTIFACT", "factory", id).lid;

  // ── the registry node ─────────────────────────────────────────────────────────────────────────
  const rootLoc = at(null);
  E.node("REGISTRY", registryLid, {
    vocabulary: VOCABULARY, authority_class: "AUTHORITATIVE",
    round: attrValue(doc._round), statuses: attrValue(doc._statuses || {}), settled_policy: attrValue(doc._settled || {}),
    revisions: attrValue(doc._revisions || {}), registries: attrValue(doc._registries || {}), comment: String(doc._comment || ""),
    source_path: LEDGER_PATH, blob: ledgerBlob, commit: repo.commit, repo: repo.name, claims: claims.length,
    tokens_observed: [...new Set(claims.map((c) => String(c.status)))].sort(),
  }, rootLoc);

  // ── the claims ────────────────────────────────────────────────────────────────────────────────
  const sectionCache = new Map();
  const witnessNode = (w, claimLidOf, lat) => {
    if (!repo.has(w.path)) { E.fault("DANGLING_WITNESS", "factory.claims.witnesses", `${JSON.stringify(w.raw)}: ${w.path} is not in the pinned factory tree`, [claimLidOf], { attrs: { text: w.raw } }); return null; }
    const blob = repo.blobOid(w.path);
    const lid = E.lid("WITNESS", "factory", w.path + (w.section ? "#" + w.section : ""));
    let line = null;
    if (w.section) {
      const key = w.path + "#" + w.section;
      if (!sectionCache.has(key)) sectionCache.set(key, sectionLine(repo.bytes(w.path).toString("utf8"), w.section));
      line = sectionCache.get(key);
      if (!line) E.fault("HEADING_WITHOUT_NUMBER", "factory.claims.witnesses", `${JSON.stringify(w.raw)}: no section banner §${w.section} in ${w.path} at ${repo.commit.slice(0, 7)}`, [claimLidOf, lid], { attrs: { text: w.raw } });
    }
    // a section that resolves → the LINE of its banner; a section that does not → the raw `§n` as a heading fragment; bare → the file
    const fragment = w.section ? (line ? `L${line}` : `§${w.section}`) : null;
    const loc = E.loc(fragment, null, { path: w.path, pinned: blob, namespace: "factory" });
    E.node("WITNESS", lid, { path: w.path, root: "factory", blob, commit: repo.commit, kind: WITNESS_KIND(w.path), ...(w.section ? { section: w.section, ...(line ? { line } : {}) } : {}) }, lat);
    E.rel("LOCATED_IN", lid, loc, lat);
    return lid;
  };
  claims.forEach((c, i) => {
    const ptr = `/claims/${i}`; const lat = at(ptr);
    const id = String(c.claim_id ?? "");
    if (!id || !BARE_TOKEN.test(id)) { E.fault("AMBIGUOUS_IDENTIFIER", "factory.claims.claim_id", `claim ${i} has id ${JSON.stringify(c.claim_id)}`, [registryLid]); return; }
    const claim = claimLid(id); const status = String(c.status ?? "");
    for (const k of Object.keys(c)) if (!CLAIM_FIELDS.has(k)) E.fault("SCHEMA_UNEXPECTED_FIELD", "factory.claims", `${id}: field ${JSON.stringify(k)} is outside the census'd shape`, [claim], { attrs: { text: k } });
    if (!statuses.includes(status)) E.fault("STATUS_OUTSIDE_VOCABULARY", "factory.claims.status", `${id}: status ${JSON.stringify(status)} is not in _statuses (${statuses.join(", ")})`, [claim, registryLid], { attrs: { text: status } });
    const isSettled = settled.has(status);
    const witnesses = Array.isArray(c.witnesses) ? c.witnesses : [];
    if (isSettled && witnesses.length === 0) E.fault("SETTLED_WITHOUT_WITNESS", "factory.claims.witnesses", `${id}: status ${status} is settled by _settled.statuses and witnesses[] is empty (a fact about the source; the factory's own gate requires witnesses only for PROVED/CONDITIONAL)`, [claim], { attrs: { status } });
    const binding = c.implementation_binding == null ? null : String(c.implementation_binding);
    const bindingForm = binding == null ? null : CELL_BINDING.test(binding) ? "cell" : /\s/.test(binding) ? "path-with-prose" : "path";
    const attrs = { claim_id: id, registry_hint: VOCABULARY, settled_by_policy: isSettled, binding_form: bindingForm };
    for (const f of PROSE_FIELDS) if (c[f] != null) attrs[f] = String(c[f]);
    for (const f of ["assumptions", "witnesses", "assumption_refs", "supersedes", "superseded_by", "cites_bound", "imported_from", "readjudicated", "evidence_qualifiers", "bound"]) if (c[f] !== undefined) attrs[f] = attrValue(c[f]);
    E.node("CLAIM", claim, attrs, lat, { extra: { evidence_state: { token: status, vocabulary: VOCABULARY } } });
    E.rel("MEMBER_OF", claim, registryLid, lat);
    // witnesses: outcome from status (contract) — settled → pass of THAT obligation; unsettled → the source states no outcome
    witnesses.forEach((raw, j) => {
      const wat = at(`${ptr}/witnesses/${j}`); const w = parseWitness(raw);
      if (!w) { E.fault("UNSUPPORTED_SOURCE_FORM", "factory.claims.witnesses", `${id}: witness ${JSON.stringify(raw)} is neither <path> nor <path> §<section>`, [claim], { attrs: { text: String(raw) } }); return; }
      const wl = witnessNode(w, claim, wat); if (!wl) return;
      E.rel("WITNESSES", wl, claim, wat, { asrt: { outcome: isSettled ? "pass" : { unknown: "not-stated" }, outcome_basis: "status", raw_status: status, settled: isSettled, cited_as: w.raw, ...(c.obligation != null ? { obligation: String(c.obligation) } : {}) } });
    });
    // free-text assumptions: the crosswalk's `text` namespace, minted by the same Emitter.lid rule, so one sentence co-refers
    (Array.isArray(c.assumptions) ? c.assumptions : []).forEach((text, j) => {
      const aat = at(`${ptr}/assumptions/${j}`); const s = String(text); if (!s) return;
      const a = E.lid("ASSUMPTION", "text", s); E.node("ASSUMPTION", a, { text: s, unnormalized: true }, aat); E.rel("ASSUMES", claim, a, aat, { asrt: { stated_by: "assumptions" } });
    });
    // typed assumption refs → the mosaic record
    (Array.isArray(c.assumption_refs) ? c.assumption_refs : []).forEach((ref, j) => {
      const rat = at(`${ptr}/assumption_refs/${j}`); const r = String(ref);
      if (!asmById.has(r)) { E.fault("UNRESOLVED_LINK", "factory.claims.assumption_refs", `${id}: assumption_ref ${JSON.stringify(r)} is not an id in ${ASSUMPTIONS_PATH}`, [claim], { attrs: { text: r, reason: ASM_ID.test(r) ? "absent" : "not-an-id" } }); return; }
      E.rel("ASSUMES", claim, asmLid(r), rat, { asrt: { stated_by: "assumption_refs", raw_token: r } });
    });
    // implementation binding: a cell → BINDS; a path (with or without prose) stays an attribute (D-056: no location invented from prose)
    if (bindingForm === "cell") {
      const num = CELL_BINDING.exec(binding)[1]; const bat = at(`${ptr}/implementation_binding`);
      if (!cellNums.has(num)) E.fault("DANGLING_CELL_BINDING", "factory.claims.implementation_binding", `${id}: ${binding} names no cell in ${CELLS_PATH}`, [claim], { attrs: { text: binding } });
      else { const cell = E.lid("CELL", "cells", num); E.node("CELL", cell, { num, registry_hint: "cells" }, bat); E.rel("BINDS", claim, cell, bat, { asrt: { source_id: binding } }); }
    }
    // supersession, from both fields: an exact claim id is the proposition; an id-shaped absent token dangles; prose is reported, never parsed
    const supersession = (field, value, sat) => {
      const v = String(value);
      if (claimIds.has(v)) { const [src, tgt] = field === "supersedes" ? [claim, claimLid(v)] : [claimLid(v), claim]; E.rel("SUPERSEDES", src, tgt, sat, { asrt: { stated_by: field, raw_token: v } }); return; }
      if (BARE_TOKEN.test(v)) { E.fault("DANGLING_SUPERSESSION", `factory.claims.${field}`, `${id}: ${field} names ${v}, which is not a claim_id at this pin`, [claim], { attrs: { text: v } }); return; }
      E.fault("UNRESOLVED_LINK", `factory.claims.${field}`, `${id}: ${field} is prose, not a claim id (never parsed — D-021)`, [claim], { attrs: { text: v, reason: "prose" } });
    };
    for (const field of ["supersedes", "superseded_by"]) if (c[field] !== undefined) {
      const vals = Array.isArray(c[field]) ? c[field] : [c[field]];
      vals.forEach((v, j) => supersession(field, v, at(Array.isArray(c[field]) ? `${ptr}/${field}/${j}` : `${ptr}/${field}`)));
    }
    // citations: SRC-* ids in prior_art (a typed id grammar), evidence_qualifiers.citation_ref, cites_bound
    const cite = (srcId, cat, asrt) => {
      if (!srcById.has(srcId)) { E.fault("UNRESOLVED_LINK", "factory.claims.citations", `${id}: ${srcId} is not an id in ${SOURCES_PATH}`, [claim], { attrs: { text: srcId, reason: "absent" } }); return; }
      E.rel("CITES", claim, srcLid(srcId), cat, { asrt });
    };
    if (typeof c.prior_art === "string") for (const m of new Set([...c.prior_art.matchAll(SRC_ID)].map((x) => x[0]))) cite(m, at(`${ptr}/prior_art`), { stated_by: "prior_art", mention: true, raw_token: m });
    if (typeof c.evidence_qualifiers?.citation_ref === "string") cite(c.evidence_qualifiers.citation_ref, at(`${ptr}/evidence_qualifiers/citation_ref`), { stated_by: "evidence_qualifiers.citation_ref", raw_token: c.evidence_qualifiers.citation_ref });
    (Array.isArray(c.cites_bound) ? c.cites_bound : []).forEach((b, j) => {
      const cat = at(`${ptr}/cites_bound/${j}`); const target = String(b?.claim ?? "");
      if (!claimIds.has(target)) { E.fault("UNRESOLVED_LINK", "factory.claims.cites_bound", `${id}: cites_bound names ${JSON.stringify(target)}, not a claim_id`, [claim], { attrs: { text: target, reason: "absent" } }); return; }
      E.rel("CITES", claim, claimLid(target), cat, { asrt: { stated_by: "cites_bound", raw_token: target, ...(b?.needs != null ? { needs: String(b.needs) } : {}) } });
    });
  });

  // ── mosaic/assumptions.json: the typed assumption records and their inverse `cited_by` statements ──
  asmRecords.forEach((a, k) => {
    const id = String(a.id ?? ""); const aat = at(`/assumptions/${k}`, ASSUMPTIONS_PATH, asmBlob);
    if (!ASM_ID.test(id)) { E.fault("AMBIGUOUS_IDENTIFIER", "factory.assumptions.id", `assumption ${k} has id ${JSON.stringify(a.id)}`, [registryLid]); return; }
    const { id: _id, cited_by, ...rest } = a;
    E.node("ASSUMPTION", asmLid(id), { id, registry_hint: VOCABULARY, ...attrValue(rest) }, aat);
    (Array.isArray(cited_by) ? cited_by : []).forEach((cid, j) => {
      const cat = at(`/assumptions/${k}/cited_by/${j}`, ASSUMPTIONS_PATH, asmBlob); const s = String(cid);
      if (!claimIds.has(s)) { E.fault("UNRESOLVED_LINK", "factory.assumptions.cited_by", `${id}: cited_by names ${JSON.stringify(s)}, not a claim_id`, [asmLid(id)], { attrs: { text: s, reason: "absent" } }); return; }
      E.rel("ASSUMES", claimLid(s), asmLid(id), cat, { asrt: { stated_by: "cited_by", raw_token: s } });
    });
  });
  // ── mosaic/sources.json: the cited results and their inverse `used_by` statements ──────────────
  srcRecords.forEach((s, k) => {
    const id = String(s.id ?? ""); const sat = at(`/sources/${k}`, SOURCES_PATH, srcBlob);
    if (!/^SRC-[A-Z0-9][A-Z0-9.-]*$/.test(id)) { E.fault("AMBIGUOUS_IDENTIFIER", "factory.sources.id", `source ${k} has id ${JSON.stringify(s.id)}`, [registryLid]); return; }
    const { id: _id, used_by, ...rest } = s;
    E.node("ARTIFACT", srcLid(id), { id, registry_hint: VOCABULARY, role: "cited-result", ...attrValue(rest) }, sat);
    (Array.isArray(used_by) ? used_by : []).forEach((cid, j) => {
      const uat = at(`/sources/${k}/used_by/${j}`, SOURCES_PATH, srcBlob); const c = String(cid);
      if (!claimIds.has(c)) { E.fault("UNRESOLVED_LINK", "factory.sources.used_by", `${id}: used_by names ${JSON.stringify(c)}, not a claim_id`, [srcLid(id)], { attrs: { text: c, reason: "absent" } }); return; }
      E.rel("CITES", claimLid(c), srcLid(id), uat, { asrt: { stated_by: "used_by", raw_token: c } });
    });
  });

  // ── mosaic/receipts/*.json: RECEIPT + ROUND, PRODUCED_BY, established → CLAIM PRODUCED_BY ROUND ──
  const roundLid = (rev) => makeLid("ROUND", "factory", rev).lid;
  const receipts = repo.under(RECEIPTS_PREFIX).filter((p) => p.endsWith(".json"));
  for (const path of receipts) {
    const blob = repo.blobOid(path); const parsed = parseStrictJson(repo.bytes(path)); const R = parsed.value;
    const rat = at(null, path, blob); const receipt = E.lid("RECEIPT", "factory", path);
    const tr = R.transition && typeof R.transition === "object" ? R.transition : {};
    const to = String(tr.to ?? ""), from = String(tr.from ?? "");
    if (!to) { E.fault("SCHEMA_MISSING_FIELD", "factory.receipts.transition", `${path}: transition.to is missing`, [receipt]); continue; }
    const inv = R.invariants && typeof R.invariants === "object" ? R.invariants : {};
    E.node("RECEIPT", receipt, {
      path, root: "factory", blob, commit: repo.commit, registry_hint: VOCABULARY, receipt_version: attrValue(R.receipt_version ?? null),
      transition: attrValue({ id: tr.id ?? null, from: tr.from ?? null, to: tr.to ?? null, parents: tr.parents ?? [], operation: tr.operation ?? null }),
      ...(R.parent && typeof R.parent === "object" ? { parent: attrValue({ revision: R.parent.revision ?? null, commit_oid: R.parent.commit_oid ?? null, receipt_sha256: R.parent.receipt_sha256 ?? null }) } : {}),
      ...(R.candidate && typeof R.candidate === "object" ? { candidate: attrValue({ revision: R.candidate.revision ?? null, commit_oid: R.candidate.commit_oid ?? null, tree_manifest_sha256: R.candidate.tree_manifest_sha256 ?? null, tree_paths: R.candidate.tree_paths ?? null }) } : {}),
      invariants: attrValue(inv),
      ...(R.decision && typeof R.decision === "object" ? { decision: attrValue({ verdict: R.decision.verdict ?? null, canonical_ref: R.decision.canonical_ref ?? null, expected_parent_oid: R.decision.expected_parent_oid ?? null }) } : {}),
      ...(parsed.number_forms.length ? { number_forms: parsed.number_forms.length } : {}),
    }, rat);
    E.rel("LOCATED_IN", receipt, E.loc(null, null, { path, pinned: blob, namespace: "factory" }), rat);
    const tat = at("/transition/to", path, blob);
    E.node("ROUND", roundLid(to), { revision: to, registry_hint: VOCABULARY, receipt_path: path, ...(tr.operation != null ? { operation: String(tr.operation) } : {}), ...(from ? { from } : {}) }, tat);
    E.rel("PRODUCED_BY", receipt, roundLid(to), tat);
    if (from) E.node("ROUND", roundLid(from), { revision: from, registry_hint: VOCABULARY }, at("/transition/from", path, blob));
    // D-037: a parent chain is LINEAGE, not replacement — no ROUND SUPERSEDES ROUND is inferred from it. The one receipt whose
    // `lineage.supersedes` is non-null states in prose that the quarantined head is "not superseded in the ledger sense".
    if (R.lineage && typeof R.lineage === "object" && R.lineage.supersedes != null) {
      const v = String(R.lineage.supersedes); const lat = at("/lineage/supersedes", path, blob);
      if (/^INV-R[0-9A-Z.-]+$/.test(v) && v !== to) E.rel("SUPERSEDES", roundLid(to), roundLid(v), lat, { asrt: { stated_by: "lineage.supersedes", raw_token: v } });
      else E.fault("UNRESOLVED_LINK", "factory.receipts.lineage.supersedes", `${path}: lineage.supersedes is prose, not a revision id (never parsed — D-021)`, [receipt], { attrs: { text: v.slice(0, 200), reason: "prose" } });
    }
    (Array.isArray(inv.established) ? inv.established : []).forEach((x, j) => {
      const eat = at(`/invariants/established/${j}`, path, blob);
      if (typeof x !== "string") { E.fault("UNSUPPORTED_SOURCE_FORM", "factory.receipts.established", `${path}: established[${j}] is not a string`, [receipt]); return; }
      if (!claimIds.has(x)) { E.fault("UNRESOLVED_LINK", "factory.receipts.established", `${path}: established names ${JSON.stringify(x)}, not a claim_id at this pin`, [receipt], { attrs: { text: x, reason: "absent" } }); return; }
      E.rel("PRODUCED_BY", claimLid(x), roundLid(to), eat, { asrt: { stated_by: "invariants.established", receipt: path } });
    });
  }
  return { factory: E.output(), meta: { registry: registryLid, round: roundId, ledgerBlob, claims: claims.length, receipts: receipts.length, statuses, settled: [...settled] } };
}
