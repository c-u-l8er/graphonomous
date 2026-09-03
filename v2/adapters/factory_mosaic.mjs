/* factory_mosaic.mjs — the invariant factory's ARGUMENT / DEFEATER / INSTRUMENT layer, the part
 * `graphonomous.semantic.v0` had no home for (G0-F, D-056) and `graphonomous.semantic.v1` admits (D-062/D-064).
 *
 * SEPARATE ADAPTER, ON PURPOSE. `adapters/factory.mjs` emits the v0-safe core and is not touched: a v0 snapshot names
 * `["crosswalk", "factory"]` and reconstructs byte-identically, and a v1 snapshot names
 * `["crosswalk", "factory", "factory_mosaic"]`. The layer is therefore switchable per snapshot, carries its own
 * `adapter_run` record with its own blob digest, and cannot change what a v0 projection contains.
 *
 * WHAT IT MAY EMIT is exactly `handoff/G0F_V1_AUDIT.md` §5 and nothing else — three roles, one kind, ten pairs, each
 * justified by pinned records at factory `d217ee2`. The audit's DEFERRED items are emitted as ATTRIBUTES with their
 * source bytes preserved and NO relation, which is the point: a `consumption_rule` defeater target supplies file
 * coordinates and no rule identity, so there is nothing for an ATTACKS edge to point at, and inventing a
 * `CONSUMPTION_RULE` role or aiming the edge at a SOURCE_LOCATION would make a queryable falsehood.
 *
 * All three files it reads — mosaic/arguments.json, mosaic/defeaters.json, mosaic/evidence.json — are ALREADY in the
 * 66-file factory pin (they entered through the ledger's own witness paths), so the snapshot commitment `gsnap-` for a
 * v1 snapshot over the same six sources is byte-identical to the v0 multi one. The v1 claim still moves, because a
 * claim binds the snapshot label, the schema set and the adapter contract, not only the source bytes. */
import { parseStrictJson, G0Error } from "../lib/canon.mjs";
import { Emitter } from "../lib/emit.mjs";
import { makeLid } from "../lib/lid.mjs";
import { LEDGER_PATH, ASSUMPTIONS_PATH, VOCABULARY, attrValue, parseWitness, sectionLine } from "./factory.mjs";

export const ARGUMENTS_PATH = "mosaic/arguments.json";
export const DEFEATERS_PATH = "mosaic/defeaters.json";
export const EVIDENCE_PATH = "mosaic/evidence.json";
export const MOSAIC_PATHS = Object.freeze([ARGUMENTS_PATH, DEFEATERS_PATH, EVIDENCE_PATH]);

/** The audit's §4 dispositions, as data the emitter consults — so "what v1 represents" is a table, never a branch
 *  buried in a loop. A target_type absent from here is DEFERRED and gets attributes only. */
const DEFEATER_TARGET = Object.freeze({
  claim: { role: "CLAIM", lid: (ref) => makeLid("CLAIM", "factory", ref).lid },
  argument: { role: "ARGUMENT", lid: (ref) => makeLid("ARGUMENT", "factory", ref).lid },
  assumption: { role: "ASSUMPTION", lid: (ref) => makeLid("ASSUMPTION", "factory", ref).lid },
  evidence: { role: "INSTRUMENT", lid: (ref) => makeLid("INSTRUMENT", "factory", ref).lid },
  receipt: { role: "RECEIPT", lid: (_ref, target) => makeLid("RECEIPT", "factory", String(target?.file ?? "")).lid },
});
/** DEFERRED, with the reason the audit recorded. Kept here so a reader of the code sees the refusal, not a silence. */
const DEFEATER_TARGET_DEFERRED = Object.freeze({
  consumption_rule: "file-at-revision coordinates only: no rule identity, an unbound symbol/section (the factory's own " +
    "INC-HIST-SYMBOL is open), and not injective — 34 defeaters carry 28 distinct payloads",
  claim_evidence: "the registry's own note says this attacks the SUPPORT a record offers, not the proposition; an " +
    "ATTACKS [DEFEATER, CLAIM] here would assert what the factory explicitly separated",
});

const ptrTok = (s) => String(s).replace(/~/g, "~0").replace(/\//g, "~1");
const targetAttrs = (t) => (t && typeof t === "object" ? Object.fromEntries(Object.entries(t)
  .filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => ["target_" + k, attrValue(v)])) : {});

/**
 * @param ctx { snapshot, repos: {factory, …}, treeRegistries }
 * @returns { factory_mosaic: Emitter output, meta }
 */
export function ingestFactoryMosaic(ctx) {
  const { snapshot, repos, treeRegistries = {} } = ctx;
  const repo = repos.factory;
  if (!repo) throw new G0Error("SOURCE_MISSING", "the snapshot pins no `factory` source");
  for (const p of MOSAIC_PATHS) if (!repo.has(p)) throw new G0Error("SOURCE_MISSING", `${repo.name}@${repo.commit.slice(0, 7)} has no ${p}`);
  const ledgerDoc = parseStrictJson(repo.bytes(LEDGER_PATH)).value;
  const roundId = String(ledgerDoc._round?.id || "");
  if (!roundId) throw new G0Error("SOURCE_SHAPE", `${LEDGER_PATH} has no _round.id`);

  const argsBlob = repo.blobOid(ARGUMENTS_PATH), defBlob = repo.blobOid(DEFEATERS_PATH), evBlob = repo.blobOid(EVIDENCE_PATH);
  const argsDoc = parseStrictJson(repo.bytes(ARGUMENTS_PATH)).value;
  const defDoc = parseStrictJson(repo.bytes(DEFEATERS_PATH)).value;
  const evDoc = parseStrictJson(repo.bytes(EVIDENCE_PATH)).value;
  const asmDoc = parseStrictJson(repo.bytes(ASSUMPTIONS_PATH)).value;
  const asmBlob = repo.blobOid(ASSUMPTIONS_PATH);

  /* The SAME registry lid the v0 factory adapter mints: this is one authority speaking about more of itself, not a
     second registry. Two adapters asserting one node is the mechanism G0-F already exercised. */
  const registryLid = makeLid("REGISTRY", "factory", `${VOCABULARY}@${roundId}`).lid;
  const E = new Emitter({ snapshot, registry: registryLid, namespace: "factory", pinned_identity: argsBlob, path: ARGUMENTS_PATH, treeRegistries });
  const at = (ptr, path = ARGUMENTS_PATH, pinned = argsBlob) => E.loc(ptr, null, { path, pinned, namespace: "factory" });

  const claimIds = new Set((ledgerDoc.claims || []).map((c) => String(c.claim_id)));
  const asmIds = new Set((asmDoc.assumptions || []).map((a) => String(a.id)));
  const claimLid = (id) => makeLid("CLAIM", "factory", id).lid;
  const argLid = (id) => makeLid("ARGUMENT", "factory", id).lid;
  const defLid = (id) => makeLid("DEFEATER", "factory", id).lid;
  const insLid = (id) => makeLid("INSTRUMENT", "factory", id).lid;
  const counts = { arguments: 0, defeaters: 0, instruments: 0, incidents: 0, attacks: 0, deferred_targets: 0, discharged_by: 0, witnesses_minted: 0 };

  /* ── WITNESS, by the v0 adapter's own construction ────────────────────────────────────────────
     An argument's `evidence_refs` of kind `witness` is as authoritative a statement that a path is a witness as a
     claim's `witnesses` list is. 23 of 24 already exist as nodes; the 24th is a bare path every claim happens to cite
     WITH a section, so it is minted here by the same rule rather than faulted (G0F_V1_AUDIT §3). */
  const sectionCache = new Map();
  const witnessOf = (path, section, concerns, lat) => {
    if (!repo.has(path)) { E.fault("DANGLING_WITNESS", "factory_mosaic.evidence_refs", `${path} is not in the pinned factory tree`, concerns); return null; }
    const blob = repo.blobOid(path);
    const lid = E.lid("WITNESS", "factory", path + (section ? "#" + section : ""));
    let line = null;
    if (section) {
      const key = path + "#" + section;
      if (!sectionCache.has(key)) sectionCache.set(key, sectionLine(repo.bytes(path).toString("utf8"), section));
      line = sectionCache.get(key);
      if (!line) E.fault("HEADING_WITHOUT_NUMBER", "factory_mosaic.evidence_refs", `no section banner §${section} in ${path} at ${repo.commit.slice(0, 7)}`, [...concerns, lid]);
    }
    const loc = E.loc(section ? (line ? `L${line}` : `§${section}`) : null, null, { path, pinned: blob, namespace: "factory" });
    E.node("WITNESS", lid, { path, root: "factory", blob, commit: repo.commit, ...(section ? { section, ...(line ? { line } : {}) } : {}) }, lat);
    E.rel("LOCATED_IN", lid, loc, lat);
    counts.witnesses_minted += 1;
    return lid;
  };

  /* ── ARGUMENT (27) ────────────────────────────────────────────────────────────────────────── */
  const argRecords = Array.isArray(argsDoc.arguments) ? argsDoc.arguments : [];
  const argIds = new Set(argRecords.map((a) => String(a.id)));
  argRecords.forEach((a, i) => {
    const ptr = `/arguments/${i}`, lat = at(ptr);
    const id = String(a.id ?? "");
    if (!id) { E.fault("AMBIGUOUS_IDENTIFIER", "factory_mosaic.arguments.id", `argument ${i} has no id`, [registryLid]); return; }
    const lid = argLid(id); counts.arguments += 1;
    E.node("ARGUMENT", lid, {
      code: id, role: String(a.role ?? ""), rule: attrValue(a.rule),
      ...(a.remaining_trust !== undefined ? { remaining_trust: attrValue(a.remaining_trust) } : {}),
      ...(a.obligation_discharged !== undefined ? { obligation_discharged: attrValue(a.obligation_discharged) } : {}),
    }, lat);
    E.rel("MEMBER_OF", lid, registryLid, lat);

    /* SUPPORTS [ARGUMENT, CLAIM] — 25 of 27; the two without a `conclusion_claim` conclude a DEFEATER and a
       claim-subsumption respectively, both DEFERRED by the audit and kept as attributes. */
    const concl = a.conclusion_claim ? String(a.conclusion_claim) : null;
    if (concl && claimIds.has(concl)) E.rel("SUPPORTS", lid, claimLid(concl), at(`${ptr}/conclusion_claim`));
    else if (concl) E.fault("UNRESOLVED_LINK", "factory_mosaic.arguments.conclusion_claim", `${id} concludes ${concl}, which the ledger does not carry`, [lid]);
    for (const [field, why] of [["conclusion_defeater", "an argument that eliminates a defeater"], ["subsumption", "a claim-to-claim subsumption"]])
      if (a[field] !== undefined) { E.node("ARGUMENT", lid, { [`deferred_${field}`]: attrValue(a[field]), [`deferred_${field}_reason`]: `${why}: one record at this pin, no consumer (G0F_V1_AUDIT §4)` }, at(`${ptr}/${field}`)); counts.deferred_targets += 1; }

    /* CITES [ARGUMENT, *] — already `*→*` in v0, so premises and source refs cost no new pair */
    for (const [j, p] of (a.premise_claims || []).entries()) {
      const pid = String(p);
      if (claimIds.has(pid)) E.rel("CITES", lid, claimLid(pid), at(`${ptr}/premise_claims/${j}`), { asrt: { part: "premise" } });
      else E.fault("UNRESOLVED_LINK", "factory_mosaic.arguments.premise_claims", `${id} premises ${pid}`, [lid]);
    }
    /* ASSUMES [ARGUMENT, ASSUMPTION] — 23 */
    for (const [j, r] of (a.assumption_refs || []).entries()) {
      const rid = String(r);
      if (asmIds.has(rid)) E.rel("ASSUMES", lid, makeLid("ASSUMPTION", "factory", rid).lid, at(`${ptr}/assumption_refs/${j}`));
      else E.fault("UNRESOLVED_LINK", "factory_mosaic.arguments.assumption_refs", `${id} assumes ${rid}`, [lid]);
    }
    /* evidence_refs: witness → WITNESSES [WITNESS, ARGUMENT]; claim/source → CITES */
    for (const [j, e] of (a.evidence_refs || []).entries()) {
      const eat = at(`${ptr}/evidence_refs/${j}`);
      const kind = String(e?.kind ?? "");
      if (kind === "witness" && e.path) {
        const sec = e.section === undefined || e.section === null ? null : String(e.section).replace(/^§/, "");
        const w = witnessOf(String(e.path), sec, [lid], eat);
        if (w) E.rel("WITNESSES", w, lid, eat, { asrt: { role: "argument-evidence" } });
      } else if (kind === "claim" && e.ref && claimIds.has(String(e.ref))) {
        E.rel("CITES", lid, claimLid(String(e.ref)), eat, { asrt: { part: "evidence" } });
      } else if (kind === "source" && e.ref) {
        E.rel("CITES", lid, makeLid("ARTIFACT", "factory", String(e.ref)).lid, eat, { asrt: { part: "evidence" } });
      } else {
        E.fault("UNSUPPORTED_SOURCE_FORM", "factory_mosaic.arguments.evidence_refs", `${id} evidence_ref ${j} is ${JSON.stringify(e).slice(0, 120)}`, [lid]);
      }
    }
  });

  /* ── INSTRUMENT (12) ──────────────────────────────────────────────────────────────────────── */
  const insRecords = Array.isArray(evDoc.instruments) ? evDoc.instruments : [];
  const insIds = new Set(insRecords.map((r) => String(r.id)));
  insRecords.forEach((r, i) => {
    const ptr = `/instruments/${i}`, lat = at(ptr, EVIDENCE_PATH, evBlob);
    const id = String(r.id ?? ""); if (!id) return;
    const lid = insLid(id); counts.instruments += 1;
    E.node("INSTRUMENT", lid, {
      code: id, name: String(r.name ?? ""), procedure: attrValue(r.procedure), produces: attrValue(r.produces),
      ...(r.independence_claim_ref ? { independence_claim_ref: String(r.independence_claim_ref) } : {}),
    }, lat);
    E.rel("MEMBER_OF", lid, registryLid, lat);
    /* ASSUMES [INSTRUMENT, ASSUMPTION] — 17 */
    for (const [j, a] of (r.assumption_refs || []).entries()) {
      const aid = String(a);
      if (asmIds.has(aid)) E.rel("ASSUMES", lid, makeLid("ASSUMPTION", "factory", aid).lid, at(`${ptr}/assumption_refs/${j}`, EVIDENCE_PATH, evBlob));
      else E.fault("UNRESOLVED_LINK", "factory_mosaic.instruments.assumption_refs", `${id} assumes ${aid}`, [lid]);
    }
  });

  /* ── DEFEATER (68) and its five ATTACKS pairs ─────────────────────────────────────────────── */
  const defRecords = Array.isArray(defDoc.defeaters) ? defDoc.defeaters : [];
  const defIds = new Set(defRecords.map((d) => String(d.id)));
  defRecords.forEach((d, i) => {
    const ptr = `/defeaters/${i}`, lat = at(ptr, DEFEATERS_PATH, defBlob);
    const id = String(d.id ?? ""); if (!id) return;
    const lid = defLid(id); counts.defeaters += 1;
    const tt = String(d.target_type ?? "");
    E.node("DEFEATER", lid, {
      code: id, kind: String(d.kind ?? ""), target_type: tt,
      ...(d.target_ref ? { target_ref: String(d.target_ref) } : {}),
      ...targetAttrs(d.target),
      ...(d.disposition ? { disposition: attrValue(d.disposition) } : {}),
      ...(d.why_open ? { why_open: String(d.why_open) } : {}),
      ...(DEFEATER_TARGET_DEFERRED[tt] ? { deferred_target_reason: DEFEATER_TARGET_DEFERRED[tt] } : {}),
    }, lat);
    E.rel("MEMBER_OF", lid, registryLid, lat);

    const spec = DEFEATER_TARGET[tt];
    if (!spec) { counts.deferred_targets += 1; return; }         // DEFERRED: attributes above, no edge
    const target = spec.lid(d.target_ref ? String(d.target_ref) : null, d.target);
    const known = { CLAIM: claimIds.has(String(d.target_ref)), ARGUMENT: argIds.has(String(d.target_ref)),
      ASSUMPTION: asmIds.has(String(d.target_ref)), INSTRUMENT: insIds.has(String(d.target_ref)),
      RECEIPT: !!d.target?.file && repo.has(String(d.target.file)) }[spec.role];
    if (!known) { E.fault("UNRESOLVED_LINK", "factory_mosaic.defeaters.target", `${id} targets ${spec.role} ${JSON.stringify(d.target_ref ?? d.target?.file)}, which is not in the pinned tree`, [lid]); return; }
    E.rel("ATTACKS", lid, target, at(`${ptr}/${d.target_ref ? "target_ref" : "target"}`, DEFEATERS_PATH, defBlob),
      { asrt: { target_type: tt, ...(d.target?.section ? { section: String(d.target.section) } : {}), ...(d.target?.symbol ? { symbol: String(d.target.symbol) } : {}) } });
    counts.attacks += 1;
  });

  /* ── incidents as FINDING (46) — NO NEW PROFILE SURFACE ───────────────────────────────────────
     FINDING, OPENS [ROUND, FINDING] and CLOSES [ROUND, FINDING] are all v0. These are absent from the v0 multi world
     only because the v0 adapter did not read this file. 10 incidents open and close at DIFFERENT rounds, so the two
     edges are not redundant. `finding_source` is provenance and stays an attribute (GPT v5 §7 / C4): the two FINDING
     populations live in different namespaces and cannot co-refer at this pin. */
  const incRecords = Array.isArray(defDoc.incidents) ? defDoc.incidents : [];
  incRecords.forEach((r, i) => {
    const ptr = `/incidents/${i}`, lat = at(ptr, DEFEATERS_PATH, defBlob);
    const id = String(r.id ?? ""); if (!id) return;
    const lid = makeLid("FINDING", "factory", id).lid; counts.incidents += 1;
    E.node("FINDING", lid, {
      code: id, finding_source: "incident", severity: String(r.severity ?? ""), status: String(r.status ?? ""),
      ...(r.subject ? { subject: attrValue(r.subject) } : {}),
      ...(r.revision_introduced ? { revision_introduced: String(r.revision_introduced) } : {}),
    }, lat);
    E.rel("MEMBER_OF", lid, registryLid, lat);
    for (const [field, kind] of [["revision_found", "OPENS"], ["fixed_by", "CLOSES"]]) {
      const rev = r[field] ? String(r[field]) : null; if (!rev) continue;
      E.rel(kind, makeLid("ROUND", "factory", rev).lid, lid, at(`${ptr}/${field}`, DEFEATERS_PATH, defBlob));
    }
    const dref = r.defeater_ref ? String(r.defeater_ref) : null;
    if (dref && defIds.has(dref)) E.rel("CITES", lid, defLid(dref), at(`${ptr}/defeater_ref`, DEFEATERS_PATH, defBlob));
    else if (dref) E.fault("UNRESOLVED_LINK", "factory_mosaic.incidents.defeater_ref", `${id} cites ${dref}`, [lid]);
  });

  /* ── DISCHARGED_BY [ASSUMPTION, CLAIM] — gated on the source's own status ─────────────────────
     Minted ONLY where discharge_state.status says the assumption IS discharged. 7 of 9 records at this pin say
     `undischarged`, and their evidence_refs point at where the assumption is UNMET; an edge there would invert the
     source (G0F_V1_AUDIT §4). Those refs are kept as attributes with their status. */
  const UNDISCHARGED = new Set(["undischarged", "false"]);
  (asmDoc.assumptions || []).forEach((a, i) => {
    const ds = a.discharge_state; if (!ds || !Array.isArray(ds.evidence_refs) || !ds.evidence_refs.length) return;
    const ptr = `/assumptions/${i}/discharge_state`, lat = at(ptr, ASSUMPTIONS_PATH, asmBlob);
    const id = String(a.id ?? ""); if (!id) return;
    const lid = makeLid("ASSUMPTION", "factory", id).lid;
    const status = String(ds.status ?? "");
    const discharged = !UNDISCHARGED.has(status);
    E.node("ASSUMPTION", lid, { discharge_status: status, ...(ds.scope ? { discharge_scope: String(ds.scope) } : {}), ...(ds.residual ? { discharge_residual: attrValue(ds.residual) } : {}) }, lat);
    for (const [j, e] of ds.evidence_refs.entries()) {
      const eat = at(`${ptr}/evidence_refs/${j}`, ASSUMPTIONS_PATH, asmBlob);
      const kind = String(e?.kind ?? "");
      if (kind === "claim" && e.ref && claimIds.has(String(e.ref)) && discharged) {
        E.rel("DISCHARGED_BY", lid, claimLid(String(e.ref)), eat, { asrt: { status } }); counts.discharged_by += 1;
      } else {
        counts.deferred_targets += 1;   // preserved as the assertion above; no edge, because the source does not support one
      }
    }
  });

  return { factory_mosaic: E.output(), meta: { registry: registryLid, round: roundId, counts, blobs: { arguments: argsBlob, defeaters: defBlob, evidence: evBlob } } };
}
