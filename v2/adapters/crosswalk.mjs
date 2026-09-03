/* crosswalk.mjs — the first authoritative adapter: `CROSS_REGISTRY_CLAIM_MAP.json` (+ its generated companion
 * `evidence_state.json`) at a pinned invariant-r10 commit. Contract: handoff/INGESTION_CONTRACTS/crosswalk-v2.6.md,
 * extended additively for v2.7 by D-025. Everything here is OBSERVED; the adapter maps source fields onto the
 * normalized model and raises typed faults for what it cannot map. It never edits a registry, never guesses an
 * identifier, and never upgrades precision (D-021). */
import { parseStrictJson, G0Error } from "../lib/canon.mjs";
import { Emitter } from "../lib/emit.mjs";
import { makeLid, contextBoundLid } from "../lib/lid.mjs";
import { createHash } from "node:crypto";

const RECORD_ID = /^E-\d{2}[abc]?$/;
const OBLIGATION = /^S[1-5]$/;
const RELATION_BY_FIELD = { direct: "STATES", mechanism: "IMPLEMENTS", corollary: "DERIVES_FROM", definition: "DEFINES", representation: "REPRESENTS", "cross-cutting": "CROSS_CUTS" };
const CATEGORY_KIND = { CROSS: "LAW", DEF: "DEFINITION", REPR: "REPRESENTATION" };
const TOKEN_FAMILY = (t) => /^TESTED/.test(t) ? "TESTED" : /^PROVED/.test(t) ? "PROVED" : /^FALSIFIED/.test(t) ? "FALSIFIED" : /^(PROPERTY-TESTED|EXHAUSTIVE-IN-MODEL)/.test(t) ? "TESTED-OTHER" : "OTHER";
const CITATION = /GPT v(\d)( audit)? §(\d+(?:\.\d+)?)(?:[–-]§?(\d+(?:\.\d+)?))?/g;
const F_ID = /\bF(\d{1,2})\b/g;
const CODE_SYMBOL = /^((?:[\w.-]+\/)*[\w.-]+\.(?:rs|ex|exs|mjs|js|py|sh))\s+([A-Za-z_][A-Za-z0-9_:.]*)$/;
const PATHISH = /^[\w.-]+(?:\/[\w.\-@]+)*\.(?:rs|ex|exs|mjs|js|py|sh|md|json|txt|log|tla|cfg|tar\.gz)(#.*)?$/;
/** D-031: the bare-token form the contract recognizes as a candidate factory-claim id (upper-case, hyphenated). */
export const BARE_TOKEN = /^[A-Z][A-Z0-9]*(-[A-Z0-9.]+)+$/;
/** Resolve a bare token against the eligible pinned namespaces of a field. Pure: `namespaces` is a list of
 *  `{namespace, pinned, ids: Set, lidFor(id), mint?}`; the answer is `unique` (exactly one namespace holds the id),
 *  `ambiguous` (several do — the caller emits AMBIGUOUS_IDENTIFIER and NO edge) or `absent`. Input order never
 *  matters: matches are sorted by lid. */
export function resolveBareToken(token, namespaces) {
  const matches = namespaces.filter((n) => n.ids.has(token)).map((n) => ({ namespace: n.namespace, pinned: n.pinned, lid: n.lidFor(token), mint: n.mint })).sort((a, b) => a.lid < b.lid ? -1 : a.lid > b.lid ? 1 : 0);
  if (matches.length === 1) return { status: "unique", match: matches[0] };
  if (matches.length > 1) return { status: "ambiguous", matches };
  return { status: "absent" };
}
const WITNESS_KIND = (p) => /compile-fail\//.test(p) ? "compile-fail-gate" : /\.tla$/.test(p) ? "tla-unexecuted" : /\.(py)$/.test(p) ? "model-check" : /\.(rs|ex|exs|mjs|js|sh)$/.test(p) ? "executable" : /\.md$/.test(p) ? "result-document" : /\.(json|log|txt)$/.test(p) ? "execution-output" : /\.tar\.gz$/.test(p) ? "bundle" : "file";

/** Which pinned repository a source_registry's paths live in (the package states these pins in prose; the
 *  snapshot carries them as sources). */
const REGISTRY_ROOT = { "cd-core-docs": "computedriven", "cd-durable-docs": "computedriven", "ampd-readme": "super", "trvm-law-registry": "trvm", "wrl-core": "trvm", "wek-w-laws": null, "claim-ledger": "factory", "r10pre-execution": "r10" };
const ADJ_DOC = (v, audit, pkg) => audit ? (v === "2" ? `${pkg}/inputs/FABLE51_R10PRE_V2_GPT56_AUDIT_FOR_OPUS.md` : null)
  : v === "1" ? "inputs-gpt-execution-adjudication.md" : v === "2" ? `${pkg}/inputs/R10PRE_EXECUTION_V2_GPT56_ADJUDICATION.md`
  : v === "3" ? `${pkg}/inputs/R10PRE_EXECUTION_V3_GPT56_ADJUDICATION.md` : v === "4" ? `${pkg}/inputs/R10PRE_EXECUTION_V4_GPT56_ADJUDICATION.md` : null;
const ADJ_SHORT = (v, audit) => audit ? `v${v}-audit` : `exec-v${v}`;

/**
 * @param ctx { snapshot, repos: {r10, computedriven?, super?, trvm?, wrl?}, packageDir: "package-v2.7", registryNamespace: "crosswalk" }
 * @returns Emitter output for the crosswalk and the evidence_state companion.
 */
export function ingestCrosswalk(ctx) {
  const { snapshot, repos, packageDir, treeRegistries = {} } = ctx;
  const r10 = repos.r10;
  const cwPath = `${packageDir}/CROSS_REGISTRY_CLAIM_MAP.json`, esPath = `${packageDir}/evidence_state.json`;
  const cwBlob = r10.blobOid(cwPath), esBlob = r10.blobOid(esPath);
  if (!cwBlob || !esBlob) throw new G0Error("SOURCE_MISSING", `${cwPath} or ${esPath} not at ${r10.commit}`);
  const cw = parseStrictJson(r10.bytes(cwPath));
  const es = parseStrictJson(r10.bytes(esPath));
  if (cw.number_forms.length) throw new G0Error("UNEXPECTED_NUMBER_FORM", `crosswalk has non-integer numbers: ${JSON.stringify(cw.number_forms)}`);
  const doc = cw.value, esDoc = es.value;
  const version = String(doc.crosswalk_version);
  const registryLid = makeLid("REGISTRY", "crosswalk", version).lid;
  const E = new Emitter({ snapshot, registry: registryLid, namespace: "crosswalk", pinned_identity: cwBlob, path: cwPath, treeRegistries });

  // ── helpers over pinned repos ─────────────────────────────────────────────────────────────────
  const headingIndex = new Map(); // repoName:path -> Map(sectionNumber -> line)
  const headings = (repo, path) => {
    const key = repo.name + ":" + path;
    if (!headingIndex.has(key)) {
      const m = new Map();
      if (repo.has(path)) repo.bytes(path).toString("utf8").split("\n").forEach((line, i) => { const h = /^#{1,3}\s+(\d+(?:\.\d+)?)[.)]?\s/.exec(line); if (h && !m.has(h[1])) m.set(h[1], i + 1); });
      headingIndex.set(key, m);
    }
    return headingIndex.get(key);
  };
  const resolveWitness = (raw) => {
    // strip a parenthetical note; split fragment; try roots in the contract's order
    let text = String(raw).trim(), note = null;
    const par = /^(.*?)\s+\((.*)\)\s*$/.exec(text); if (par) { text = par[1]; note = par[2]; }
    let fragment = null; const hash = text.indexOf("#"); if (hash >= 0) { fragment = text.slice(hash + 1); text = text.slice(0, hash); }
    const candidates = [["r10", r10, `${packageDir}/${text}`], ["r10", r10, text]];
    for (const [ns, key] of [["computedriven", "computedriven"], ["super", "super"], ["trvm", "trvm"], ["wrl", "wrl"], ["factory", "factory"]]) if (repos[key]) candidates.push([ns, repos[key], text]);
    for (const [ns, repo, p] of candidates) if (repo && repo.has(p)) return { ns, repo, path: p, blob: repo.blobOid(p), fragment, note, raw: String(raw) };
    // "ampd/test effect (7)": a DIRECTORY plus a suite name and a count is a test-suite label, not a file
    const dirTok = text.split(/\s+/)[0];
    for (const [ns, repo] of candidates) if (repo && [...repo.paths].some((q) => q.startsWith(dirTok + "/"))) return { ns: null, repo: null, path: text, blob: null, fragment, note, raw: String(raw), directory_label: { ns, dir: dirTok } };
    return { ns: null, repo: null, path: text, blob: null, fragment, note, raw: String(raw) };
  };

  const factoryIds = (() => { const f = repos.factory; if (!f || !f.has("CLAIM_LEDGER.json")) return null; try { return new Set(parseStrictJson(f.bytes("CLAIM_LEDGER.json")).value.claims.map((c) => c.claim_id)); } catch { return null; } })();
  /** D-031: every namespace a bare `source_ids` token could name at this pin. Adding a namespace here widens the
   *  ambiguity check, never the resolution: a token in two of them resolves to nothing. */
  const bareNamespaces = [];
  if (factoryIds) bareNamespaces.push({ namespace: "factory", pinned: `${repos.factory.name}@${repos.factory.commit}`, ids: factoryIds, lidFor: (id) => makeLid("CLAIM", "factory", id).lid, mint: (lid, lat) => E.node("CLAIM", lid, { claim_id: lid.slice("claim:factory:".length), registry_hint: "factory-ledger", present_in_pinned_ledger: true }, lat) });
  bareNamespaces.push({ namespace: "crosswalk", pinned: `${r10.name}@${r10.commit}`, ids: new Set(doc.records.map((x) => String(x.record_id))), lidFor: (id) => makeLid("CLAIM", "crosswalk", id).lid });
  bareNamespaces.push({ namespace: "inv", pinned: `${r10.name}@${r10.commit}`, ids: new Set([...Object.keys(doc.semantic_obligations || {}), ...Object.keys(doc.liveness_candidates || {}), ...Object.keys(doc.factory_candidates || {}), ...Object.keys(doc.resolved_candidates || {})]), lidFor: (id) => makeLid("OBLIGATION", "inv", id).lid });
  // ── the registry node ─────────────────────────────────────────────────────────────────────────
  const rootLoc = E.loc(null);
  const tokensUsed = [...new Set(doc.records.map((r) => r.evidence_class_token))].sort();
  const declaredCats = Object.keys(doc.semantic_obligations || {});
  const usedCats = new Set(doc.records.map((r) => r.semantic_obligation));
  E.node("REGISTRY", registryLid, {
    version, status_text: String(doc.status || ""), authority_class: "AUTHORITATIVE", registry_status: /^DRAFT/.test(String(doc.status || "")) ? "DRAFT" : "STATED",
    source_path: cwPath, blob: cwBlob, commit: r10.commit, repo: r10.name, vocabulary: "crosswalk", tokens_observed: tokensUsed,
    field_note: String(doc.field_note || ""), ontology: doc.ontology || [], untested_locus_roles: doc.untested_locus_roles || [], not_found_artifacts: doc.not_found_artifacts || [],
    declared_unused_categories: declaredCats.filter((c) => !usedCats.has(c)).sort(),
    adjudications_applied: Object.fromEntries(Object.entries(doc).filter(([k]) => /^adjudication_v/.test(k)).map(([k, v]) => [k, v])),
    execution_summaries: Object.keys(doc).filter((k) => /^execution_summary_/.test(k)).sort(),
  }, rootLoc);

  // ── obligations and categories ────────────────────────────────────────────────────────────────
  const obligationLid = (s) => makeLid("OBLIGATION", "inv", s).lid;
  const categoryLid = (c) => E.lid(CATEGORY_KIND[c], "crosswalk", c);
  const soLoc = E.loc("/semantic_obligations");
  for (const [k, name] of Object.entries(doc.semantic_obligations || {})) {
    if (OBLIGATION.test(k)) E.node("OBLIGATION", obligationLid(k), { code: k, name: String(name), axis: "safety", promotion: "working" }, soLoc);
    else if (CATEGORY_KIND[k]) E.node(CATEGORY_KIND[k], categoryLid(k), { code: k, name: String(name), category: true }, soLoc);
    else if (k !== "COR") E.fault("UNKNOWN_TOKEN", "crosswalk.semantic_obligations", `unknown obligation key ${k}`, [registryLid]);
  }
  const targetForObligation = (so, claimLid) => {
    if (OBLIGATION.test(so)) return obligationLid(so);
    if (CATEGORY_KIND[so]) return categoryLid(so);
    E.fault("UNKNOWN_TOKEN", "crosswalk.records.semantic_obligation", `record ${claimLid} names obligation ${JSON.stringify(so)}`, [claimLid]);
    return null;
  };

  // ── adjudication citations (`GPT v3 §12`, `GPT v2 audit §6`, `inputs/… §1–§2`) ────────────────
  const adjudicationNodes = (text, fromLid, at) => {
    const out = [];
    for (const m of String(text).matchAll(CITATION)) {
      const [, v, audit, s1, s2] = m; const docPath = ADJ_DOC(v, !!audit, packageDir); const short = ADJ_SHORT(v, !!audit);
      const secs = [s1]; if (s2) { const a = Number(s1), b = Number(s2); if (Number.isInteger(a) && Number.isInteger(b) && b > a && b - a < 40) for (let i = a + 1; i <= b; i++) secs.push(String(i)); else secs.push(s2); }
      for (const sec of secs) {
        const lid = E.lid("ADJUDICATION", "gpt", `${short}:s${sec}`);
        if (!docPath || !r10.has(docPath)) { E.fault("UNPARSEABLE_CITATION", "crosswalk.citations", `GPT v${v}${audit ? " audit" : ""} §${sec}: no pinned document for that version at ${r10.commit.slice(0, 7)}`, [fromLid]); continue; }
        const line = headings(r10, docPath).get(sec);
        const loc = E.loc(line ? `L${line}` : null, null, { path: docPath, pinned: r10.blobOid(docPath), namespace: "r10" });
        if (!line) E.fault("HEADING_WITHOUT_NUMBER", "crosswalk.citations", `no heading numbered ${sec} in ${docPath}`, [fromLid, lid]);
        E.node("ADJUDICATION", lid, { authority: "advisory", adjudicator: "GPT-5.6", document: docPath, section: sec, ...(line ? { line } : {}) }, at);
        E.rel("LOCATED_IN", lid, loc, at);
        E.rel("ADJUDICATED_BY", fromLid, lid, at, { asrt: { cited_as: m[0] } });
        out.push(lid);
      }
    }
    return out;
  };
  const adjudicationFromRef = (ref, fromLid, at) => {
    // "inputs/R10PRE_EXECUTION_V4_GPT56_ADJUDICATION.md §1–§2"
    const m = /^(\S+\.md)\s+§(\d+(?:\.\d+)?)(?:[–-]§?(\d+(?:\.\d+)?))?$/.exec(String(ref).trim());
    if (!m) { E.fault("UNPARSEABLE_CITATION", "crosswalk.adjudication_ref", `cannot parse ${JSON.stringify(ref)}`, [fromLid]); return []; }
    const rel = m[1]; const docPath = r10.has(`${packageDir}/${rel}`) ? `${packageDir}/${rel}` : r10.has(rel) ? rel : null;
    const vm = /_V(\d)_GPT56_(ADJUDICATION|AUDIT)/.exec(rel); const short = vm ? (vm[2] === "AUDIT" ? `v${vm[1]}-audit` : `exec-v${vm[1]}`) : rel.replace(/\.md$/, "");
    const secs = [m[2]]; if (m[3]) { const a = Number(m[2]), b = Number(m[3]); if (Number.isInteger(a) && Number.isInteger(b) && b > a && b - a < 40) for (let i = a + 1; i <= b; i++) secs.push(String(i)); else secs.push(m[3]); }
    const out = [];
    for (const sec of secs) {
      const lid = E.lid("ADJUDICATION", "gpt", `${short}:s${sec}`);
      if (!docPath) { E.fault("UNPARSEABLE_CITATION", "crosswalk.adjudication_ref", `${rel} is not at ${r10.commit.slice(0, 7)}`, [fromLid]); continue; }
      const line = headings(r10, docPath).get(sec);
      const loc = E.loc(line ? `L${line}` : null, null, { path: docPath, pinned: r10.blobOid(docPath), namespace: "r10" });
      if (!line) E.fault("HEADING_WITHOUT_NUMBER", "crosswalk.adjudication_ref", `no heading numbered ${sec} in ${docPath}`, [fromLid, lid]);
      E.node("ADJUDICATION", lid, { authority: "advisory", adjudicator: "GPT-5.6", document: docPath, section: sec, ...(line ? { line } : {}) }, at);
      E.rel("LOCATED_IN", lid, loc, at);
      E.rel("ADJUDICATED_BY", fromLid, lid, at, { asrt: { cited_as: String(ref) } });
      out.push(lid);
    }
    return out;
  };

  // ── witnesses / receipts ──────────────────────────────────────────────────────────────────────
  /** A witness node is ASSERTED where it is cited (`at`) and LOCATED_IN the pinned file it names; the citation's
   *  own note rides on the relation the caller adds, never on the node. */
  const witnessNode = (raw, claimLid, at, extraAttrs = {}) => {
    const w = resolveWitness(raw);
    if (!w.repo && w.directory_label) { E.fault("UNSUPPORTED_SOURCE_FORM", "crosswalk.witness_paths", `${JSON.stringify(w.raw)} is a test-suite label (directory ${w.directory_label.dir}/ in ${w.directory_label.ns} plus a suite name and a count), not a file`, [claimLid], { attrs: { text: w.raw, form: "directory-label" } }); return null; }
    if (!w.repo && !/[\/.]/.test(w.path)) { E.fault("UNSUPPORTED_SOURCE_FORM", "crosswalk.witness_paths", `${JSON.stringify(w.raw)} is a label (no path, no extension), not a file`, [claimLid], { attrs: { text: w.raw, form: "label" } }); return null; }
    if (!w.repo) { E.fault("DANGLING_WITNESS", "crosswalk.witness_paths", `${JSON.stringify(w.raw)} resolves under no pinned root (package, lane, computedriven, super, trvm, wrl, factory)`, [claimLid]); return null; }
    const lid = E.lid("WITNESS", w.ns, w.path + (w.fragment ? "#" + w.fragment : ""));
    const fileLoc = E.loc(w.fragment ? w.fragment : null, null, { path: w.path, pinned: w.blob, namespace: w.ns });
    E.node("WITNESS", lid, { path: w.path, root: w.ns, blob: w.blob, commit: w.repo.commit, kind: WITNESS_KIND(w.path), ...(w.fragment ? { fragment: w.fragment } : {}), ...extraAttrs }, at);
    E.rel("LOCATED_IN", lid, fileLoc, at);
    return { lid, note: w.note };
  };
  /** The RECEIPT node carries what is true of the receipt itself; this citation's role/type/what and the promotion's
   *  `executed` flag ride on the WITNESSES assertion (D-029), so one receipt cited as sensitivity AND repair witness of
   *  one claim is ONE relation with two assertions. `executed` on the assertion is what `has_exec_receipt` reads. */
  const receiptNode = (rc, at, claimLid, role, executed) => {
    // rc: {type?, receipt, sha256, what?}
    const w = resolveWitness(rc.receipt);
    const lid = makeLid("RECEIPT", "sha256", rc.sha256).lid;
    let verified = null;
    if (w.repo) verified = w.repo.sha256(w.path) === rc.sha256;
    else E.fault("DANGLING_WITNESS", "crosswalk.promotions.receipts", `receipt ${JSON.stringify(rc.receipt)} resolves under no pinned root`, [claimLid]);
    if (verified === false) E.fault("SOURCE_MOVED", "crosswalk.promotions.receipts", `receipt ${rc.receipt} hashes differently at the pin than the recorded ${rc.sha256}`, [claimLid, lid]);
    // the node carries what is true of the receipt itself; the citation's role/type/what ride on the relation
    E.node("RECEIPT", lid, { path: w.path, sha256: rc.sha256, ...(w.repo ? { root: w.ns, blob: w.blob, commit: w.repo.commit } : {}), sha256_verified_at_pin: verified === null ? { unknown: "source-dangling" } : verified }, at);
    if (w.repo) E.rel("LOCATED_IN", lid, E.loc(null, null, { path: w.path, pinned: w.blob, namespace: w.ns }), at);
    E.rel("WITNESSES", lid, claimLid, at, { asrt: { role, outcome: { unknown: "not-stated" }, ...(executed !== undefined ? { executed: !!executed } : {}), ...(rc.type ? { sensitivity_type: String(rc.type) } : {}), ...(rc.what ? { what: String(rc.what) } : {}) } });
    return lid;
  };

  // ── records ───────────────────────────────────────────────────────────────────────────────────
  const records = doc.records; const byId = new Map(records.map((r, i) => [r.record_id, i]));
  const claimLids = new Map();
  records.forEach((r, i) => {
    const ptr = `/records/${i}`; const at = E.loc(ptr);
    if (!RECORD_ID.test(String(r.record_id))) { E.fault("AMBIGUOUS_IDENTIFIER", "crosswalk.records.record_id", `record ${i} has id ${JSON.stringify(r.record_id)}`, [registryLid]); return; }
    const claim = makeLid("CLAIM", "crosswalk", r.record_id).lid; claimLids.set(r.record_id, claim);
    const token = String(r.evidence_class_token || "");
    const history = [];
    for (const [ver, field] of [["v2.3-before", "evidence_class_before_v2_3"], ["v2.4", "evidence_class_v2_4"], ["v2.5", "evidence_class_token_v2_5"], ["v2.6", "evidence_class_token_v2_6"]]) if (r[field] != null) history.push({ version: ver, token_or_text: String(r[field]) });
    const attrs = {
      name: String(r.name || ""), source_registry: String(r.source_registry || ""), source_ids: (r.source_ids || []).map(String), relation: String(r.relation || ""),
      semantic_obligation: String(r.semantic_obligation || ""), evidence_class_text: String(r.evidence_class || ""), token_family: TOKEN_FAMILY(token),
      scope_profile_text: r.scope_profile == null ? "" : String(r.scope_profile), derivation_links_raw: (r.derivation_links || []).map(String), history,
      receipts_typed: false,
      ...(r.executed != null ? { executed: !!r.executed } : {}), ...(r.executed_by ? { executed_by: String(r.executed_by) } : {}), ...(r.runtime ? { runtime: String(r.runtime) } : {}),
      ...(r.promoted_in ? { promoted_in: String(r.promoted_in) } : {}), ...(r.split_from ? { split_from: String(r.split_from) } : {}),
      ...(r.trust_profile ? { trust_profile_text: String(r.trust_profile) } : {}), ...(r.conditions ? { conditions: r.conditions.map(String) } : {}),
      ...(r.tested ? { tested: r.tested.map(String) } : {}), ...(r.not_tested ? { not_tested: r.not_tested.map(String) } : {}),
      ...(r.committed ? { committed: r.committed.map(String) } : {}), ...(r.not_claimed ? { not_claimed: r.not_claimed.map(String) } : {}),
      ...(r.adjudicator ? { adjudicator: String(r.adjudicator) } : {}), ...(r.adjudicated_at ? { adjudicated_at: String(r.adjudicated_at) } : {}), ...(r.history_note ? { history_note: String(r.history_note) } : {}),
    };
    E.node("CLAIM", claim, attrs, at, { extra: { evidence_state: { token, vocabulary: "crosswalk" } } });
    E.rel("MEMBER_OF", claim, registryLid, at);
    // obligation relation
    const relKind = RELATION_BY_FIELD[r.relation];
    if (!relKind) E.fault("UNKNOWN_TOKEN", "crosswalk.records.relation", `record ${r.record_id} relation ${JSON.stringify(r.relation)}`, [claim]);
    else { const t = targetForObligation(String(r.semantic_obligation), claim); if (t) E.rel(relKind, claim, t, E.loc(`${ptr}/relation`), { attrs: { relation_field: r.relation } }); }
    // token history → transitions (version chain), observed; the typed promotion, if any, is attached below.
    // D-037: no SUPERSEDES is emitted along the chain — supersession is never inferred from temporal order.
    const chain = [...history.map((h) => h.token_or_text), token];
    for (let k = 1; k < chain.length; k++) if (chain[k] !== chain[k - 1]) {
      const tl = E.lid("EVIDENCE_STATE_TRANSITION", "crosswalk", `${r.record_id}:${history[k - 1]?.version || "?"}->${k < history.length ? history[k].version : "current"}`);
      E.node("EVIDENCE_STATE_TRANSITION", tl, { record: r.record_id, from_text: chain[k - 1], to_text: chain[k], typed: false }, E.loc(`${ptr}/${k < history.length ? ["evidence_class_before_v2_3", "evidence_class_v2_4", "evidence_class_token_v2_5", "evidence_class_token_v2_6"].find((f) => r[f] != null && history[k]?.token_or_text === String(r[f])) || "evidence_class_token" : "evidence_class_token"}`));
      E.rel("STATE_TRANSITION_OF", tl, claim, at, { attrs: { from_text: chain[k - 1], to_text: chain[k] } }); // D-037: a transition moves the claim's state; it never SUPERSEDES the claim
    }
    // witnesses
    (r.witness_paths || []).forEach((wp, j) => { const lat = E.loc(`${ptr}/witness_paths/${j}`); const w = witnessNode(wp, claim, lat); if (w) E.rel("WITNESSES", w.lid, claim, lat, { asrt: { outcome: { unknown: "not-stated" }, ...(w.note ? { note: w.note } : {}) } }); });
    // scope / trust / conditions
    if (r.scope_profile) { const p = E.lid("PROFILE", "text", String(r.scope_profile)); E.node("PROFILE", p, { text: String(r.scope_profile), unnormalized: true, role: "scope" }, E.loc(`${ptr}/scope_profile`)); E.rel("SCOPED_BY", claim, p, E.loc(`${ptr}/scope_profile`)); }
    if (r.trust_profile) { const p = E.lid("PROFILE", "text", String(r.trust_profile)); E.node("PROFILE", p, { text: String(r.trust_profile), unnormalized: true, role: "trust" }, E.loc(`${ptr}/trust_profile`)); E.rel("TESTED_UNDER", claim, p, E.loc(`${ptr}/trust_profile`)); }
    (r.conditions || []).forEach((c, j) => { const a = E.lid("ASSUMPTION", "text", String(c)); E.node("ASSUMPTION", a, { text: String(c), unnormalized: true }, E.loc(`${ptr}/conditions/${j}`)); E.rel("ASSUMES", claim, a, E.loc(`${ptr}/conditions/${j}`)); });
    // derivation links
    (r.derivation_links || []).forEach((d, j) => {
      const lat = E.loc(`${ptr}/derivation_links/${j}`);
      if (RECORD_ID.test(String(d))) { if (byId.has(d)) E.rel("DERIVES_FROM", claim, makeLid("CLAIM", "crosswalk", d).lid, lat); else E.fault("UNRESOLVED_LINK", "crosswalk.derivation_links", `${r.record_id} → ${d}: no such record at this pin (retired by a split?)`, [claim], { attrs: { text: String(d), reason: "retired-id" } }); }
      else if (/^law:[a-z][a-z0-9.-]*@\d+$/.test(String(d).trim())) { const l = E.lid("LAW", "trvm", String(d).trim().slice(4)); E.node("LAW", l, { citation: String(d).trim(), registry_hint: "trvm-grid" }, lat, { precision: "pointer" }); E.rel("CITES", claim, l, lat); }
      else E.fault("UNRESOLVED_LINK", "crosswalk.derivation_links", `${r.record_id} link ${j} is prose, not a reference`, [claim], { attrs: { text: String(d), reason: "prose" } });
    });
    // split_from
    if (r.split_from) { const parent = makeLid("CLAIM", "crosswalk", String(r.split_from)).lid; if (!byId.has(r.split_from)) E.node("CLAIM", parent, { name: `${r.split_from} (retired by split)`, superseded_by_split: true, source_registry: String(r.source_registry || "") }, E.loc(`${ptr}/split_from`)); E.rel("SPLIT_FROM", claim, parent, E.loc(`${ptr}/split_from`)); }
    // adjudication refs and in-text citations
    if (r.adjudication_ref) adjudicationFromRef(r.adjudication_ref, claim, E.loc(`${ptr}/adjudication_ref`));
    adjudicationNodes(`${r.evidence_class || ""} ${(r.derivation_links || []).join(" ")}`, claim, E.loc(`${ptr}/evidence_class`));
    // source ids → locations, mechanisms, laws, experiments, cells, factory claims
    (r.source_ids || []).forEach((sid, j) => {
      const s = String(sid).trim(); const lat = E.loc(`${ptr}/source_ids/${j}`); const rootName = REGISTRY_ROOT[r.source_registry]; const repo = rootName ? repos[rootName] : null;
      const sym = CODE_SYMBOL.exec(s);
      if (sym) {
        const [, path, symbol] = sym;
        if (repo && repo.has(path)) {
          const text = repo.bytes(path).toString("utf8").split("\n"); const re = new RegExp(`\\b${symbol.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`);
          const line = text.findIndex((ln) => re.test(ln)) + 1;
          const loc = E.loc(line ? `L${line}` : null, line ? "symbol" : "file", { path, pinned: repo.blobOid(path), namespace: rootName });
          const mech = E.lid("MECHANISM", rootName, symbol);
          E.node("MECHANISM", mech, { symbol, path, repo: repo.name, commit: repo.commit, ...(line ? { line } : {}) }, lat);
          E.rel("LOCATED_IN", mech, loc, lat); E.rel("LOCATED_IN", claim, loc, lat); E.rel("CITES", claim, mech, lat, { asrt: { source_id: s } });
          if (r.relation === "mechanism") { const t = targetForObligation(String(r.semantic_obligation), claim); if (t) E.rel("IMPLEMENTS", mech, t, lat, { asrt: { asserted_by_record: r.record_id } }); }
          if (!line) E.fault("UNSUPPORTED_SOURCE_FORM", "crosswalk.source_ids", `symbol ${symbol} not found in ${path} at ${repo.commit.slice(0, 7)}`, [claim, mech]);
        } else E.fault("DANGLING_WITNESS", "crosswalk.source_ids", `${s}: ${path} not in ${rootName || "an unpinned root"}`, [claim]);
      } else if (/^law:[a-z][a-z0-9.-]*@\d+$/.test(s)) { const l = E.lid("LAW", "trvm", s.slice(4)); E.node("LAW", l, { citation: s, registry_hint: "trvm-grid" }, lat); E.rel("CITES", claim, l, lat); }
      else if (/^W-\d+$/.test(s)) { const l = makeLid("LAW", "wek", s).lid; E.node("LAW", l, { code: s, registry_hint: "wek-w-laws" }, lat); E.rel("CITES", claim, l, lat); }
      else if (/^claim-ledger:/.test(s)) {
        for (const id of s.slice("claim-ledger:".length).split("/").map((x) => x.trim()).filter(Boolean)) {
          const f = E.lid("CLAIM", "factory", id); const known = factoryIds ? factoryIds.has(id) : null;
          E.node("CLAIM", f, { claim_id: id, registry_hint: "factory-ledger", ...(known === null ? {} : { present_in_pinned_ledger: known }) }, lat); E.rel("CITES", claim, f, lat, { asrt: { source_id: s, qualified: true } });
          if (known === false) E.fault("UNRESOLVED_LINK", "crosswalk.source_ids", `${s}: ${id} is not a claim_id in the pinned CLAIM_LEDGER.json`, [claim], { attrs: { text: s } });
        }
      }
      else if (/^cells\.json:/.test(s)) { const m = /^cells\.json:(\S+)/.exec(s); const c = E.lid("CELL", "cells", m[1]); E.node("CELL", c, { num: m[1], registry_hint: "cells" }, lat); E.rel("BINDS", claim, c, lat, { asrt: { source_id: s } }); if (s.length > m[0].length) E.fault("AMBIGUOUS_IDENTIFIER", "crosswalk.source_ids", `${s}: trailing text after the cell number`, [claim]); }
      else if (/^(EXP-\d+[a-z]?|S6\? falsifier)/.test(s)) { const m = /^(EXP-\d+[a-z]?|S6\? falsifier)\s*(.*)$/.exec(s); const x = E.lid("EXPERIMENT", "r10", m[1] === "S6? falsifier" ? "S6-falsifier" : m[1]); E.node("EXPERIMENT", x, { label: m[1] }, lat); E.rel("PRODUCED_BY", claim, x, lat, { asrt: { source_id: s, ...(m[2] ? { part: m[2] } : {}) } }); }
      else if (PATHISH.test(s) || /\.md\s+§/.test(s) || /\.md\s+R\d/.test(s) || /\.md\s+\S+/.test(s)) {
        const pm = /^(\S+?\.(?:md|rs|ex|exs|mjs|js|py|sh|json|txt))(?:\s+(.*))?$/.exec(s);
        if (pm && repo && repo.has(pm[1])) { const loc = E.loc(pm[2] ? pm[2] : null, pm[2] ? "heading" : "file", { path: pm[1], pinned: repo.blobOid(pm[1]), namespace: rootName }); E.rel("LOCATED_IN", claim, loc, lat, { asrt: { source_id: s } }); }
        else E.fault("DANGLING_WITNESS", "crosswalk.source_ids", `${s} not found in ${rootName || "an unpinned root"} (registry ${r.source_registry})`, [claim]);
      }
      else if (r.source_registry === "claim-ledger" && BARE_TOKEN.test(s)) {
        // D-031: a bare token (E-40/E-41 write factory claim ids without the `claim-ledger:` prefix) is resolved only when
        // it matches exactly one eligible pinned namespace; the raw token is kept, the resolution basis recorded, and the
        // source defect reported as a non-blocking UNQUALIFIED_REFERENCE. Two matches → AMBIGUOUS_IDENTIFIER, no edge.
        const res = resolveBareToken(s, bareNamespaces);
        if (res.status === "unique") {
          const target = res.match.lid; if (res.match.mint) res.match.mint(target, lat);
          E.rel("CITES", claim, target, lat, { asrt: { source_id: s, raw_token: s, qualified: false, resolution_basis: "unique-pinned-match", resolved_namespace: res.match.namespace, resolved_in: res.match.pinned } });
          E.fault("UNQUALIFIED_REFERENCE", "crosswalk.source_ids", `${r.record_id} source_id ${JSON.stringify(s)} names ${target} without a namespace; resolved because it matches exactly one eligible pinned namespace (${res.match.namespace}); the source should write the qualified form`, [claim, target], { attrs: { text: s, resolved_to: target, resolution_basis: "unique-pinned-match" } });
        } else if (res.status === "ambiguous") E.fault("AMBIGUOUS_IDENTIFIER", "crosswalk.source_ids", `${r.record_id} source_id ${JSON.stringify(s)} matches ${res.matches.length} eligible namespaces (${res.matches.map((m) => m.namespace).join(", ")}); no edge emitted`, [claim], { attrs: { text: s, candidates: res.matches.map((m) => m.lid).sort() } });
        else E.fault("UNRESOLVED_LINK", "crosswalk.source_ids", `${r.record_id} source_id ${JSON.stringify(s)} is a bare token that matches no eligible pinned namespace`, [claim], { attrs: { text: s, reason: "bare-token-absent" } });
      }
      else if (/^WRL_CORE_/.test(s)) {
        const m = /^WRL_CORE_(\d+\.\d+)\s+§(\d+(?:\.\d+)?)/.exec(s); const trvm = repos.trvm; const docPath = m ? `WRL_CORE_${m[1]}.md` : null;
        if (m && trvm && trvm.has(docPath)) {
          const line = headings(trvm, docPath).get(m[2]);
          const loc = E.loc(line ? `L${line}` : null, null, { path: docPath, pinned: trvm.blobOid(docPath), namespace: "trvm" });
          E.rel("LOCATED_IN", claim, loc, lat, { asrt: { source_id: s, section: m[2] } });
          if (!line) E.fault("HEADING_WITHOUT_NUMBER", "crosswalk.source_ids", `${s}: no heading numbered ${m[2]} in TRVM ${docPath} at ${trvm.commit.slice(0, 7)}`, [claim]);
        } else E.fault("DANGLING_WITNESS", "crosswalk.source_ids", `${s}: WRL_CORE document not in the pinned TRVM tree`, [claim]);
      }
      else E.fault("UNRESOLVED_LINK", "crosswalk.source_ids", `${r.record_id} source_id ${JSON.stringify(s)} is a label, not a resolvable reference`, [claim], { attrs: { text: s } });
    });
  });

  // ── promotions ────────────────────────────────────────────────────────────────────────────────
  (doc.promotions || []).forEach((p, i) => {
    const ptr = `/promotions/${i}`; const at = E.loc(ptr); const claim = claimLids.get(p.record_id);
    if (!claim) { E.fault("UNRESOLVED_LINK", "crosswalk.promotions", `promotion ${i} names unknown record ${p.record_id}`, [registryLid]); return; }
    const tl = E.lid("EVIDENCE_STATE_TRANSITION", "crosswalk", `${p.record_id}:promotion:${p.promoted_in || "?"}`);
    const truncated = /…$/.test(String(p.to || ""));
    if (truncated) E.fault("TRUNCATED_FIELD", "crosswalk.promotions.to", `promotion ${p.record_id}: 'to' ends with an ellipsis in the source`, [tl]);
    E.node("EVIDENCE_STATE_TRANSITION", tl, {
      record: p.record_id, typed: true, promoted_in: String(p.promoted_in || ""), from_text: p.from == null ? "" : String(p.from), to_text: String(p.to || ""), to_truncated: truncated,
      ...(p.from_token !== undefined ? { from_token: p.from_token == null ? "" : String(p.from_token) } : {}), ...(p.to_token ? { to_token: String(p.to_token) } : {}),
      executed: !!p.executed, ...(p.executed_by ? { executed_by: String(p.executed_by) } : {}), ...(p.runtime ? { runtime: String(p.runtime) } : {}), ...(p.cross_lane !== undefined ? { cross_lane: !!p.cross_lane } : {}),
      history: (p.history || []).map(String),
    }, at);
    E.rel("STATE_TRANSITION_OF", tl, claim, at, { attrs: { typed: true } }); // D-037
    if (p.sensitivity_witness?.receipt) { const sat = E.loc(`${ptr}/sensitivity_witness`); const rc = receiptNode(p.sensitivity_witness, sat, claim, "sensitivity", p.executed); E.rel("WITNESSES", rc, tl, sat, { asrt: { role: "sensitivity", type: String(p.sensitivity_witness.type || ""), executed: !!p.executed } }); }
    if (p.pre_fix_witness?.receipt) receiptNode({ ...p.pre_fix_witness, type: "pre-fix" }, E.loc(`${ptr}/pre_fix_witness`), claim, "pre-fix", p.executed);
    if (p.repair_witness?.receipt) receiptNode({ ...p.repair_witness, type: "repair" }, E.loc(`${ptr}/repair_witness`), claim, "repair", p.executed);
    if (p.subject_identity) {
      const s = p.subject_identity; const al = s.commit ? E.lid("ARTIFACT", "git", `${s.repo}@${s.commit}`) : E.lid("ARTIFACT", "sha256", String(s.artifact_sha256 || "unknown"));
      E.node("ARTIFACT", al, { repo: String(s.repo || ""), ...(s.commit ? { commit: String(s.commit) } : {}), ...(s.tree ? { tree: String(s.tree) } : {}), ...(s.artifact ? { artifact: String(s.artifact) } : {}), ...(s.artifact_sha256 ? { artifact_sha256: String(s.artifact_sha256) } : {}) }, E.loc(`${ptr}/subject_identity`));
      E.rel("PRODUCED_BY", tl, al, E.loc(`${ptr}/subject_identity`));
    }
    if (p.adjudication_ref) adjudicationFromRef(p.adjudication_ref, tl, E.loc(`${ptr}/adjudication_ref`));
  });

  /** One rule for both emitters (D-028 §5 as amended by D-030): a sentence that LEADS with an F-id is that finding;
   *  every other F-id it names is a citation (`CITES`), not an opened finding. A sentence with no leading id is an
   *  UNNAMED finding whose identity is context-bound — hash(container ‖ NUL ‖ exact sentence) where the container is
   *  the ROUND whose `open_findings` list holds it (the nearest authoritative semantic container both registries can
   *  name deterministically) — so the crosswalk and evidence_state quoting one sentence under R0.8 meet on one lid,
   *  while the same words under another round are another finding. The raw sentence stays on the node. */
  const openFindings = (X, round, text, at) => {
    const lead = /^\s*(F\d{1,2})\b/.exec(text); const named = [...new Set([...text.matchAll(F_ID)].map((m) => "F" + m[1]))];
    const fl = lead ? makeLid("FINDING", "computedriven", lead[1]).lid : contextBoundLid("FINDING", "inv", round, text);
    X.node("FINDING", fl, lead ? { code: lead[1] } : { unnamed: true, text, container: round, identity: "context-bound:sha256(container|NUL|sentence)[:16]" }, at);
    X.rel("OPENS", round, fl, at, { asrt: { as_of: version, text } });
    for (const id of named) if (!lead || id !== lead[1]) { const cited = makeLid("FINDING", "computedriven", id).lid; X.node("FINDING", cited, { code: id }, at); X.rel("CITES", fl, cited, at, { asrt: { mention: true } }); }
  };
  // ── r0_8 ──────────────────────────────────────────────────────────────────────────────────────
  if (doc.r0_8) {
    const b = doc.r0_8; const at = E.loc("/r0_8"); const round = makeLid("ROUND", "computedriven", "R0.8").lid;
    E.node("ROUND", round, { status: String(b.status || ""), why: String(b.why || ""), ...(b.f35_status ? { f35_status: String(b.f35_status) } : {}), ...(b.profile ? { profile: b.profile.map(String) } : {}), historical: (b.historical || []).map(String), shipped_not_adjudicated: (b.shipped_not_adjudicated || []).map(String), ...(b.out_of_scope_profile ? { out_of_scope_profile: b.out_of_scope_profile.map(String) } : {}) }, at);
    (b.open_findings || []).forEach((f, j) => openFindings(E, round, String(f), E.loc(`/r0_8/open_findings/${j}`)));
    (b.closed_by_adjudication_v3 || []).forEach((c, j) => {
      const lat = E.loc(`/r0_8/closed_by_adjudication_v3/${j}`); const ids = [...String(c).matchAll(F_ID)].map((m) => "F" + m[1]); const seen = new Set();
      for (const id of ids) { if (seen.has(id)) continue; seen.add(id); const fl = makeLid("FINDING", "computedriven", id).lid; E.node("FINDING", fl, { code: id }, lat); const adj = E.lid("ADJUDICATION", "gpt", "exec-v3:closures"); E.node("ADJUDICATION", adj, { authority: "advisory", adjudicator: "GPT-5.6", document: ADJ_DOC("3", false, packageDir), section: "1-8" }, lat); E.rel("CLOSES", adj, fl, lat, { asrt: { text: String(c) } }); }
      if (!ids.length) E.fault("UNPARSEABLE_CITATION", "crosswalk.r0_8.closed_by_adjudication_v3", `no F-id in ${JSON.stringify(c)}`, [round]);
    });
    adjudicationNodes(String(b.why || ""), round, at);
  }
  // ── liveness / factory / resolved candidates ──────────────────────────────────────────────────
  for (const [k, v] of Object.entries(doc.liveness_candidates || {})) {
    const at = E.loc(`/liveness_candidates/${k.replace(/~/g, "~0").replace(/\//g, "~1")}`); const ol = E.lid("OBLIGATION", "inv", k);
    E.node("OBLIGATION", ol, { code: k, axis: "liveness", promotion: "candidate", name: String(v.name || ""), statement: String(v.statement || ""), status_text: String(v.status || ""), source_text: String(v.source || "") }, at);
    (v.witnesses || []).forEach((w, j) => { const raw = typeof w === "string" ? w : w.path || w.file || JSON.stringify(w); const lat = E.loc(`/liveness_candidates/${k.replace(/\//g, "~1")}/witnesses/${j}`); const wl = witnessNode(raw, ol, lat); if (wl) E.rel("WITNESSES", wl.lid, ol, lat, { asrt: { outcome: { unknown: "not-stated" }, ...(typeof w === "object" ? { declared: Object.fromEntries(Object.entries(w).filter(([kk]) => /^[a-z_]+$/.test(kk)).map(([kk, vv]) => [kk, typeof vv === "string" ? vv : JSON.stringify(vv)])) } : {}) } }); });
    for (const m of v.mechanism_instances_seen || []) E.fault("UNSUPPORTED_SOURCE_FORM", "crosswalk.liveness_candidates.mechanism_instances_seen", `prose mechanism ${JSON.stringify(m)} (D-021: not minted)`, [ol], { attrs: { text: String(m) } });
  }
  for (const [k, v] of Object.entries(doc.factory_candidates || {})) {
    const at = E.loc(`/factory_candidates/${k}`); const ol = E.lid("OBLIGATION", "inv", k);
    E.node("OBLIGATION", ol, { code: k, axis: "factory-epistemic", promotion: "candidate", statement: String(v.statement || ""), status_text: String(v.status || ""), source_text: String(v.source || ""), ...(v.generic_rules_v3 ? { generic_rules: v.generic_rules_v3.map(String) } : {}) }, at);
    if (v.handoff) { const lat = E.loc(`/factory_candidates/${k}/handoff`); const wl = witnessNode(String(v.handoff), ol, lat); if (wl) E.rel("WITNESSES", wl.lid, ol, lat, { asrt: { outcome: { unknown: "not-stated" }, role: "handoff" } }); }
  }
  for (const [k, text] of Object.entries(doc.resolved_candidates || {})) {
    const at = E.loc(`/resolved_candidates/${k}`); const ol = E.lid("OBLIGATION", "inv", k);
    E.node("OBLIGATION", ol, { code: k, axis: "safety", promotion: "resolved-into", disposition_text: String(text) }, at);
    const into = /S1\(/.test(String(text)) ? obligationLid("S1") : null;
    if (into) E.rel("REDUCES_TO", ol, into, at, { asrt: { disposition: String(text) } }); else E.fault("UNPARSEABLE_CITATION", "crosswalk.resolved_candidates", `cannot read the target obligation from ${JSON.stringify(text)}`, [ol]);
    for (const m of String(text).matchAll(/\b(E-\d{2}[abc]?)\b/g)) if (claimLids.has(m[1])) E.rel("CITES", ol, claimLids.get(m[1]), at, { asrt: { role: "evidence-record" } });
  }
  // ── package-level witnesses hash table and the projection block ───────────────────────────────
  for (const [file, sha] of Object.entries(doc.witnesses || {})) {
    const at = E.loc(`/witnesses/${file.replace(/~/g, "~0").replace(/\//g, "~1")}`); const w = resolveWitness(file.includes("/") ? file : `witnesses/${file}`);
    if (!w.repo) { E.fault("DANGLING_WITNESS", "crosswalk.witnesses", `${file} not at the pin`, [registryLid]); continue; }
    const ok = w.repo.sha256(w.path) === sha; const wl = E.lid("WITNESS", w.ns, w.path);
    E.node("WITNESS", wl, { path: w.path, root: w.ns, blob: w.blob, commit: w.repo.commit, kind: WITNESS_KIND(w.path), sha256_recorded: String(sha), sha256_verified_at_pin: ok }, at);
    E.rel("LOCATED_IN", wl, E.loc(null, null, { path: w.path, pinned: w.blob, namespace: w.ns }), at);
    if (!ok) E.fault("SOURCE_MOVED", "crosswalk.witnesses", `${file} hashes differently at the pin than recorded`, [wl]);
  }
  if (doc.projection) {
    const ok = r10.sha256(esPath) === doc.projection.sha256;
    if (!ok) E.fault("CONTRADICTION", "crosswalk.projection", `projection.sha256 ${doc.projection.sha256} != sha256 of pinned ${esPath}`, [registryLid]);
  }

  // ── evidence_state.json — the DERIVED companion: cross-checked, never trusted over the crosswalk ─
  const esRegistry = makeLid("REGISTRY", "evstate", version).lid;
  const F = new Emitter({ snapshot, registry: esRegistry, namespace: "evstate", pinned_identity: esBlob, path: esPath, treeRegistries });
  F.node("REGISTRY", esRegistry, { schema: String(esDoc.schema || ""), source_text: String(esDoc.source || ""), authority_class: "DERIVED", ...(esDoc.generated_by ? { generated_by: String(esDoc.generated_by) } : {}), source_path: esPath, blob: esBlob, commit: r10.commit, repo: r10.name, derived_counts: esDoc.derived_counts || {} }, F.loc(""));
  const esById = new Map((esDoc.records || []).map((r, i) => [r.id, [r, i]]));
  for (const [id, [r, i]] of esById) {
    const claim = claimLids.get(id); const ptr = `/records/${i}`; const at = F.loc(ptr);
    if (!claim) { F.fault("UNRESOLVED_LINK", "evstate.records", `evidence_state record ${id} has no crosswalk record`, [esRegistry]); continue; }
    const cwRec = records[byId.get(id)];
    if (String(r.class) !== String(cwRec.evidence_class_token)) F.fault("CONTRADICTION", "evstate.class", `${id}: evidence_state class ${r.class} != crosswalk token ${cwRec.evidence_class_token}`, [claim]);
    const prevField = cwRec.evidence_class_token_v2_6 != null ? "evidence_class_token_v2_6" : "evidence_class_token_v2_5";
    if (r.class_prev != null && cwRec[prevField] != null && String(r.class_prev) !== String(cwRec[prevField])) F.fault("CONTRADICTION", "evstate.class_prev", `${id}: class_prev ${r.class_prev} != crosswalk ${prevField} ${cwRec[prevField]}`, [claim]);
    F.node("CLAIM", claim, { evstate_class: String(r.class || ""), ...(r.class_prev != null ? { evstate_class_prev: String(r.class_prev) } : {}), evstate_receipts_count: (r.receipts || []).length, ...(r.executed != null ? { evstate_executed: !!r.executed } : {}) }, at);
    F.rel("MEMBER_OF", claim, esRegistry, at);
    (r.receipts || []).forEach((rp, j) => { const w = resolveWitness(String(rp)); const lat = F.loc(`${ptr}/receipts/${j}`); if (!w.repo && w.directory_label) { F.fault("UNSUPPORTED_SOURCE_FORM", "evstate.receipts", `${JSON.stringify(rp)} is a test-suite label, not a file`, [claim], { attrs: { text: String(rp), form: "directory-label" } }); return; } if (!w.repo && !/[\/.]/.test(w.path)) { F.fault("UNSUPPORTED_SOURCE_FORM", "evstate.receipts", `${JSON.stringify(rp)} is a label, not a file`, [claim], { attrs: { text: String(rp), form: "label" } }); return; } if (!w.repo) { F.fault("DANGLING_WITNESS", "evstate.receipts", `${JSON.stringify(rp)} resolves under no pinned root`, [claim]); return; } const wl = F.lid("WITNESS", w.ns, w.path + (w.fragment ? "#" + w.fragment : "")); const loc = F.loc(w.fragment || null, null, { path: w.path, pinned: w.blob, namespace: w.ns }); F.node("WITNESS", wl, { path: w.path, root: w.ns, blob: w.blob, commit: w.repo.commit, kind: WITNESS_KIND(w.path), ...(w.fragment ? { fragment: w.fragment } : {}) }, lat); F.rel("LOCATED_IN", wl, loc, lat); F.rel("WITNESSES", wl, claim, lat, { asrt: { outcome: { unknown: "not-stated" }, listed_as: "receipt", ...(w.note ? { note: w.note } : {}) } }); });
  }
  (esDoc.statuses || []).forEach((s, i) => {
    const at = F.loc(`/statuses/${i}`); const round = makeLid("ROUND", "computedriven", String(s.id)).lid;
    F.node("ROUND", round, { evstate_status: String(s.status || ""), ...(s.profile ? { profile: s.profile.map(String) } : {}), ...(s.out_of_scope ? { out_of_scope: s.out_of_scope.map(String) } : {}) }, at);
    (s.open_findings || []).forEach((f, j) => openFindings(F, round, String(f), F.loc(`/statuses/${i}/open_findings/${j}`)));
  });
  (esDoc.artifacts || []).forEach((a, i) => {
    const at = F.loc(`/artifacts/${i}`); const w = resolveWitness(String(a.id));
    if (!w.repo) { F.fault("DANGLING_WITNESS", "evstate.artifacts", `${a.id} not at the pin`, [esRegistry]); return; }
    const wl = F.lid("WITNESS", w.ns, w.path); const loc = F.loc(null, null, { path: w.path, pinned: w.blob, namespace: w.ns });
    F.node("WITNESS", wl, { path: w.path, root: w.ns, blob: w.blob, commit: w.repo.commit, kind: WITNESS_KIND(w.path), executed: !!a.executed, class_text: String(a.class || "") }, at);
    F.rel("LOCATED_IN", wl, loc, at);
    const l1 = Object.keys(doc.liveness_candidates || {})[0]; if (l1) F.rel("WITNESSES", wl, E.lid("OBLIGATION", "inv", l1), at, { asrt: { outcome: { unknown: "not-stated" }, executed: !!a.executed } });
  });
  return { crosswalk: E.output(), evidence_state: F.output(), meta: { version, cwBlob, esBlob, records: records.length } };
}
