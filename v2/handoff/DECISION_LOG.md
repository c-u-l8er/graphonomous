# DECISION LOG — Graphonomous G0/G1

Format per entry: decision · alternatives considered · evidence/rationale · reversibility and cost of change ·
unresolved questions. Entries are appended, never rewritten; a reversal is a new entry that cites the old one.

## D-001 — The lane lives at `graphonomous/v2/`, beside the v0.4 Elixir engine (2026-09-02)

- **Decision.** New work goes in `graphonomous/v2/` inside the existing `graphonomous` repository
  (`git@github.com:c-u-l8er/graphonomous.git`, HEAD `5a9e00b` at open). The v0.4 engine (`lib/`, 113 modules,
  49 test files, `mix.exs`) is left untouched.
- **Alternatives.** (a) A new top-level sub-repo `graphonomous-g0/` — rejected for now: ProjectAmp2 tracks none of its
  ~27 sub-repos, so a new directory means a new remote and another untracked tree; (b) rewriting inside `lib/` —
  rejected: G0 is a different product definition (a projection over registries, not a memory loop) and the brief
  says preserve working code unless replacement is justified.
- **Reversibility.** Cheap: `git mv` later. Nothing outside this directory references it yet.
- **Open.** Whether the v0.4 MCP machines eventually *front* the G0 projection (a `retrieve`-style query surface) or
  the two stay separate products. Not a G-PR0 question.

## D-002 — The authority boundary is frozen as stated in the brief, and it is the S2 discipline applied to us (2026-09-02)

- **Decision.** Graphonomous G0/G1 is a derived semantic projection over authoritative registries and evidence, not
  an authoritative registry. It may derive, relate, rank, challenge, detect inconsistency and emit `PROPOSAL` /
  `CANDIDATE` objects with provenance. It never writes canonical evidence state.
- **Evidence.** GPT's verbatim note (recovered from the invariant lane's transcript, session `c33dcf12`,
  2026-09-02T20:37Z; saved to this lane's research inputs): *"We do not want to solve five registries drifting by
  creating six registries drifting."* The factory already enforces promotion finality by compare-and-swap on a ref
  (`~/.invariant-factory/wt-r9/scripts/factory-station.mjs`, FAC-CANONICAL-HEAD-CAS); a projection that wrote back
  would bypass the one station that owns finality.
- **Reversibility.** A later stage (G5) may make Graphonomous an *admitted participant* of the factory; that is an
  explicit admission, not a relaxation of this rule.

## D-003 — The first dataset is the real invariant program at a frozen snapshot, not a toy (2026-09-02)

- **Decision.** G0 ingests: `invariant-r10/package-v2.6/` (crosswalk 56 records, `evidence_state.json`,
  machine-readable ledger, witnesses, experiments' RESULT files, handoffs, the R0.8.x handbacks in `px13/`), the
  factory canonical ref `refs/heads/invariant-canonical` in `~/.invariant-factory/canonical.git` (CLAIM_LEDGER.json,
  208 claims; `mosaic/*`), `TRVM/governance/invariant-grid.json` (138 law-registry entries), `computedriven/`
  (docs, receipts, git history R0.1→R0.8.7), `opensentience.org/_invariants/data/cells.json` (46 cells), `super/`
  (ampd conformance + receipts), the WEK R0 documents, and the GPT adjudications as *advisory* sources.
- **Snapshot rule.** Every adapter reads a pinned revision (git OID, or sha256 for loose files) recorded in
  `SOURCE_INVENTORY.md`. The live trees move under us — the invariant lane and the computedriven lane were both
  observed moving during 2026-09-02 — so nothing reads a working tree by path without first recording the OID it saw.
- **Alternatives.** A synthetic dataset first — rejected by the brief and by GPT's note; the point is that real
  application pressure reveals missing primitives.

## D-004 — The bundle companions were not delivered; their intent is reconstructed, and the gap is recorded (2026-09-02)

- **Fact.** The master prompt references `02_RESEARCH_AGENDA.md`, `03_STACK_REPAIR_PROTOCOL.md` and two verbatim
  notes in `sources/`. Only `GRAPHONOMOUS_FABLE51_MASTER_PROMPT_v1.md` (21,230 bytes) reached `~/Downloads`.
  Searched: `~/Downloads` (all `*.md`, `files.zip`, `files (20).zip`), the repository, and the two prior session
  transcripts that mention the topic.
- **Decision.** Treat the master prompt's §11 as the research agenda and its §10 as the repair protocol; treat GPT's
  recovered note as source note #1. Record the missing files in `SOURCE_INVENTORY.md` under *missing/unavailable*
  and ask GPT for them in the next handoff rather than inventing their contents.

## D-005 — Implementation language for G0 is decided by the substrate, pending two audits (2026-09-02, provisional)

- **Leaning.** Node ESM, zero runtime dependencies, with a Python cross-check of the projection digest. Evidence so
  far: the identity spine is `WRL/wrl.js` (browser-capable) with a byte-exact Python twin in `TRVM/forge/`; every
  registry gate this lane must interoperate with is Node ESM (`scripts/check-*.mjs`, `factory-station.mjs`,
  `check-evidence-transitions.mjs`, `_invariants/build/build.mjs`); the visualization is browser-side; two-language
  agreement on canonical bytes is an existing discipline here (890/890 WRL conformance, re-run this session).
- **Alternative.** Elixir/OTP, matching the v0.4 engine and `super/ampd` — kept open until the WRL (R5) and TRVM (R6)
  audits say where the canonicalizer and derivation protocol actually live. A G0 that cannot import the spine it is
  supposed to be native to would be ceremonial WRL, which the brief forbids.
- **Reversibility.** Moderate once adapters exist. Decide before G0-A.

## D-006 — Canonical bytes, store and certificate come from TRVM as they are; no fourth canonicalizer (2026-09-02)

- **Decision.** G0 adopts TRVM `canonicalBytes` as its canonical form over a restricted value domain (no floats, no
  BigInt, no NaN, no lone surrogates; UTF-8 strings; safe integers), `governance/cas.mjs` as the content-addressed store
  for records and the projection manifest, and `verifiedClaimSemId` as the projection certificate under a Graphonomous
  protocol id with a Graphonomous checker.
- **Alternatives.** (a) WRL `serializeArtifact` — refuses floats (fine) but emits BigInt digits and is coupled to the
  artifact schema; (b) a Graphonomous-own canonicalizer — a fourth rule where three already disagree outside the
  intersection domain (R6 §4); (c) RFC 8785 without a domain restriction — reintroduces the `1.0` vs `1` divergence
  measured in `TEST_FIXTURES/canon-divergence-2026-09-02.md`.
- **Evidence.** R6 probes B and C (`research/probes/trvm/`), `derive_battery.mjs` 45/45, the six-registry
  two-language experiment.
- **Reversibility.** Low cost while no projection has been published; after publication a canonicalizer change moves
  every `rev-` and `root-`, which is the WRL/TRVM discipline working as intended.

## D-007 — Rules are evaluated by the projector and recorded as labelled provenance records, not as TRVM derivations (2026-09-02)

- **Decision.** Every derived fact carries a content-bound `rule_sem_id` and CAS-stored inputs; the evaluation record is
  labelled `trvm_derivation: false`. Numeric rules go through the real derive authority. The adapter's removal
  condition is a `prim` catalog with the five entries proposed in R6 §2.2.
- **Why not wait / why not fork.** Waiting blocks G0 on a TRVM roadmap item behind two open milestones (native film
  emission, cross-replay; `realm_roadmap.order[9]`). Forking a private rule language inside TRVM's shape would be the
  "Graphonomous semantics layer" the brief forbids. The labelled adapter keeps the boundary visible.
- **Evidence.** `program-unknown-op` for `forall`, `eq`, `and`, `if`, `get`, `prim` at `fd0df4c`; only
  `sub(len(scope …), 1)` binds (R6 §2.1).
- **Reversibility.** High: the rule data shape is chosen to be the `prim` program shape, so the removal is a
  re-hash, not a redesign.

## D-008 — Two snapshot pins: current = `invariant-r10@ba4e625` (package-v2.7), historical = `699fbc2` (package-v2.6) (2026-09-02)

- **Fact.** The invariant lane committed the v5 return (`303f76c`, package-v2.7 per the GPT v4 adjudication: F35 CLOSED,
  R0.8 open for the NC29 cut, F36/F37 shipped unadjudicated, a generated projection hash, gate v2.7 with 23 mutations)
  at 16:07 local, while the census of `699fbc2` was running (R7A §0). `package-v2.6/` is tree-identical at both commits;
  the E-51 receipt under `experiments/` is not (Q-14).
- **Decision.** G0's first frozen input is the newest committed package (`ba4e625`, v2.7); `699fbc2` (v2.6) is the
  historical snapshot for DEMO step 7 and for the A2 "per snapshot" answer. Both OIDs are in the spec §14. A v2.7 delta
  census runs before G0-B; the R7A/R7B census of `699fbc2` stands as the baseline.
- **Alternatives.** Pin only v2.6 (already censused) — rejected: ingesting a package its own lane has superseded would
  make Graphonomous's first answer stale on arrival; pin the working tree — rejected by D-003 and by what happened.
- **Reversibility.** Trivial: pins are data in `snapshot.json`.

## D-009 — WRL: kernel-native now, seal-native when WRL can seal a static profile; world ids are `gsem-`, never `sem-` (2026-09-02)

- **Decision.** G0 relations get their `rev-`/`rel-` from WRL's relation kernel (`relation-identity.js`), the semantic
  world is a V2-shaped artifact under `profile_id: graphonomous.semantic.v0` with one nominal port per object, the D8
  rulings are design constraints, and the world id is computed with the spine's bytes rule but prefixed `gsem-`. The
  profile mechanism with a static profile kind is proposed to the WRL owner (GAP-W1/W6); computing `gsem-` outside the
  spine is the labelled adapter with that removal condition.
- **Evidence.** R5: the kernel hashes a G0 `evidence.SUPPORTS` with nested attributes today (`rev-c29c2cfe…`), while
  the V2 world gate refuses kind/domain/attributes/arity/texture and `validateGraph` refuses any profile but the
  constant; `ProfileSchemaV1` has zero code; all seven D9 rows are `awaiting`.
- **Alternatives.** (a) Implement `ProfileSchemaV1` in `wrl.js` now under the repair protocol — rejected for G-PR0: a
  change to a frozen family's registries and a new profile kind is the architect's ruling, not an implementation bug;
  the memory of this tree records the standing order "add no new runtime constructs unless GPT-5.6 explicitly rules
  it" for Forge, and WRL is the same spine. (b) Ceremonial `.wrl` beside a conventional app — forbidden by the brief.
  (c) Mint `sem-` ids ourselves — rejected: a `sem-` WRL did not issue is a forged spine identity.
- **Reversibility.** When WRL ships the profile, `gsem-` → `sem-` is a supersession of ids, not a redesign; the
  artifact bytes are already V2-shaped.

## D-010 — Implementation host: Node ESM, zero runtime dependencies, with a Python twin for digests (2026-09-02)

- **Decision.** Closes D-005. The WRL kernel, TRVM `canonicalBytes`, `cas.mjs`, `certificate.mjs`, every registry gate
  and the browser are JavaScript; the evaluator is a dependency-free ESM module usable unchanged as CLI, library and
  static page (R3 §1); the Python twin reproduces the projection root and the derivation-set digest (the two-language
  agreement discipline WRL/Forge already run). Elixir is not a G0 host: hex `rfc8785` needs OTP 29 and this box runs
  28 (R2 §1); the v0.4 engine stays as it is.
- **Reversibility.** Moderate after adapters exist; recorded now so no adapter is written in a language that cannot
  import the spine.

## D-011 — Build the evaluator; do not adopt a Datalog engine (2026-09-02)

- **Decision.** A ~300-line stratified semi-naive evaluator recording `{rule, conclusion, premises, bindings, depth}`
  per derived fact, with `{absent: …}` premises for negation, an independent ~50-line checker, and a documented
  tie-break (min depth, then canonical bytes; at most 4 alternatives kept).
- **Evidence.** R3 §1 decision table (verified 2026-09-02): Soufflé 2.5 and Nemo 0.10.1 have real proof trees but no
  published Node/Python/browser artifact; CozoDB dormant since 2024-12; DDlog archived 2026-07-13; Datascript /
  Datalevin / Datahike / Logica / pyDatalog record no provenance; no engine documents its tie-break, which the digest
  requirement needs.
- **Reversibility.** High: the rule program is data in the `prim` shape (D-007); Nemo is the named fallback if the
  rule set grows past a few dozen rules or ~10⁶ facts.

## D-012 — Receipts and artifacts take the in-toto shape; signing and logs wait (2026-09-02)

- **Decision.** A `RECEIPT` is an in-toto Statement isomorph (`subject[]` by digest, `predicate_type`,
  `predicate`), external artifacts are ResourceDescriptors with a DigestSet restricted to `sha256 · gitCommit ·
  gitTree · gitBlob · dirHash1`; DSSE, Sigstore, SLSA, SCITT/COSE receipts and Rekor are adapters or explicit waits.
- **Evidence.** R2 §3–§4: the subject-by-digest binding is exactly claim → artifact; every log protocol solves
  multi-issuer equivocation, and G0 has one writer and a git history. Leaves use the RFC 9162 prefix now so a tree
  can be layered later without re-hashing.

## D-013 — The store is a directory of canonical JSON plus a CAS; SQLite is a throwaway index (2026-09-02)

- **Decision.** Spec §9. Never hash the SQLite file; never rely on implicit order; the browser loads the JSON.
- **Evidence.** R3 §6 (rowids renumber on VACUUM; deleted pages linger; `node:sqlite` is RC; nothing at 10k edges
  a sorted array and two Maps cannot answer); R2 §6 (manifest of sorted `(id, hash)`; git tree as witness only).

## D-014 — Statement id ≠ assertion id; retraction is a record; unknowns are typed (2026-09-02)

- **Decision.** Spec §2, §4.3–4.4, §4.7, §5.5. One relation may carry many assertions; two sources stating one
  relation are one relation with two assertions; retraction and supersession are positive records with provenance;
  `unknown{reason}` with a closed reason set; negation only stratified over observed facts.
- **Evidence.** R1: RDF 1.2 (CR 7 Apr 2026) split the proposition (triple term) from its occurrences (reifiers,
  many-to-many) and the WG equates a reifier with a Cypher edge id; nanopublications' forward-pointer supersession and
  retraction-as-record; Datomic's retraction datom; FHIR `data-absent-reason`; Abiteboul–Hull–Vianu on stratification.
  The three-way F35 disagreement in our own sources (Q-09) is the case that made this necessary.

## D-015 — G0.5 renders with Cytoscape.js; layering is deterministic (dagre for sub-graphs, ELK or Graphviz for the whole graph); no layout is truth (2026-09-02, after R4)

- **Decision.** Primary: Cytoscape.js 3.34.2 as a plain ES module from cdnjs, cytoscape-dagre 4.0.1 (`.mjs`) for
  neighbourhood / sub-graph layered views (≲ 500 nodes), ELK layered 0.12.0 (`randomSeed` fixed, `considerModelOrder`
  on) in a Worker or offline for whole-graph deterministic layering loaded through `preset` from a cache keyed by
  `sha256(projection) + engine + version + options`; fcose only for non-layered overviews and never as a
  reproducibility surface (it has no seed and reruns differently — verified). Fallback and export: `@viz-js/viz` 3.30.0
  (Graphviz 16.0.0, single ES module) → SVG with `id`/`class`/`href` → `svg-pan-zoom` 3.6.2. Escalation past ~5k nodes:
  Sigma 3.0.3 + graphology. Provenance class by stroke (solid imported, dashed derived, dotted proposed), kind by node
  shape, status by badge and border, relation kind by arrowhead; colour only reinforces (WCAG 1.4.1, 1.4.11). No
  `cytoscape-svg` (GPL-3.0). A DOM list mirror of the working set for keyboard access.
- **Evidence (measured on this box, headless Chrome / Node, R4 appendix).** 500 nodes / 1,500 edges: Cytoscape import
  414 ms, first render 192 ms, pan p90 50 ms; dagre 1,956 ms; ELK 1,118 ms; viz `dot` 399 ms. 2,000 / 10,000: Cytoscape
  first render 667 ms, pan p90 339 ms; **dagre did not finish in 240 s**; ELK 12.3 s; viz `dot` 11.4–13.7 s (4.8 MB
  SVG); fcose 58.6 s and non-reproducible; `dot` and ELK rerun-identical; dagre reproduces itself but changes with node
  insertion order — so nodes and edges are canonically sorted before any layout. All CDN URLs verified HTTP 200
  (`research/R4_VISUALIZATION.md`, "Verified URLs").
- **Alternatives.** Sigma-first (WebGL) — loses compound nodes, native dashes and SVG export, and headless
  measurements are not GPU-representative; Graphviz-only — static SVG makes expand/collapse and hit-testing ours.
- **Reversibility.** High: the page consumes the §9 JSON through the §10 module; a renderer swap touches one file.

---

## GPT Adjudication v1 (2026-09-02) — rulings recorded as D-016 … D-024

Source: `~/Downloads/GRAPHONOMOUS_GPR0_GPT_ADJUDICATION_v1.md` (verdict: **ACCEPT G-PR0 / AUTHORIZE G0-A, with decisions
D-016 through D-024**) and its companion `GRAPHONOMOUS_G0A_G0B_CONTINUATION_PROMPT.md`. Local numbering had reached
D-015, so GPT's numbers map 1:1; the text below is GPT's ruling in substance with this lane's application noted.
Nothing in the frozen `G0_G1_SPEC.md` is rewritten; §13/§14 carry an amendment pointer to D-022/D-023.

## D-016 — The missing-companion reconstruction stands (GPT: ACCEPT)

- G-PR0 is not restarted to recreate `02_RESEARCH_AGENDA.md`, `03_STACK_REPAIR_PROTOCOL.md` or the `sources/` notes.
  The controlling meaning is restated: Graphonomous is a derived projection; it may observe, relate, derive, diagnose,
  rank and later propose; it may not promote evidence state or write canonical truth back; a real stack defect is
  reduced, repaired in the owning layer with regression evidence, and the original acceptance test is re-run.
- A later-arriving companion is **advisory input**; a concrete conflict with the frozen spec becomes a decision entry.

## D-017 — WRL generic `PROFILES[profile_id]` + static profile kind: approved in principle, with gates (GPT: ACCEPT WITH GATES)

- Gates before Graphonomous may claim "WRL seal-native": `forge.world.core.v1` stays byte/semantic-id compatible
  (both pinned `sem-` ids unmoved); `graphonomous.semantic.v0` is data, not a compiler branch; a static profile means
  **no runtime/admission/film claims are implied** and must not obtain correctness by filling fake no-op runtime
  policies into a semantic identity; profile schemas declare roles, ports, config/value constraints, relation
  signatures, endpoint constraints, canonical defaults and any rulepack/policy vocabulary that participates in
  identity; positive and negative conformance vectors exist.
- `gsem-` is a Graphonomous-owned provisional identity until the official WRL compiler validates and seals the same
  artifact. **Never rename `gsem-` to `sem-`**: when WRL can seal it, create the real `sem-` and record explicit
  supersession/equivalence provenance. (Tightens D-009's "superseded, not silently renamed" into an explicit rule.)
- Not required for G0-A/B.

## D-018 — GAP-W9 (`revision.policy` hashed but unvalidated) is an IMPLEMENTATION_BUG (GPT ruling)

- Repair options: validate `revision.policy` against the active profile's declared rulepack/policy vocabulary
  (preferred for the Graphonomous profile, since the field is meant to select `graphonomous.semantic.rules.v0`), or
  formally rule it an uninterpreted label that no runtime treats as authorization/configuration.
- Closure evidence: negative conformance (undeclared policy refused); positive conformance (declared policy seals);
  existing pinned vectors and `sem-` ids unchanged; a repair receipt linked from the register.
- Non-blocking for G0-A/B; **blocking for any claim that G0-C is officially WRL-sealed.** Register row updated.

## D-019 — The five `prim` names are candidates, not the irreducible basis (GPT: PARTIAL ACCEPT / DO NOT PROMOTE YET)

- The projector evaluation with `trvm_derivation: false` / `not-a-trvm-derivation` provenance stays the truthful G0
  interim (confirms D-007). `eq.canonical/1`, `get.field/1`, `set.count_where/1`, `set.all/1`, `if.value/1` are valid
  candidate capabilities; their independence and minimality are not established (set counting, all-quantification and
  conditional structure may overlap depending on the predicate language and value model).
- Before any candidate enters the frozen derive core or a canonical `prim` catalog: a **Primitive Basis Reduction
  round** — state each candidate's semantic obligation; total deterministic semantics and canonical I/O domain;
  positive and refusal vectors; derive each from the others plus the core; compare at least two smaller bases; separate
  what A6 truly needs from what is ergonomic; keep reachability/traversal separate unless evidence joins it; preserve
  frozen core ids unless a deliberate versioned extension moves them. Recorded as a follow-up task in the register
  (GAP-T14). Graphonomous does not wait for it.

## D-020 — GAP-T5 accepted as an interop need; "one-line fix" rejected as sufficient closure (GPT ruling)

- Persisting a DeriveResult changes the evidence lifecycle. The persisted envelope/root must bind the existing semantic
  projection and its request identity (never a weaker receipt) and preserve the separation between semantic result and
  execution evidence.
- Closure test: persist canonical derivation evidence through the existing CAS; resolve byte-exactly; re-run the
  ownership/footprint/foreign-result validation path from the persisted object; mutate request, program id, grant id,
  semantic result, footprint or bound identity and prove refusal or root movement; document where execution evidence
  lives (inside, separately content-addressed, or intentionally ephemeral); never call persistence a warrant.
- Not required for G0-A/B; Graphonomous's own projector provenance is CAS-stored independently and stays labelled
  non-TRVM. Register row updated (the "one-liner" wording is withdrawn).

## D-021 — MECHANISM from code symbols: accepted with a strict inference boundary (GPT: ACCEPT)

- A `MECHANISM` is minted only when a source record identifies the symbol or an ingestion contract deterministically
  resolves it; it is an **observed implementation referent**, not proof of satisfying an obligation.
- `IMPLEMENTS` is emitted only when the authoritative source supplies the relation or a frozen, auditable adapter
  grammar represents the source's own assertion. Source precision (`symbol`, `file`, …) is recorded; file-level prose
  is never upgraded to symbol-level certainty; unresolvable prose stays `UNSUPPORTED_SOURCE_FORM`; G1 may `PROPOSAL`
  a mapping, never convert it to observed truth. (Confirms spec §3.1 MECHANISM and the crosswalk contract; the
  crosswalk's `relation: mechanism` **is** the source's own assertion, so `IMPLEMENTS` from it is observed.)

## D-022 — A6 becomes an evidence-availability partition; Factory remains the promotion gate (GPT: MODIFY TERMINOLOGY)

- The three buckets stay; the word *unsupported* is withdrawn from G0 output. Frozen names for the derived diagnostic:
  `EXEC_RECEIPT_OBSERVED` (an admissible executed receipt is present under the G0 rule) ·
  `NO_EXEC_RECEIPT_OBSERVED` (the source suffices to establish absence for that rule) ·
  `EXEC_RECEIPT_UNDECIDABLE_FROM_SOURCE` (the source representation cannot decide).
- No inference of "claim false", "claim invalid" or "promotion rejected". The Factory kit's rule D (or the owning
  registry's promotion protocol) is the only gate that may make the promotion/rejection judgment; Graphonomous
  reproduces that gate's result as attributed evidence when present.
- **Amends spec §13/§14 by pointer:** rule `unsupported(C)` is renamed `no_exec_receipt_observed(C)`,
  `undecidable_support(C)` becomes `exec_receipt_undecidable_from_source(C)`, and `has_exec_receipt(C)` reports as
  `EXEC_RECEIPT_OBSERVED`. `rules/g0.rules.json` uses the new names from its first revision.

## D-023 — The two pins are frozen; do not chase HEAD during the baseline build (GPT: CONFIRM)

- `invariant-r10@ba4e625` / `package-v2.7` is the **G0 baseline (current-at-freeze)** snapshot;
  `invariant-r10@699fbc2` / `package-v2.6` is the historical comparison. The v2.7 delta census precedes G0-B (done:
  D-025). Newer invariant rounds become a third snapshot later; neither pin is ever moved to follow HEAD. A2 is
  intentionally snapshot-relative. (Amends the wording of D-008 and spec §14: "current" reads "baseline /
  current-at-freeze".)

## D-024 — G0-A then G0-B authorized; stack repairs are side loops with return-to-test discipline (GPT: GO)

- G0-A: `rules/g0.rules.json`; JSON Schema 2020-12 record schemas; lid grammar with collision/refusal tests; a Node
  canonical-byte test importing TRVM `canonicalBytes`; an independent Python twin; reproduction of the `1.0`
  divergence with proof that the normalized domain removes it; set-valued-field order/duplicate tests; refusal tests
  for malformed Unicode, floats and unsafe integers.
- G0-B: pin and verify every input OID before reading; the delta census; ingest the crosswalk through its frozen
  contract; emit normalized records and typed faults; CAS-store records and manifest through TRVM `cas.mjs`; publish
  the projection root; rebuild with shuffled file and reversed adapter order and require byte-identical root; run the
  Python twin over the manifest; write no registry; mint no `sem-`; label every evaluator result non-TRVM.
- Repair loop when a stack defect surfaces: failing acceptance test → classify owner → minimal reproducer → failing
  owner-layer regression → smallest fix → owner-layer suite → receipt → re-run the original test → continue G0. No
  stack layer is expanded because a host implementation would be inconvenient.

## D-025 — v2.7 delta census: additive shape; the crosswalk contract extends without a second adapter (2026-09-02)

- **Measured at the two pins** (`git show`, never the working tree): crosswalk `CROSS_REGISTRY_CLAIM_MAP.json` v2.6 blob
  `4639a28d…` → v2.7 blob `c7dba29f…`; 56 records in both, no ids added or removed, **no class token moved**; every
  record changed because seven fields were added (`evidence_class_token_v2_6` on 56, `evidence_class_v2_6` 1,
  `subject_identity` 5, `adjudication_ref` 6, `adjudicator` 6, `adjudicated_at` 6, `history_note` 1); three top-level
  keys added (`adjudication_v2_7`, `execution_summary_v5`, `projection {file, sha256, generated_by}`); `promotions[]`
  restructured from 11 to 20 fields (`from_token`/`to_token`/`from_detail`/`to_detail`, `subject_identity {repo,
  artifact, artifact_sha256}`, `cross_lane`, `adjudication_ref`, `adjudicator`, `adjudicated_at`); `r0_8` gains
  `profile[]` and moves power-loss/consensus to out-of-scope; `evidence_state.json` (blob `f1e9b153…`) adds
  `generated_by`, keeps 56/5/1/3 with receipts still bare strings and `executed` null on 48; `statuses[0]` gains
  `profile[]` and `out_of_scope[]`, its `open_findings` is now the F36/F37 sentence; the ledger `10_MACHINE_READABLE_
  LEDGER.json` blob `b1cdc96b…` → `53a5cae8…`.
- **Decision.** One adapter reads both pins: every v2.7-only field is optional in the contract; `subject_identity`
  becomes an `ARTIFACT` descriptor (`sha256` digest) attached to the transition; `adjudication_ref`/`adjudicator`/
  `adjudicated_at` become `ADJUDICATED_BY` edges with `precision: section` when the ref parses; `projection.sha256` is
  verified against the pinned `evidence_state.json` blob (a `CONTRADICTION` fault if it disagrees); `evidence_class_
  token_v2_6` joins the history chain. The delta report is `handoff/research/census/DELTA_v26_v27.md`.

## D-026 — Two encoding errata resolved before code exists (2026-09-02)

- **Decimal strings.** A non-integer or unsafe numeric lexeme in a source is carried as `{"decimal_string": "<lexeme>"}`
  (one ASCII key; the lexeme exactly as written, e.g. `"1.0"`, `"1e21"`, `"-0.0"`), which is the spec §6.2
  `number_form: "decimal-string"` encoding made concrete so arrays can carry it too. Integer lexemes within ±(2^53−1)
  are integers; `-0` is an integer lexeme and canonicalizes to `0` in both languages (measured).
- **Lids are ASCII.** Spec §4.1 restricts lids to `[A-Za-z0-9._:/@+-]` and then shows `§1`; the ASCII rule wins:
  adjudication sections are `s1`, `s21.2` (`adjudication:gpt:exec-v1:s1`). Local parts may also carry `~`, `#` and `%`
  for JSON-pointer and anchor fragments; a local part that cannot be spelled in the grammar is replaced by
  `h.<sha256 prefix 16>` with the raw text kept as an attribute and a `BAD_LID` fault raised.

## D-027 — Three relation kinds added to the closed set: `DEFINES`, `REPRESENTS`, `CROSS_CUTS` (2026-09-02, G0-B)

- **Why.** The crosswalk's `relation` field takes six values (direct · mechanism · corollary · definition ·
  representation · cross-cutting; R7A). Spec §3.2 mapped the first three (`STATES`, `IMPLEMENTS`, `DERIVES_FROM`) and the
  contract mapped the other three to kinds the §3.2 closed list did not contain. Encoding them as one of the existing
  kinds would erase a distinction the source makes. The ontology is "extended only by a decision entry" (§3), so this is it.
- **Semantics.** `DEFINES`: a definition record → the category `definition:crosswalk:DEF`; `REPRESENTS`: a representation
  invariant → the category `representation:crosswalk:REPR` or the obligation it serves; `CROSS_CUTS`: a cross-cutting known
  law → the category `law:crosswalk:CROSS`. The three category nodes are minted from the registry's own
  `semantic_obligations` map (kinds `DEFINITION`, `REPRESENTATION`, `LAW`), so nothing is invented; `COR`, declared and
  used by no record, is recorded on the registry node as `declared_unused_categories` rather than minted.
- **Reversibility.** Trivial before any projection is published; afterwards a kind rename is a supersession of relation lids.

## D-028 — What building G0-A/G0-B decided (2026-09-02)

Each item below was forced by a measurement during the build; none changes a frozen section, each is a rule the code now
enforces and the tests check.

1. **Citation relations vs statement relations.** `WITNESSES`, `SUPPORTS`, `FALSIFIES`, `ATTACKS`, `CITES`, `LOCATED_IN`,
   `ADJUDICATED_BY`, `PRODUCED_BY` are one relation *per citation*, qualified by the citing location (one receipt is E-14's
   sensitivity witness and its repair witness; E-50b names EXP-6 twice, run 1 and C1). Every other kind is one relation per
   (kind, source, target) with assertions from every source that states it (`OPENS`, `CLOSES` fold across the crosswalk
   and the evidence-state projection). Measured: with `OPENS` repeatable the historical snapshot listed F35 twice.
2. **A node is asserted where it is cited, and LOCATED_IN where it lives.** Witness, receipt, adjudication and mechanism
   nodes take the citing pointer as their assertion location; the file/heading/symbol location becomes a `LOCATED_IN`
   relation. Asserting them at the file made two citations collide on one assertion lid, and input order then chose the
   winner — the 74 `DUPLICATE_ID` faults and the first failed reconstruction run.
3. **Per-citation facts ride on the assertion or the relation, never on the node.** A receipt's `sensitivity_type`/`what`
   and an experiment's `part` are attributes of the citation; the F24 closure sentence is an assertion attribute. Putting
   them on nodes produced attribute conflicts between honest sources.
4. **A location's `registry` is the pinned tree it lives in**, taken from the snapshot's source list — never the emitter
   that cited it first. Precision is a function of the fragment (`/…` pointer · `L<n>` line, `symbol` only when the
   symbol was found on that line · other text heading · none file); fragments are percent-encoded so `/resolved_candidates/S6?`
   keeps its readable lid.
5. **Unnamed findings are keyed by the hash of their sentence** (`finding:inv:h.<16>`), and both emitters parse open-finding
   sentences with one rule (every F-id named is a finding the round opens), so two registries quoting one sentence meet.
6. **The factory canonical ref is a pinned source** (`~/.invariant-factory/canonical.git#d217ee2`): the crosswalk's
   `claim-ledger` records cite `scripts/emb-support.mjs`, `mosaic/embodiment.json` and bare claim ids (`EMB-CUT-EMPTY`,
   `TAX-FLOW`, `TAX-RELATIONAL-2`) that resolve only there; a bare id is accepted only when it exists in the pinned
   `CLAIM_LEDGER.json`.
7. **`wrl-core` citations resolve in the TRVM tree.** `WRL_CORE_0.2 §7` names `TRVM/WRL_CORE_0.2.md` (headings verified at
   `fd0df4c`), not a file in the WRL repository — recorded as Q-22.
8. **Test-suite labels are a named form.** `ampd/test effect (7)`, `cd-core tests` are `UNSUPPORTED_SOURCE_FORM` (form
   `directory-label` / `label`), not `DANGLING_WITNESS`; only `EVIDENCE-nc17-19-23-AFTER-efa8881.txt` dangles (Q-13).
9. **Baseline vs historical are two projections, two roots, never merged.** A2 and A4 are answered per snapshot: at
   `699fbc2` the R0.8.5 handback witnesses E-13b and E-14; at `ba4e625` E-13b's sensitivity witness is the R0.8.6 handback.
10. **No stack repair was needed in G0-A/B.** TRVM `canonicalBytes` and `cas.mjs` carried every record and manifest of both
    projections unchanged (3,000+ CAS objects each, all resolving `ok`); the labelled adapters of D-007/D-009 stand.

## D-029 — Relation identity is the proposition; citation location leaves relation identity for every kind (2026-09-03, GPT Adjudication v2 Q1: CHANGE D-028 §1)

- **Decision.** A relation is `(kind, source_lid, target_lid[, explicit semantic qualifier])`. Every source occurrence that
  states it is an `ASSERTION` on that one relation. The pre-B.1 rule "WITNESSES / SUPPORTS / FALSIFIES / ATTACKS / CITES /
  LOCATED_IN / ADJUDICATED_BY / PRODUCED_BY are one relation per citation, qualified by the citing location" (D-028 §1) is
  **withdrawn**; `REPEATABLE_RELATION_KINDS` is removed from `lib/lid.mjs`. Occurrence metadata — `role`, `what`, `part`,
  `outcome`, `executed` (of the promotion the citation belongs to), `sensitivity_type`, `type`, `note`, `source_id`,
  `cited_as`, `section`, `listed_as`, `mention`, `text`, `declared`, `disposition`, `as_of`, `asserted_by_record`,
  `raw_token`, `qualified`, `resolution_basis` — rides on the assertion record's `attrs`. The relation record's `attrs`
  keeps only what is true of the proposition itself: `relation_field` (the source's spelling of the kind) on the six
  `relation`-field kinds and `from_text`/`to_text`/`typed` on `SUPERSEDES` (measured: no other relation attribute
  survives the fold at either pin).
- **Typed semantic qualifiers.** A field that changes the proposition rather than describing one citation of it must be
  promoted to a qualifier declared per kind in `RELATION_QUALIFIERS` (`lib/lid.mjs`), spelled `<name>=<value>` in the
  lid; an undeclared qualifier is refused (`QUALIFIER_UNDECLARED`), never improvised from the location. **The table is
  empty at B.1.** Candidates examined and rejected: `role` (sensitivity / pre-fix / repair — how a promotion uses the
  receipt, not what the receipt witnesses), `part` (`EXP-6 run 1` / `EXP-6 C1` — sub-designations of one experiment
  producing one claim), `what` and `outcome` (statements about the occurrence), `section` (already inside the target
  location lid), `cited_as` (wording).
- **Evidence.** Rebuilt at both pins: baseline relations 786 → 588 with assertions unchanged at 1,272 (historical
  741 → 566, assertions 1,210); `WITNESSES` 184 → 105, `LOCATED_IN` 246 → 137, `PRODUCED_BY` 21 → 20 (E-50b's two EXP-6
  citations fold), `ADJUDICATED_BY` 27 → 20, `CITES` 28 → 26; zero `DUPLICATE_ID`, zero `CONTRADICTION` — no two
  assertions of one proposition disagreed on a proposition-level attribute, which is the empirical check that nothing
  moved onto the assertion was actually semantic. The R0.8.5 handback receipt now witnesses E-14 as one relation with a
  `sensitivity` and a `repair` assertion (GPT's worked example); E-13b's R0.8.6 handback carries three roles on one
  relation. A8 holds under plain / reversed / two seeds (`test/projection.test.mjs`).
- **Why.** The spec (§2, §4.3) already separated statement from assertion; the per-citation scheme re-collapsed them
  and would have made WRL `rel-` identity depend on provenance occurrence — exactly what G0-C is about to freeze.
- **Reversibility.** A relation lid is now a pure function of `(kind, source, target)`; re-qualifying a kind later is a
  supersession of lids under a new decision, never a silent rename.
- **Amends by pointer:** spec §4.3 (qualifier = "the asserting source's lid") and D-028 §1, §3.

## D-030 — Unnamed findings take a context-bound identity: hash(container ‖ NUL ‖ exact sentence) (2026-09-03, GPT Adjudication v2 Q1b: ACCEPT THE IDEA, AMEND THE BASIS)

- **Decision.** `finding:inv:h.<sha256(UTF-8(container_lid) ‖ 0x00 ‖ UTF-8(sentence))[:16]>` via `contextBoundLid()` in
  `lib/lid.mjs`. The **container is the ROUND** whose `open_findings` list holds the sentence (`round:computedriven:R0.8`
  from the crosswalk's `r0_8` and from `evidence_state.statuses[].id`): it is the nearest authoritative semantic container
  both registries can name deterministically, so two registries quoting one sentence under one round meet on one lid
  (measured: the F36/F37 sentence has one finding with an assertion from each registry), while the same words under
  another round are another finding (`test/b1.test.mjs` synthesizes R0.8 and R0.9). The **sentence is the source JSON
  string value exactly** — no case folding, whitespace normalization or rewording — and stays on the node as `text`, with
  `container` and an `identity` note. NUL cannot occur in a lid or in a G0 string (spec §6.2), so the encoding is
  injective. Registry identity is deliberately *not* in the hash (that would forbid cross-source co-reference by
  construction); the pre-B.1 sentence-only hash is withdrawn (it would have merged unrelated findings that happen to share
  wording).
- **Refinements from the prior-art check (R9, same day).** (i) A fixed domain tag `G0-CONTEXT-BOUND-LID-v1` leads the
  hash input (Git's `type SP size NUL`, DSSE's PAE, RFC 6962's leaf prefix all separate hash purposes by a fixed prefix),
  so this digest can never coincide with a digest of the same bytes taken for another purpose. (ii) RDFC-1.0 (Rec.
  2024-05-21) also labels a blank node by a hash over its neighbourhood — the container-in-the-hash choice is the
  established practice, not an invention. (iii) RDFC-1.0 escalates on collision; G0 does not need to: two byte-identical
  sentences in ONE container's list are the same finding **by the ruling** ("same container + same sentence may
  co-refer") and appear as one node with two assertions; the list ordinal is deliberately not identity so reordering a
  list renames nothing.
- **Later authoritative ids** may `SUPERSEDES` / identify the anonymous node; it is never renamed.
- **Amends by pointer:** D-028 §5.

## D-031 — Bare identifiers: resolve when unique across every eligible pinned namespace, keep the raw token, report the source defect (2026-09-03, GPT Adjudication v2 Q3)

- **Decision.** A bare token in a `claim-ledger` record's `source_ids` matching `BARE_TOKEN` (`^[A-Z][A-Z0-9]*(-[A-Z0-9.]+)+$`)
  is resolved by `resolveBareToken()` against the **eligible namespaces of that field at this pin**: the factory
  `CLAIM_LEDGER.json` claim ids, the crosswalk's own record ids, and the crosswalk's obligation / candidate keys. Exactly
  one match → the `CITES` edge is emitted with assertion attrs `{raw_token, qualified: false, resolution_basis:
  "unique-pinned-match", resolved_namespace, resolved_in: <repo@commit>}` **and** a non-blocking `UNQUALIFIED_REFERENCE`
  fault (new §12 code; added to `fault.schema.json`) naming the claim and the resolved target. Two or more matches →
  `AMBIGUOUS_IDENTIFIER` with the candidate lids, **no edge, no minted node**. No match → `UNRESOLVED_LINK`
  (`reason: bare-token-absent`). Adding a namespace to the eligible list can only widen refusal, never resolution.
- **Evidence.** Real data: `EMB-CUT-EMPTY` (E-40), `TAX-FLOW`, `TAX-RELATIONAL-2` (E-41) resolve uniquely → 3
  `UNQUALIFIED_REFERENCE` at each pin (61 → 64 faults). The ambiguous path is exercised synthetically
  (`test/b1.test.mjs`): a ledger that carried `FAC-CONTROL-SENSITIVITY` would collide with the crosswalk's factory
  candidate of that name → no edge; drop it from the ledger and the same token resolves to the obligation.
- **Prior art (R9 §C).** CURIE, JSON-LD 1.1, identifiers.org and Bioregistry all *refuse or leave unexpanded* an
  unprefixed token; resolving one at all is the departure, and the non-blocking fault is what compensates. The
  resolution is replay-stable because `resolved_in` names the pinned commit whose ledger bytes decided it.
- **Source repair** stays with the registry: write `claim-ledger:<id>`. Recorded as Q-30.

## D-032 — The rule set becomes assertion-aware; the G0 admissibility rule for an executed receipt is stated (2026-09-03, G0-B.1)

- **Decision.** `rules/g0.rules.json` v2 adds base facts `asrt(A, Subject, Loc)` and `aattr(A, Name, Value)` (projected
  from assertion records by `lib/facts.mjs`) and rewrites the three rules that read occurrence attributes:
  `supports(W,C) :- rel(R,WITNESSES,W,C), asrt(A,R,_), aattr(A,outcome,pass)` (likewise `falsifies` with `fail`) and
  `has_exec_receipt(C) :- rel(R,WITNESSES,W,C), node(W,RECEIPT), attr(W,sha256_verified_at_pin,true), asrt(A,R,_),
  aattr(A,executed,true)`. The last is **the G0 admissibility rule** D-022 left implicit: a receipt is admissible when its
  recorded sha256 verifies at the pin, and executed when the promotion citing it says `executed: true` (carried on the
  citing assertion, since the same receipt could be cited by promotions with different flags). Two citations of one
  receipt are two derivations of one fact, never two facts. The pre-B.1 rule read `attr(W, executed, true)` on the RECEIPT
  node, an attribute no receipt node carries — it would have derived nothing; the A6 test computed the partition by hand.
- **Consequence.** The content-bound rule id moves from `g0rule-48857b8f…` to the id printed by `loadRules()`; the manifest
  binds the program, so both B.1 roots differ from the pre-B.1 roots for this reason as well. No pre-B.1 rule is renamed.
- **Amends by pointer:** spec §13 (rule bodies) and §10.2 (fact model).

## D-033 — Order: G0-B.1 → G0-E → G0-C; D-027 stands; pre-B.1 receipts are preserved; handoff bundles carry REPRO_DEPENDENCIES (2026-09-03, GPT Adjudication v2 Q2, Q4, §0)

- **Q4 (order).** G0-C is deferred until the evaluator and query surface have consumed the corrected graph and A1–A7 are
  executable queries: WRL `rev-`/`rel-`/`gsem-` must not be minted from an identity model the first consumer has not
  tested. This is a detour, not a change of direction; the G0-C plan of D-009/D-017 is unchanged.
- **Q2.** `DEFINES`, `REPRESENTS`, `CROSS_CUTS` stand (D-027) as Graphonomous ontology kinds — not WRL/TRVM primitives;
  `CROSS_CUTS` implies no transitivity, inheritance, authority or dependency; `relation_field` stays as provenance; a
  later Ontology Basis Reduction may test reducibility.
- **Pre-B.1 receipts.** `projections/pre-b1/{baseline,historical}` keep the pre-B.1 builds intact (roots
  `root-d1dd7756…` and `root-5051394e…`, still `g0 verify`-clean) with the pre-B.1 `EVIDENCE.md`; they are superseded
  by the B.1 roots and never overwritten.
- **Reproducibility.** Every GPT handoff ZIP from now on carries `REPRO_DEPENDENCIES/`: byte-exact copies of every
  sibling file the shipped code imports (TRVM `derive_protocol.mjs`, `cas.mjs`, `observed_execution_host.mjs`,
  WRL `relation-identity.js`, …) with repository, commit, blob OID, sha256 and original path — verification copies only;
  production imports the real sibling checkout (`canon.mjs` refuses a moved TRVM blob).

## D-034 — OPEN (ruling requested): transition→claim `SUPERSEDES` versus the frozen `current` rule (2026-09-03, found by G0-E)

- **What the first consumer found.** The crosswalk adapter (G0-B) encodes each token-history step and each typed
  promotion as an `EVIDENCE_STATE_TRANSITION` node with `SUPERSEDES transition → claim` (the contract's "history fields
  become transition nodes and SUPERSEDES relations", spec §4.7). The frozen rules `superseded(X) :- rel(_, SUPERSEDES, _,
  X)` and `current(X) :- node(X,_), not superseded(X), not retracted(X)` (spec §13) therefore derive `superseded` for the
  eight claims that have any recorded transition — E-12, E-13a, E-13b, E-13c, E-14, E-15, E-48, E-51 — and `current`
  excludes exactly the best-evidenced claims of the dataset (measured at both pins; `test/query.test.mjs` pins the pattern
  so neither side can change silently).
- **Why this is a semantic disagreement, not a bug to patch.** Spec §3.2 gives `SUPERSEDES` the meaning "record revision →
  record revision; round → round; claim → claim": a *later* thing replaces an *earlier* thing. A transition does not replace
  the claim — it moves the claim's evidence state; the claim lid is the same before and after. So either the adapter's
  edge kind is wrong (a transition should point at the claim with a kind that means "moves the state of"), or the rule's
  premise is wrong (only claim→claim / revision→revision `SUPERSEDES` should retire a record). Both the emitted relation
  and the frozen rule text are contracts; choosing one is the adjudicator's call.
- **Options put to GPT.** (A) *Preferred:* add a relation kind for transition → claim (e.g. `MOVES_STATE_OF`, or reuse
  `MEMBER_OF` in its "record → round" sense — the transition is a record of the claim), and emit `SUPERSEDES` only along
  the transition chain (`transition_k SUPERSEDES transition_{k-1}` for one claim, in package order) so the spec's
  "revision → revision" reading holds; `current` then keeps every claim and retires superseded transitions. (B) Keep the
  edge and restrict `superseded` to `rel(_, SUPERSEDES, Y, X), node(Y, K), node(X, K)` (same kind on both ends). (C) Keep
  both and document that `current` is about *evidence-state records*, not claims — rejected here because `current` is
  spec-defined over `record(X)` generally.
- **Interim.** Nothing is changed: the projection roots and the evaluation are published with the disagreement visible.
  `current`/`superseded` are not used by A1–A7. G0-C is not blocked by this, but the choice moves relation lids and must
  land before `rel-`/`gsem-` are frozen.

## D-035 — G0-E as built: evaluator, checker, evaluation artifact, query surface (2026-09-03)

- **Evaluator (`lib/eval.mjs`).** Stratified, semi-naive; terms compared by canonical bytes; derivations collected
  **exhaustively** (every ground rule instantiation whose premises hold — a finite set) and only then ranked by `(depth,
  canonical bytes)` and capped at `max_alt = 4`, so the kept alternatives are a function of (program, fact set) and not of
  the iteration schedule; depth is recomputed to a fixpoint at the end (base 0; derived = 1 + max positive-premise depth,
  minimum over derivations). Measured: seeded shuffles of the base facts give the identical derivation-set digest
  (`test/eval.test.mjs`, `test/query.test.mjs` E-3); a transitive closure over a 3-cycle terminates with 9 facts.
- **Variable convention fixed.** `rules.mjs` accepted any capitalised token as a variable, so `WITNESSES`, `RECEIPT`,
  `TESTED` in the frozen rules were "variables" — harmless in positive atoms (they bound and then had to match), refused in
  a negated atom. Rule: a variable is an initial capital followed by lowercase/digits/underscore (`C`, `Var1`); everything
  else is a constant. Written into the rule set's comment (which moves the content-bound id — the manifest binds the
  program, so both projections were rebuilt: `g0rule-0291a139…`).
- **Independent checker (`lib/check.mjs`).** Shares no logic with the evaluator; re-substitutes the recorded bindings,
  requires every positive premise to be a fact strictly shallower than the conclusion, every `{absent}` premise to have no
  matching fact (wildcards honoured), the head to equal the conclusion, depth = 1 + max premise depth, and the id
  `sha256(canonical {rule, conclusion, premises})` to recompute. Tampering with the conclusion, a premise, a binding, the
  rule name, an absence or the depth is refused with a named reason — in memory and from the stored artifact.
- **Evaluation artifact.** `<projection>/derived/` = `facts.jsonl` (one `derived_fact` record per ground atom, `basis:
  derived`, `inputs: [projection root]`, `evaluator: graphonomous.g0.eval.v0`, `trvm_derivation: false`) +
  `manifest.json` (`kind: graphonomous.rule-evaluation`, projection root, ruleset id, per-rule counts, derivation-set
  digest, checker result) + its own CAS and `ROOT`. **The observed projection root is untouched by evaluation**; the
  evaluation root binds it. `g0 verify-eval` replays every stored derivation through the checker against base facts
  rebuilt from the projection records. Baseline: 404 derived facts / 414 derivations; historical: 393 / 403; both replay
  clean.
- **Query surface (`lib/query.mjs`).** Exactly `node · neighbors · path · facts · explain · as_of` (spec §10.1); `facts`
  takes a rule name (derived), a node/relation kind, or `FAULT`; `explain` unfolds an observed record to its assertions
  and pinned locations, and a derived fact to its derivation tree with base facts rendered through the records they are
  about and `{absent}` as leaves — it never re-derives. A1–A7 are executable query tests over the SHIPPED projections
  (`test/query.test.mjs`, no git needed), plus the six continuation tests and the D-034 pattern.
- **What G0-E did not do.** No TRVM primitive was added or requested (D-019 stands; the evaluator wants nothing the
  projector cannot supply). `supports`/`falsifies` derive nothing on this dataset because no source states an
  `outcome` — recorded honestly, not fabricated from `sensitivity_type`. The Python twin covers the projection root and
  the CAS; a Python replay of the derivation checker is a follow-up, not a claim.

## D-036 — G0-C executed as a SPIKE: real kernel `rev-`, G0-computed `rel-`, `gsem-`; identities PROVISIONAL, not frozen (2026-09-03)

- **Why a spike and not a freeze.** GPT's order (D-033) makes G0-C conditional on G0-E green *and* a coherent round.
  G0-E is green (69 → 77 tests), but two rulings now stand between the world and a freeze: D-034 (the transition→claim
  `SUPERSEDES` kind, which moves relation lids and therefore every `rel-`/`gsem-`), and the three kernel findings of R10
  (GAP-W11/W12/W13: the kernel refuses a `gsem-` world scope, refuses lids as `object_id`s, refuses the profile at the
  world canonicalizer). Freezing identities over those would fossilize exactly what GPT asked not to fossilize. Building
  the world anyway, against the real pinned kernel, turns each ruling into a concrete before/after instead of an
  abstraction — the same move G0-A/B made for identity. Everything minted here is marked `PROVISIONAL` in
  `world/identities.json`; nothing downstream consumes it.
- **What is the kernel's.** `rev-` = WRL `relationRevisionId(canonicalizeRelationRevision(revision))` at `1f4c5fd`
  (the two imported files blob-pinned by `assertWrlPinned`); the revision is `{domain: semantic, kind, orientation: directed, texture: solid,
  endpoints[source/target → {object_id, port: node}], attributes: <proposition-level relation attrs, D-029>, policy:
  graphonomous.semantic.rules.v0}`. Measured on the baseline: one attribute edit moves exactly one `rev-`.
- **What is G0's, labelled.** (i) `object_id` = a reversible encoding of the lid into `\w+` (`_` → `__`, other
  non-alphanumerics → `_HH` per UTF-8 byte; profile `object_id_encoding`; round-trips every lid of both pins; the raw lid
  stays in `static_config.lid`). (ii) The world envelope `{ir_version: "2.0", profile_id: graphonomous.semantic.v0,
  semantic_policies: {rulepack_id}, objects (nodes AND source locations, identity-first order), relations (seed-sorted,
  duplicate seeds refused)}` and `gsem-` = sha256 over WRL `serializeArtifact` bytes. (iii) `rel-` = sha256 over
  `serializeArtifact({tag: WRL_RELATION, variant: named-initial, world_id: <gsem->, relation_name: <statement lid>})` —
  the D8.1 preimage; the test proves the same function equals the kernel's `relationIdFromAllocation` for a `sem-` scope
  and that the kernel throws `WRL_BAD_ALLOCATION` for the `gsem-` scope. Every `rel-` carries `rel_minted_by:
  g0-d8.1-preimage`; no `rel-` is called kernel-minted; no `sem-` exists anywhere in the artifact.
- **Identity laws measured (`test/wrl_world.test.mjs`).** Same projection ⇒ same bytes and `gsem-`; shuffled record order
  ⇒ same; one relation-attribute edit ⇒ that `rev-` moves, all others hold, `gsem-` moves, **every `rel-` moves** (WRL
  D8.5 world scoping — the stable cross-world name is the statement lid); an assertion-only edit ⇒ nothing moves (WRL
  D8.3: provenance is outside the revision — this is the behaviour GPT asked to have specified and tested rather than
  assumed); a node-attribute edit ⇒ `gsem-` moves, no `rev-` moves; no coordinates / timestamps / hosts / assertions in
  the bytes; the profile's endpoint constraints hold for every relation at both pins (widened once from the spec table
  where the data showed `REPRESENTS → LAW`) and refuse a violating or dangling relation.
- **Not claimed.** Not "WRL-sealed", not "seal-native" (D-017 gates + GAP-W9 stand); a future real `sem-` will not be
  byte-identical (the derived envelope) — supersession with recorded equivalence, never rename. The `world/` artifact is
  outside both the projection root and the evaluation root; it binds the projection root it was built from.

## GPT Adjudication v3 (2026-09-03, input `GRAPHONOMOUS_G0B1E_FOR_GPT.md`) — rulings recorded as D-037 … D-046

State ruling: G-PR0 FROZEN · G0-A TESTED · G0-B historical · **G0-B.1 ACCEPTED / TESTED** · **G0-E ACCEPTED / TESTED** ·
G0-C spike ACCEPTED AS EVIDENCE ONLY, identities PROVISIONAL · G0-C final BLOCKED on D-034 + WRL profile/sealing closure ·
G0-D partly TESTED · G0-F/G0.5/G1 later · TRVM primitive basis unchanged (no primitive justified by G0-E). "Fable did the
right thing by stopping instead of freezing over D-034 / GAP-W11..W13."

## D-037 — D-034 RULED: transition → claim is `STATE_TRANSITION_OF`; `SUPERSEDES` is replacement between comparable entities (2026-09-03, GPT v3 §1: option A with an explicit kind)

- **Decision.** The adapter relation `TRANSITION --SUPERSEDES--> CLAIM` is semantically wrong: a transition changes the
  evidence state *of* a claim, it does not replace the claim. Every such edge becomes `TRANSITION --STATE_TRANSITION_OF-->
  CLAIM`; the transition keeps its typed `from_token`/`to_token`, receipt/adjudication data and other transition-specific
  properties. `STATE_TRANSITION_OF` joins the closed relation-kind set (§3.2; endpoints `EVIDENCE_STATE_TRANSITION` →
  `CLAIM`). The relation attrs that rode on the old edge (`from_text`/`to_text` on history steps, `typed: true` on
  promotions) ride unchanged on the new kind — only the kind changes, so the proposition is the same edge under its
  correct name.
- **`SUPERSEDES` frozen meaning.** A true replacement between semantically comparable entities: claim → claim where one
  claim replaces another; revision → revision; round → round; transition → transition **only** when a later source
  explicitly states replacement of one transition record by another. `SUPERSEDES` is **never** inferred from temporal
  order — so the D-034 option-A variant "emit SUPERSEDES along the transition chain" is NOT taken. Endpoint constraints
  now refuse transition → claim `SUPERSEDES` (profile pairs `[CLAIM,CLAIM]`, `[ROUND,ROUND]`,
  `[EVIDENCE_STATE_TRANSITION,EVIDENCE_STATE_TRANSITION]`; the emitter refuses a kind-mixed SUPERSEDES at projection time).
- **Rules.** The frozen `superseded(X) :- rel(_, SUPERSEDES, _, X)` and `current` rules stay as written; `current` is not
  patched to compensate for a bad edge (options B and C rejected). After the repair `superseded` derives nothing on this
  data and `current` includes the eight best-evidenced claims (E-12, E-13a, E-13b, E-13c, E-14, E-15, E-48, E-51).
- **Consequence.** Relation lids move for 14 relations at each pin, so both projection roots, both evaluation roots,
  both spike `gsem-` and the ruleset id move. The pre-D-034 B.1/E roots are preserved under `projections/pre-d034/` as
  receipts and never overwritten (the numbers are in `projections/EVIDENCE.md`; the old/new pairs are in STATUS.md).
- **Class.** A modeling repair in Graphonomous, not a WRL/TRVM stack change.

## D-038 — GAP-W11 RULED: do NOT widen `validateAllocation`; spike ids are provisional and carry a non-WRL name (2026-09-03, GPT v3 §2)

- **Decision.** `rel-` means a WRL allocation identity under a WRL-sealed semantic world. If the kernel refuses `gsem-`,
  Graphonomous must not weaken the kernel to reuse the prefix, and a value the kernel cannot mint must not be frozen or
  presented as a canonical `rel-`. The R10 proposal "accept `g?sem-` in `validateAllocation`" is withdrawn.
- **Treatment of the spike.** The D-036 world artifacts stay as historical/provisional measurement artifacts (they proved
  the preimage and the world-scoping law). From this round the G0-computed preimage id is emitted under the field
  `provisional_allocation_preimage_id` with the non-WRL prefix `grelpre-` (same hex), `provisional_minted_by:
  g0-d8.1-preimage`; nothing may call it a `rel-`. Once WRL seals `graphonomous.semantic.v0` to a real `sem-`
  (D-039), the real kernel allocation path mints the real `rel-` and the spike is superseded for WRL-world purposes.

## D-039 — WRL stack repair AUTHORIZED: `WRL-P0 — Static Profile + Seal Closure` (2026-09-03, GPT v3 §3; the first Graphonomous-driven owning-layer round)

- **Failing application requirement (concrete).** A deterministic Graphonomous semantic statement world exists, but WRL
  cannot seal its static profile to a real `sem-`, so the kernel cannot allocate its relations through the normal `rel-`
  path (R10 §4: `assertV2Artifact` refuses the profile; forging it dies at `projectRelationRevisionToV1Edge`).
- **Goals.** (1) the smallest generic static-profile mechanism needed to seal more than the built-in profile; (2)
  `forge.world.core.v1` stays valid, every pinned `sem-`/`rev-` unchanged; (3) `graphonomous.semantic.v0` admitted through
  that same mechanism, never an app-specific bypass; (4) WRL owns final semantic artifact validation, canonicalization
  and `sem-` sealing; (5) GAP-W9 closed with a failing test + smallest validation repair that does not alter valid
  revision bytes; (6) no TRVM change; (7) `validateAllocation` not widened; (8) no unrelated WRL feature. Suggested
  (not commanded) shape: `PROFILES[profile_id]` + a static profile kind, forge as the compatibility row.
- **Acceptance.** Owning-layer failing test before repair; WRL conformance suite after; identity non-regression vectors;
  the Graphonomous G0-C reproducer green through the real WRL API; a stack-fix receipt with old/new WRL commit/blob ids
  and exact tests (`STACK_FIX_RECEIPTS/`).
- **Do not solve this in Graphonomous host code.** The `gsem-` canonicalizer of D-036 is retired when WRL seals.

## D-040 — GAP-W12 RULED: the reversible lid → `\w+` object-id encoding is accepted as a profile adapter (2026-09-03, GPT v3 §4)

- Accepted while it remains injective, reversible, deterministic, defined only over the Graphonomous lid grammar,
  versioned/profile-bound, and tested for collision refusal and round-trip. The original lid stays as semantic data in the
  profile object (`static_config.lid`). It is an interoperability encoding, not the native Graphonomous identity. WRL's
  core `\w+` grammar is not widened in this round; a second application proving the grammar wrong reopens it.

## D-041 — GAP-W13 RULED: final world canonicalization belongs to WRL; three identities stay explicit (2026-09-03, GPT v3 §5, §8)

- **Ownership.** Graphonomous owns the observed projection root, statement/assertion semantics and the semantic profile
  input it asks WRL to seal. WRL owns validation of the admitted profile, the canonical semantic artifact bytes, the real
  `sem-`, and kernel allocation from it. The current `gsem-` is a Graphonomous spike/candidate-world receipt, not the
  canonical WRL world identity.
- **Non-requirement.** The real `sem-` need not be byte-identical to, or derivable by re-prefixing, the `gsem-`; the two
  have different owners and preimages. The manifest keeps the explicit mapping `projection_root → provisional gsem
  (historical spike) → final WRL sem` and the final `sem-` supersedes the spike for WRL-world purposes.
- **Three identities (§8).** *Projection root* = the full observed snapshot incl. assertions/provenance; *evaluation root*
  = derived G0-E understanding bound to one projection root; *WRL `sem-`* = the statement/object world of
  `graphonomous.semantic.v0`. An assertion/provenance-only edit may move the first two and leaves the third unchanged —
  intentional for this profile: G0-C is explicitly the **semantic statement world**, not the complete epistemic/evidence
  world. If provenance should become WRL-native, define a separate `graphonomous.evidence.v0` world rather than mixing
  occurrence data into relation revision identity.

## D-042 — G0-C profile/envelope shape: strong candidate, frozen only after WRL-P0 seals it (2026-09-03, GPT v3 §6)

- Directionally accepted: profile `graphonomous.semantic.v0`; IR-v2-shaped envelope; `semantic_policies.rulepack_id`;
  objects carrying the stable lid + semantic attrs; one nominal `node` port where current WRL requires one; endpoint
  constraints measured against the real projection (the `REPRESENTS → LAW` widening stands, backed by projection evidence
  and a conformance test); no layout coordinates/timestamps/hosts in semantic identity. Exact bytes/schema freeze only
  after WRL admits the profile through its real sealing path.

## D-043 — Statement lid / `rev-` / `rel-`: the measured world-scoping behaviour is accepted as the law (2026-09-03, GPT v3 §7)

- **Graphonomous statement lid** = stable identity of the proposition across worlds; **`rev-`** = content identity of one
  relation revision; **`rel-`** = allocation identity of that named relation inside one exact world (`sem-`). After one
  semantic relation edit: the edited statement's `rev-` moves, unrelated `rev-` hold, `sem-` moves, every world-scoped
  `rel-` may move (the allocation preimage includes the world id), statement lids remain the cross-world names. Expected
  world scoping, not semantic identity instability.

## D-044 — `has_exec_receipt` stays generic over any subject (2026-09-03, GPT v3 §9)

- `has_exec_receipt(Subject)` holds for any semantic subject actually witnessed by a verified executed receipt, including
  transitions; the A6 rules join against `tested_claim` where claim-only semantics are wanted. The rule variable is
  renamed `C` → `Subject` (this moves the content-bound ruleset id). A regression test shows one claim and one transition
  both satisfy it while the A6 claim partition is unchanged (EXEC_RECEIPT_OBSERVED = E-13b, E-14, E-15, E-48).

## D-045 — Checkpoint rule: Graphonomous v2 gets local commits from this round on (2026-09-03, GPT v3 §10)

- After D-034 is repaired and the rebuilt B.1/E suites are green: a **local Graphonomous checkpoint commit** of the
  reviewed v2 state (OID recorded in the handoff); no push unless separately configured; WRL edits never mixed into it.
  WRL-P0 is a separate commit in its own repository. After WRL-P0 is accepted, Graphonomous updates its pinned WRL ref
  and finishes G0-C in a new Graphonomous commit. The lane thereby gets the pinned-source discipline it imposes on the
  registries it reads (D-001's "uncommitted beside v0.4" arrangement ends).

## D-046 — Execution order for this round (2026-09-03, GPT v3 §11)

- `D-034 repair` → rebuild baseline/historical → rebuild evaluations → rerun B1 + E + A1–A7 + four-order A8 + twin/CAS
  → Graphonomous G0-E checkpoint commit → `WRL-P0` → WRL conformance + non-regression + stack-fix receipt + WRL commit →
  update the Graphonomous WRL pin → final G0-C through real WRL sealing → mint real `sem-` + kernel-minted `rel-` →
  verify statement/revision/allocation identity laws → clean GPT handoff. **Stop before G0-D/F/UI.** The WRL repair and
  the first real sealed Graphonomous world are reviewed as a milestone.
