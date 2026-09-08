/* trvm.mjs — the TRVM governance adapter (G1-B, GPT Adjudication v6 §11 → D-071). READ-ONLY, DETERMINISTIC.
 *
 * The third authoritative source family. What it reads and why each file is authoritative is measured in
 * handoff/research/R15_TRVM_SOURCE_INVENTORY.md — every path below was chosen by reading the CONSUMER that loads it,
 * never by the filename.
 *
 * THE RULES THIS ADAPTER OBEYS
 *   · It is NOT authoritative over TRVM. Native ids (`<id>@<rev>`, `law:<id>@<rev>`, `srel-`, `brun-`, `bpkg-`),
 *     native status vocabulary (PROVED / PROPERTY-TESTED / REGRESSION-LOCKED / FALSIFIED / …; PINNED / ABORTED /
 *     CANDIDATE_FROZEN / REVEALED / COMPLETE) and source locations are carried EXACTLY as the source spells them.
 *     Four laws are FALSIFIED by design and TRVM's build fails if one starts passing — collapsing that into "failing"
 *     would invert the source.
 *   · NO PROSE-LAW PARSING. `statement`, `evidence`, `revision_note`, every `note`, and all ~90 `changelog_from_*`
 *     arrays are carried as opaque attributes. TRVM defines a grammar for `LAWS.md` headings (tools/laws_check.py)
 *     but that file is wired into neither `make` nor CI, and its integers never cross the `law:` namespace, so it is
 *     out of scope here rather than half-parsed.
 *   · It emits ONLY relations the source structurally states (R15 §10). A grid entry names no refusal code, no
 *     Makefile gate and no `srel-`; a bundle names no law; a release names no law set. None of those edges is
 *     fabricated.
 *   · IT NEVER RUNS `make governance`. Measured (R15 §8.2): `nest_bundle.mjs`, the other three `*_bundle.mjs` and
 *     `experiment_falsifiers.mjs` write into the repository unconditionally. Every read here goes through the pinned
 *     commit, so nothing this adapter does can change what it is reading.
 *
 * LAW LINEAGE, AND WHAT IT COST TO REPRESENT IT (D-073 → D-077).
 * TRVM structurally states 25 unique law→law supersession propositions. Under frozen `graphonomous.semantic.v1` they
 * could only be DEFERRED — `SUPERSEDES` was frozen same-kind at [CLAIM,CLAIM] · [ROUND,ROUND] ·
 * [EVIDENCE_STATE_TRANSITION,…] and `lib/lid.mjs` refused any other pair at EMISSION time. That deferral was the
 * measured v2 obligation, GPT v7 §6 opened `graphonomous.semantic.v2` with exactly that one endpoint pair, and this
 * adapter now emits the relations. **A v0 or v1 seal still REFUSES them** with WRL_UNDECLARED_ENDPOINT_PAIR — the
 * guard did not move, the admitted row did. `deferred` still carries every proposition, now labelled with the profile
 * that represents it, so the handoff can show what the widening bought.
 */
import { execFileSync } from "node:child_process";
import { Emitter } from "../lib/emit.mjs";

/** The authoritative file set, at the pinned commit. Each entry says WHO makes it authoritative (R15). */
export const TRVM_FILES = Object.freeze([
  { path: "governance/invariant-grid.json", why: "grid_check.mjs's single load; the only file that enumerates laws" },
  { path: "docs/spec/proof-wire/SPEC-RELEASE.json", why: "the current release pointer; spec_release.mjs recomputes its id from it" },
  { path: "docs/spec/proof-wire/schema/nested-composition-v2.json", why: "the normative schema; spec_agreement.mjs compares the implementation against it" },
  { path: "governance/blind-run.json", why: "the live run record; run_state.mjs owns its state machine" },
  { path: "governance/blind-package.json", why: "the delivered-bytes identity the run names" },
  { path: "governance/scheduler_certificate.json", why: "carries a law_refs array" },
  { path: "governance/refinement_receipt.json", why: "carries a law_refs array" },
  { path: "governance/world_warrant_receipt.json", why: "carries a law_refs array (8 + 3 nested + 1)" },
  { path: "governance/maintenance_receipt.json", why: "carries a law_refs array" },
  { path: "governance/golden_prehash_vectors.json", why: "carries a law_refs array" },
]);
/** Directories read whole, at the pin. */
export const TRVM_DIRS = Object.freeze([
  { prefix: "governance/receipts/", why: "the blind-run ledger, append-only, one file per state transition" },
  { prefix: "docs/spec/proof-wire/releases/", why: "the immutable release archive" },
]);

export const NS = "trvm-gov";   // its own namespace: the crosswalk already pins TRVM at fd0df4c as an EVIDENCE source; this is the GOVERNANCE source at 8816e59, and the two coordinates must stay visibly distinct.
const LAW_CITE = /^law:([a-z0-9_.\-]+)@(\d+)$/;
const j = (b) => JSON.parse(b.toString("utf8"));

/** Every `law_refs` array anywhere in a record, with the JSON pointer that found it. TRVM nests them. */
function lawRefsIn(node, at = "", out = []) {
  if (!node || typeof node !== "object") return out;
  if (Array.isArray(node)) { node.forEach((x, i) => lawRefsIn(x, `${at}/${i}`, out)); return out; }
  for (const [k, v] of Object.entries(node)) {
    if (k === "law_refs" && Array.isArray(v)) out.push({ at: `${at}/law_refs`, refs: v.filter((x) => typeof x === "string") });
    else lawRefsIn(v, `${at}/${k}`, out);
  }
  return out;
}

/**
 * Ingest TRVM governance at the snapshot's pinned commit.
 * `repos.trvm` is an openRepo() handle — every read is `<commit>:<path>`, never the worktree.
 */
export function ingestTrvmGovernance({ snapshot, repos, treeRegistries = {} }) {
  const repo = repos[NS];
  if (!repo) return { governance: new Emitter({ snapshot, registry: `registry:${NS}:absent`, namespace: NS, pinned_identity: "0".repeat(40), path: "", treeRegistries }).output() };

  const GRID = "governance/invariant-grid.json";
  const grid = j(repo.bytes(GRID));
  const registryLid = `registry:${NS}:invariant-grid@${grid.version}`;
  const E = new Emitter({ snapshot, registry: registryLid, namespace: NS, pinned_identity: repo.blobOid(GRID), path: GRID, treeRegistries: { ...treeRegistries, [NS]: registryLid } });
  /** re-point the emitter at another pinned file; every location minted after this names that blob */
  const at = (path) => { E.path = path; E.pinned = repo.blobOid(path); return E; };
  const deferred = [];

  /* ── the registry itself ─────────────────────────────────────────────── */
  at(GRID);
  E.node("REGISTRY", registryLid, {
    version: grid.version, grid_version: grid.law_registry.grid_version, entries: grid.law_registry.entries.length,
    /* the source's own date field, carried as the source spells it. R15 §2 measured that grid_check never reads it
       and that it is stale against the 1.70.0 commit date — that disagreement is a G1 question, not a fault here. */
    declared_date: grid.date ?? null,
    /* a G0 attribute key must match /^[A-Za-z_][A-Za-z0-9_]*$/ and these are filenames, so the map travels as a
       sorted list of pairs — the source's spelling of each name is preserved in the value, not in a key. */
    artifact_versions: Object.entries(grid.artifact_versions ?? {}).sort().map(([artifact, version]) => ({ artifact, version })),
  }, E.loc(""));

  const schemasRegistry = `registry:${NS}:nested-composition-v2`;

  /* ── vocabularies the grid declares as closed sets ────────────────────── */
  for (const s of grid.status_vocabulary ?? []) {
    const lid = E.lid("DEFINITION", NS, `status/${s}`);
    E.node("DEFINITION", lid, { term: s, vocabulary: "law_registry.status_vocabulary", closed_set: true }, E.loc("/status_vocabulary"));
    E.rel("MEMBER_OF", lid, registryLid, E.loc("/status_vocabulary"));
  }
  for (const d of grid.defect_class_vocabulary ?? []) {
    const lid = E.lid("DEFINITION", NS, `defect_class/${d}`);
    E.node("DEFINITION", lid, { term: d, vocabulary: "defect_class_vocabulary", closed_set: true }, E.loc("/defect_class_vocabulary"));
    E.rel("MEMBER_OF", lid, registryLid, E.loc("/defect_class_vocabulary"));
  }

  /* ── the 139 laws ────────────────────────────────────────────────────── */
  const byKey = new Map();
  grid.law_registry.entries.forEach((e, i) => {
    const key = `${e.id}@${e.revision}`;
    const lid = E.lid("LAW", NS, key);
    byKey.set(key, lid);
    const loc = E.loc(`/law_registry/entries/${i}`);
    E.node("LAW", lid, {
      law_id: e.id, revision: e.revision, citation: `law:${key}`, status: e.status, canonical: e.canonical === true,
      ...(e.defect_class !== undefined ? { defect_class: e.defect_class } : {}),
      ...(e.accepted_false_verdict !== undefined ? { accepted_false_verdict: e.accepted_false_verdict } : {}),
      ...(e.underlying_observations_genuine !== undefined ? { underlying_observations_genuine: e.underlying_observations_genuine } : {}),
      ...(e.grid_law_id !== undefined ? { grid_law_id: e.grid_law_id } : {}),
      /* prose, carried opaque and labelled — never parsed (R15 §9) */
      statement: e.statement, evidence: e.evidence,
      ...(e.revision_note !== undefined ? { revision_note: e.revision_note } : {}),
      prose_fields: ["statement", "evidence", "revision_note"],
    }, loc);
    E.rel("MEMBER_OF", lid, registryLid, loc, { asrt: { index: i } });
    const st = E.lid("DEFINITION", NS, `status/${e.status}`);
    if (grid.status_vocabulary?.includes(e.status)) E.rel("CITES", lid, st, loc, { asrt: { role: "status" } });
    if (e.defect_class && grid.defect_class_vocabulary?.includes(e.defect_class)) E.rel("CITES", lid, E.lid("DEFINITION", NS, `defect_class/${e.defect_class}`), loc, { asrt: { role: "defect_class" } });
  });

  /* ── law lineage: 25 propositions the source STATES ──────────────────────
     Measured at 8816e59: 24 entries carry `supersedes`, 25 carry `superseded_by`, 24 propositions are stated by BOTH
     fields and exactly one (kernel.identity@1 -> kernel.identity@2) only by `superseded_by` — legal in TRVM, whose
     grid_check enforces lineage symmetry only where both sides are populated. One proposition, so the two fields fold
     into ONE relation with two assertions; that is the "one statement, many assertions" model doing its job.
     SUPERSEDES [LAW, LAW] is admitted by graphonomous.semantic.v2 (D-077). A v0/v1 seal still REFUSES these with
     WRL_UNDECLARED_ENDPOINT_PAIR, which is the guard, not a bug. */
  at(GRID);
  {
    const stated = new Map();   // `${src}>${dst}` -> {src, dst, by: [{field, index}]}
    grid.law_registry.entries.forEach((e, i) => {
      const from = `${e.id}@${e.revision}`;
      for (const field of ["supersedes", "superseded_by"]) {
        const target = e[field];
        if (typeof target !== "string") continue;
        if (!byKey.has(target)) { E.fault("UNRESOLVED_LINK", "trvm-gov.lineage", `law ${from}.${field} names ${target}, which is not an entry in this registry`, [byKey.get(from)]); continue; }
        const [src, dst] = field === "supersedes" ? [from, target] : [target, from];
        const k = `${src}>${dst}`;
        if (!stated.has(k)) stated.set(k, { src, dst, by: [] });
        stated.get(k).by.push({ field, index: i, on: from });
      }
    });
    for (const [, x] of [...stated].sort()) {
      for (const b of x.by.sort((p, q) => p.index - q.index)) {
        E.rel("SUPERSEDES", byKey.get(x.src), byKey.get(x.dst), E.loc(`/law_registry/entries/${b.index}/${b.field}`),
          { attrs: { source_fields: [...new Set(x.by.map((y) => y.field))].sort() },
            asrt: { stated_by: b.field, stated_on: `law:${b.on}` } });
      }
      deferred.push({ kind: "SUPERSEDES", pair: ["LAW", "LAW"], source: `law:${NS}:${x.src}`, target: `law:${NS}:${x.dst}`, stated_by: [...new Set(x.by.map((y) => y.field))].sort(), represented_under: "graphonomous.semantic.v2" });
    }
  }

  /* ── the normative schema: refusal codes, id prefixes, child protocols ── */
  const NC = "docs/spec/proof-wire/schema/nested-composition-v2.json";
  const nc = j(repo.bytes(NC)); at(NC);
  E.node("REGISTRY", schemasRegistry, {
    protocol: nc.protocol ?? "TRVM-NESTED-COMPOSITION-v2", refusal_codes: nc.refusal_codes.length,
    id_prefixes: Object.keys(nc.constants.id_prefixes).length, child_protocols: Object.keys(nc.constants.child_protocols).length,
    array_is_sorted: JSON.stringify(nc.refusal_codes) === JSON.stringify([...nc.refusal_codes].sort()),
  }, E.loc(""));
  nc.refusal_codes.forEach((code, i) => {
    const lid = E.lid("DEFINITION", NS, `refusal/${code}`);
    E.node("DEFINITION", lid, { term: code, vocabulary: "nested-composition-v2.refusal_codes", declared_index: i, normative: true }, E.loc(`/refusal_codes/${i}`));
    E.rel("MEMBER_OF", lid, schemasRegistry, E.loc(`/refusal_codes/${i}`));
  });
  for (const [field, prefix] of Object.entries(nc.constants.id_prefixes).sort()) {
    const lid = E.lid("DEFINITION", NS, `id_prefix/${field}`);
    E.node("DEFINITION", lid, { term: field, prefix, vocabulary: "nested-composition-v2.constants.id_prefixes", normative: true, falsified_by: "spec_agreement.mjs mints one id of each kind and compares the text before the first '-'" }, E.loc("/constants/id_prefixes"));
    E.rel("MEMBER_OF", lid, schemasRegistry, E.loc("/constants/id_prefixes"));
  }
  for (const [proto, decl] of Object.entries(nc.constants.child_protocols).sort()) {
    const lid = E.lid("DEFINITION", NS, `child_protocol/${proto}`);
    E.node("DEFINITION", lid, { term: proto, claim_field: decl.claim_field, composed: decl.composed, vocabulary: "nested-composition-v2.constants.child_protocols", normative: true, builtin: true }, E.loc("/constants/child_protocols"));
    E.rel("MEMBER_OF", lid, schemasRegistry, E.loc("/constants/child_protocols"));
  }
  if (nc.constants.verifier_policy) {
    const lid = E.lid("DEFINITION", NS, "verifier_policy/shipped");
    E.node("DEFINITION", lid, { term: "verifier_policy", ...nc.constants.verifier_policy, vocabulary: "nested-composition-v2.constants.verifier_policy", normative: true, tightening_only: true }, E.loc("/constants/verifier_policy"));
    E.rel("MEMBER_OF", lid, schemasRegistry, E.loc("/constants/verifier_policy"));
  }

  /* ── spec releases: the pointer and the archive ───────────────────────── */
  const relFiles = repo.under("docs/spec/proof-wire/releases/").filter((p) => p.endsWith(".json")).sort();
  const releaseLid = (id) => E.lid("ARTIFACT", NS, id);
  const seenRelease = new Set();
  const emitRelease = (path, r, isPointer) => {
    at(path);
    const lid = releaseLid(r.spec_release_id);
    if (!seenRelease.has(r.spec_release_id)) {
      seenRelease.add(r.spec_release_id);
      E.node("ARTIFACT", lid, {
        spec_release_id: r.spec_release_id, release_type: r.release_type, spec_revision: r.spec_revision,
        experiment_revision: r.experiment_revision, public_corpus_revision: r.public_corpus_revision,
        spec_digest: r.spec_digest, experiment_digest: r.experiment_digest, public_corpus_digest: r.public_corpus_digest,
        holdout_commitment: r.holdout_commitment, holdout_entries: r.holdout_entries,
        protocols: r.protocols, jcs_upstream: r.jcs_upstream,
        spec_files: (r.spec_files ?? []).length, experiment_files: (r.experiment_files ?? []).length,
      }, E.loc(""));
    }
    if (isPointer) E.node("ARTIFACT", lid, { is_current_pointer: true }, E.loc(""));
    return lid;
  };
  const pointer = j(repo.bytes("docs/spec/proof-wire/SPEC-RELEASE.json"));
  const currentRelease = emitRelease("docs/spec/proof-wire/SPEC-RELEASE.json", pointer, true);
  for (const p of relFiles) emitRelease(p, j(repo.bytes(p)), false);

  /* ── the blind run and its ledger ─────────────────────────────────────── */
  const BR = "governance/blind-run.json";
  const run = j(repo.bytes(BR)); at(BR);
  const runLid = E.lid("EXPERIMENT", NS, "blind-run");
  E.node("EXPERIMENT", runLid, {
    type: run.type, status: run.status, run_id: run.run_id, spec_release_id: run.spec_release_id,
    blind_package_id: run.blind_package_id, instrument_digest: run.instrument_digest,
    blind_contract_revision: run.blind_contract_revision, adapters: (run.adapters ?? []).map((a) => ({ implementation: a.implementation, role: a.role, package_digest: a.package_digest })),
    states: ["PINNED", "CANDIDATE_FROZEN", "REVEALED", "COMPLETE", "ABORTED"],
  }, E.loc(""));
  if (seenRelease.has(run.spec_release_id)) E.rel("CITES", runLid, releaseLid(run.spec_release_id), E.loc("/spec_release_id"), { asrt: { role: "spec_release" } });

  const BP = "governance/blind-package.json";
  if (repo.has(BP)) {
    const bp = j(repo.bytes(BP)); at(BP);
    const bpLid = E.lid("ARTIFACT", NS, bp.blind_package_id);
    E.node("ARTIFACT", bpLid, { blind_package_id: bp.blind_package_id, type: bp.type, root: bp.root, file_count: bp.file_count }, E.loc(""));
    E.rel("CITES", runLid, bpLid, at(BR).loc("/blind_package_id"), { asrt: { role: "blind_package" } });
  }

  const receiptFiles = repo.under("governance/receipts/").filter((p) => p.endsWith(".json")).sort();
  const receiptLidOf = new Map();
  for (const p of receiptFiles) {
    const r = j(repo.bytes(p)); at(p);
    const name = p.slice("governance/receipts/".length).replace(/\.json$/, "");
    const lid = E.lid("RECEIPT", NS, name);
    receiptLidOf.set(name, { lid, r });
    E.node("RECEIPT", lid, {
      type: r.type, run_id: r.run_id, status: r.status, spec_release_id: r.spec_release_id ?? null,
      blind_package_id: r.blind_package_id ?? null, instrument_digest: r.instrument_digest ?? null,
      /* v1 receipts carry NEITHER field; that is a schema generation, not a missing link (R15 §6) */
      previous_run_id: r.previous_run_id ?? null, previous_status: r.previous_status ?? null,
      carries_previous: Object.prototype.hasOwnProperty.call(r, "previous_run_id"),
      note: r.note ?? null, prose_fields: ["note"],
    }, E.loc(""));
    E.rel("PRODUCED_BY", lid, runLid, E.loc(""), { asrt: { role: "blind_run_ledger" } });
    if (r.spec_release_id && seenRelease.has(r.spec_release_id)) E.rel("CITES", lid, releaseLid(r.spec_release_id), E.loc("/spec_release_id"), { asrt: { role: "spec_release" } });
  }
  /* previous_run_id → the receipt that run id belongs to. An ABORT names the run it ENDED; a PIN starts a chain
     (GPT v6 §2 / D-065). The link is emitted in the direction the source states it, and only when it resolves. */
  const byRunId = new Map();
  for (const [, { lid, r }] of receiptLidOf) if (r.run_id) { if (!byRunId.has(r.run_id)) byRunId.set(r.run_id, []); byRunId.get(r.run_id).push(lid); }
  for (const [name, { lid, r }] of [...receiptLidOf].sort()) {
    if (!r.previous_run_id) continue;
    const targets = byRunId.get(r.previous_run_id);
    at(`governance/receipts/${name}.json`);
    if (!targets) { E.fault("UNRESOLVED_LINK", "trvm-gov.ledger", `receipt ${name} names previous_run_id ${r.previous_run_id}, which no receipt in this ledger carries`, [lid]); continue; }
    for (const t of targets.sort()) E.rel("CITES", lid, t, E.loc("/previous_run_id"), { asrt: { role: "previous_run", previous_status: r.previous_status ?? null } });
  }

  /* ── the five artifacts that structurally cite laws ───────────────────── */
  for (const { path } of TRVM_FILES.filter((f) => /receipt|certificate|vectors/.test(f.path))) {
    if (!repo.has(path)) continue;
    const rec = j(repo.bytes(path)); at(path);
    const name = path.split("/").pop().replace(/\.json$/, "");
    const lid = E.lid("RECEIPT", NS, name);
    const found = lawRefsIn(rec);
    E.node("RECEIPT", lid, { file: path, law_refs_arrays: found.length, law_refs_total: found.reduce((n, f) => n + f.refs.length, 0) }, E.loc(""));
    for (const { at: ptr, refs } of found) for (const ref of refs) {
      const m = LAW_CITE.exec(ref);
      if (!m) { E.fault("UNQUALIFIED_REFERENCE", "trvm-gov.law_refs", `${path}${ptr} cites ${JSON.stringify(ref)}, which is not law:<id>@<rev>`, [lid]); continue; }
      const key = `${m[1]}@${m[2]}`;
      const target = byKey.get(key);
      if (!target) { E.fault("UNRESOLVED_LINK", "trvm-gov.law_refs", `${path}${ptr} cites law:${key}, which is not an entry in invariant-grid.json@${grid.version}`, [lid]); continue; }
      E.rel("CITES", lid, target, E.loc(ptr), { asrt: { role: "law_ref", citation: ref } });
    }
  }

  return { governance: E.output(), deferred, pins: { grid_blob: repo.blobOid(GRID), commit: repo.commit, grid_version: grid.version, laws: grid.law_registry.entries.length, releases: seenRelease.size, receipts: receiptFiles.length } };
}
