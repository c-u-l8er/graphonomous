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

## D-047 — WRL-P0 as built: a profile table with two row kinds, and GAP-W9 closed at the world gate (2026-09-03; WRL `1f4c5fd` → `b072db0`, receipt `STACK_FIX_RECEIPTS/WRL-P0.md`)

- **Decision (WRL-owned, recorded here for the lane).** `relation-v2.js` gains `V2_PROFILES`, frozen data keyed by
  `profile_id`, each row tagged `derivation: "lowered" | "static"`. `forge.world.core.v1` is the lowered row (declares
  nothing; the frozen spine's registries are its declaration, reached through `v2WorldAsV1 → graphToIr` as before; its
  rulepack is read from `V2_RELATION_SOURCE_FAMILIES["2.0"]`, which stays the ir_version's default profile, and its domain
  from the kernel's `profileDefaultDomain`). `graphonomous.semantic.v0` is the static row: roles + ports, domain,
  signature, 31 kinds → explicit (source role, target role) pairs, policies. `v2WorldOfStaticProfile` reads the row and
  never asks which row it reads; a static profile derives `semantic_policies = {rulepack_id}` and nothing else (no
  `schemas`, no `state_schema_ref`, no admit/film/numeric policy — D-017), and the downgrade, runtime projection and text
  surface refuse a static world (a seal is not a run). GAP-W9: every relation's `revision.policy` must be in the profile's
  declared vocabulary (`WRL_UNDECLARED_POLICY`), validation only.
- **Alternatives rejected.** Keying by `ir_version` (every profile would be a new encoding); a `deriveWorld` function per
  row (a branch in a costume); deriving runtime fields from defaults for a static row (a no-op runtime claim sealed into
  identity); widening `validateAllocation` to `gsem-` (D-038); a separate served data module (no deploy story).
- **Evidence.** Failing-first: with the 10 new checks and the old code, `891 passed, 9 failed` — the graphonomous seal
  refused `WRL_UNSUPPORTED_PROFILE` and a forge world with `policy: "anything.at.all"` sealed to `sem-b9b0c089…`. After:
  `900 passed, 0 failed`; five projection vectors, DEMO/STARTER ids, migration `rel-`/`rev-` lists byte-identical
  (`NO BYTE OR ID MOVED`). Kernel and spine blobs unchanged; TRVM untouched. Minimized world seals to `sem-282c71b6…`
  with kernel `rel-b1180b9b…` / `rev-8da1d819…`, `kernel_agrees: true`.
- **What this settles for G0-C.** Graphonomous submits the artifact; WRL canonicalizes, validates the profile, seals the
  `sem-` and mints every `rel-`/`rev-` (`canonicalizeV2Artifact` / `v2WorldIdOfArtifact` / `deriveV2Relations`). The lane's
  own canonicalizer, `gsem-` and `grelpre-` leave the live path and remain as the historical spike (D-038, D-041).
- **Open for the WRL owner.** `OBJECT_ID_RE` restates the kernel's private `IDENT_RE`; no `spec.html` pending-register row
  exists for static profiles because no D8 rule number states them — a spec-text follow-up.

## D-048 — Final G0-C: both worlds SEALED by WRL; the spike's bytes turned out identical to WRL's canonical bytes (2026-09-03, measured, not assumed)

- **Decision.** G0-C now runs through the real WRL path at pin `b072db0` (`canonicalizeV2Artifact` → `v2WorldIdOfArtifact`
  → `deriveV2Relations`): baseline `sem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be` (1,080
  objects / 588 relations / 960,827 canonical bytes), historical `sem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23`
  (1,052 / 566 / 920,425). Every `rel-` and `rev-` is the kernel's (`minted_by: wrl-kernel@b072db0`; 588/588 and 566/566
  re-derived through `relationIdFromAllocation(namedInitialAllocation(sem, name))` and `relationRevisionId`). G0 no longer
  canonicalizes, sorts, refuses duplicates or hashes a world; `lib/wrl_world_spike.mjs` reproduces the historical
  `gsem-`/`grelpre-` only for the mapping test. The D-037 spike output is preserved byte-identical under
  `projections/*/world-spike/`; `world/identities.json` carries `supersedes.historical_spike_gsem`.
- **The measurement GPT v3 §5 said was not required — and which happened anyway.** The `sem-` hex equals the spike's
  `gsem-` hex at both pins: the spike (D-036) had mirrored WRL's canonicalization exactly (identity-first object order,
  seed-byte relation order, kernel-canonical revisions, `serializeArtifact` key order), and WRL-P0's static derivation
  adds nothing to the envelope (no `schemas`, `semantic_policies = {rulepack_id}`, `ports` from the role — which the spike
  had already stated). D-041 ruled the equality is *not required*; it did not forbid it. What matters is **who minted**:
  the `sem-` was computed by WRL from bytes WRL canonicalized and validated, and the test asserts the equality per pin as
  a measurement, never as a rule — the spike is not a seal, whatever its bytes. This is not a rename (D-017): the
  mapping is explicit and the two ids have different owners and preimage authorities. Every `grelpre-` differs from its
  kernel `rel-` (588/588, 566/566), because the allocation scope string differs (`gsem-` vs `sem-`).
- **Identity laws (D-043), measured on the baseline (`handoff/G0C_IDENTITY_MATRIX.md`, `tools/identity_matrix.mjs`):**
  none / shuffle → `sem-` stable, 0/588 `rev-`, 0/588 `rel-`; assertion-only edit → `sem-` stable, 0/0, but the
  projection root moves (recomputed); one relation attribute edit → `sem-` moves, 1/588 `rev-`, 588/588 `rel-`, lids
  stable; one node attribute edit → `sem-` moves, 0/588 `rev-`, 588/588 `rel-`. Refusals measured through WRL:
  transition→claim `SUPERSEDES` `WRL_UNDECLARED_ENDPOINT_PAIR`; undeclared kind `WRL_UNDECLARED_KIND`; unknown profile
  `WRL_UNSUPPORTED_PROFILE`; undeclared policy `WRL_UNDECLARED_POLICY`; stated `schemas`/`ports` `WRL_V2_WORLD_MISMATCH`;
  duplicate seed `WRL_DUPLICATE_RELATION_SEED`; dangling terminal `WRL_UNKNOWN_ENDPOINT`; undeclared role
  `WRL_UNDECLARED_ROLE`; duplicate object `WRL_DUPLICATE_ID`. Every measured (kind, source role, target role) triple at
  both pins is covered by the WRL row's pairs; the WRL row and the submitted declaration agree on all 8 facets.
- **Status of the identities.** `SEALED` by WRL-P0; **FROZEN only when GPT accepts this round** (D-042). Projection and
  evaluation roots are unchanged by the seal (the world is outside both).
- **Open.** Whether GPT wants `identities.json` to keep the spike mapping once the round is accepted, or retire it to
  `world-spike/` alone; and whether the measured equality should be promoted to a stated property of the profile
  ("a conforming submitter's bytes are WRL's bytes") or left as a per-pin measurement.

## GPT Adjudication v4 (2026-09-03, input `GRAPHONOMOUS_G0C_WRLP0_FOR_GPT.md` + `graphonomous-g0c-wrlp0-v1.zip`, sha256 `8d2d20e5…`) — rulings recorded as D-049 … D-054

GPT independently verified the 19,889-entry `SHA256SUMS` and re-ran the self-contained suites from the ZIP: **67 tests,
67 pass** (the repository-backed projection tests and WRL's 900-check suite accepted as receipt evidence). State after
v4: G-PR0 FROZEN · G0-A/B.1/E TESTED · WRL-P0 ACCEPTED/TESTED · **G0-C FROZEN** · **`graphonomous.semantic.v0` FROZEN
CONTRACT** · D-048 equality MEASURED/NON-NORMATIVE · WRL-P0.1 spec text OPEN/NON-BLOCKING · `graphonomous.evidence.v0`
DEFERRED until post-G0-F evidence · G0-D AUTHORIZED NEXT · G0-F AUTHORIZED AFTER G0-D · G0.5/UI not this round.

## D-049 — G0-C FROZEN: the golden worlds, their pins, and the frozen identity interpretation (2026-09-03, GPT v4 §1–§3)

- **D-037 accepted, TESTED, FROZEN modeling decision.** `EVIDENCE_STATE_TRANSITION --STATE_TRANSITION_OF--> CLAIM`;
  transition→claim `SUPERSEDES` rejected; `SUPERSEDES` never inferred from chronology; `current` unmodified. The
  post-D-037 projection/evaluation roots (`root-da4f3d7a…` / `root-c7f9c759…`; `root-c5d650b0…` / `root-edcd9f6f…`) are
  the accepted G0-B.1/G0-E receipts for the two source snapshots.
- **WRL-P0 accepted** as the first Graphonomous-driven owning-layer repair; WRL local commit
  `b072db0a983a33108b9a0c4429b978cb07e54148` is **the WRL pin for frozen G0-C v0**. This freezes the behaviour
  `graphonomous.semantic.v0` needs and the cited non-regression vectors — not all future WRL profile design.
- **Final G0-C accepted, TESTED, identities FROZEN** under profile `graphonomous.semantic.v0`, WRL `b072db0`, source pins
  `invariant-r10@ba4e625` (baseline) / `@699fbc2` (historical) + `computedriven@efa8881`, `super@7651697`,
  `TRVM@fd0df4c`, factory ref `d217ee2`. **Golden worlds:** baseline
  `sem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be`, historical
  `sem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23`; the exact `rev-`/`rel-` sets in
  `projections/{baseline,historical}/world/identities.json` at Graphonomous commit `0da094a` are the golden G0-C vectors.
- **Frozen identity interpretation.** (1) Graphonomous statement lid = cross-world proposition identity; (2) WRL `rev-`
  = relation revision/content identity; (3) WRL `rel-` = allocation identity under one exact `sem-`; (4) the projection
  root includes assertions/provenance; (5) `graphonomous.semantic.v0` deliberately excludes assertion/provenance
  occurrence from semantic-world identity; (6) the G0-E evaluation root is separately bound to the projection root. The
  measured identity matrix (`G0C_IDENTITY_MATRIX.md`) is accepted as the law's evidence.

## D-050 — `graphonomous.semantic.v0` is a FROZEN CONTRACT; changes go to `graphonomous.semantic.v1` (2026-09-03, GPT v4 §3)

- No role, relation kind, endpoint pair, identity-affecting default, policy vocabulary or canonicalization semantics may
  be added under the same profile id. If G0-F (or any application requirement) cannot be represented by the frozen v0
  declaration: **stop**, keep the projection/evaluation/certificate evidence, and propose `graphonomous.semantic.v1`
  with the smallest new obligation and a migration/non-regression analysis proving every v0 golden identity still
  reproduces — or prove the change is non-semantic and non-contractual. New datasets may produce new `sem-/rel-/rev-`
  values while conforming to v0. Guard: `test/wrl_world.test.mjs` reconciles the submitted declaration against WRL's
  row facet-for-facet; the WRL row at `b072db0` is the contract's bytes.

## D-051 — D-048 ruled: the `sem`/`gsem` hex equality stays a per-pin MEASUREMENT, non-normative (2026-09-03, GPT v4 §4)

- Not a profile property; no future submitter must reproduce WRL's canonical bytes ahead of WRL; future compatibility
  must not depend on it. Authority remains normative: historical `gsem-` = Graphonomous spike receipt; `sem-` =
  WRL-validated, WRL-minted. **Keep the mapping** in `identities.json` / `world-spike/` as migration evidence that no
  rename was smuggled in, marked historical/provisional/**non-normative** and ignored by the live sealing/allocation
  path. No `grelpre-` value becomes or aliases a kernel `rel-`.

## D-052 — WRL-P0.1 Spec Closure is real documentation debt, non-blocking; `OBJECT_ID_RE` duplication stays (2026-09-03, GPT v4 §5)

- WRL code is ahead of numbered spec text for static profiles. A small WRL-owned documentation/spec item should state,
  with stable rule/capability references: profile selection by `profile_id`; `lowered` vs `static` derivation; the static
  declaration surface; policy-vocabulary validation; that a static seal is no runtime/downgrade claim; the endpoint
  role/kind constraints admitted static profiles use. Filed as `STACK_GAP_REGISTER.md` row GAP-W14 (WRL-P0.1); never mixed
  with Graphonomous semantic code; does not block G0-D/G0-F. The kernel is **not** modified to export its private regex;
  the profile adapter's restatement stays pinned by conformance/round-trip tests until WRL changes the core grammar or a
  second consumer shows real drift risk.

## D-053 — `graphonomous.evidence.v0` DEFERRED until after G0-F (2026-09-03, GPT v4 §6)

- The three-surface separation (projection root = complete evidence/provenance; G0-E root = derived understanding;
  `sem-` = semantic statement world) is working. An evidence WRL profile is reconsidered only after G0-F, from measured
  needs of at least two authoritative source families; G0-F returns a measurement note and a recommendation, not code
  (which provenance/assertion concepts are shared vs source-specific; whether any query/identity/certificate need cannot
  be met by root + world separation). If no concrete requirement emerges, provenance stays in the projection/CAS layer.

## D-054 — Next order: G0-D projection certificate, then G0-F factory ledger; what the certificate may mean; GAP-T9 discipline (2026-09-03, GPT v4 §7–§9)

- **G0-D `GRAPHONOMOUS-PROJECTION-v0`** certifies **reconstruction identity, not truth**: *under these pinned source
  identities, ingestion contracts, canonical-byte rules and manifest, this projection reconstructs to this exact root
  and the protocol checker verifies the required identity/chain relations.* It must not mean any claim is true, evidence
  is sufficient, a state is promoted, Graphonomous may write a registry, or a G0-E derived fact is a TRVM derivation.
  Required: versioned protocol id; content-bound certificate identity; binds the exact projection root, the
  source/snapshot identity set (or a commitment to it), the ingestion/rule/schema identities needed to reconstruct;
  moves on any bound semantic input, holds on unbound prose; old certificates stay independently checkable after a
  later snapshot; explicitly **not a warrant**; no authority follows from possession. Field mapping is derived from the
  real `certificate.mjs` / `nest_check.mjs` API, never from the old pre-spec.
- **GAP-T9 discipline.** First try TRVM's existing certificate extension/checking mechanisms. If TRVM can mint but
  cannot generically check/register the child protocol except by a Graphonomous-local checker, reduce that to a minimal
  reproducer and classify it; only then a focused owning-layer round **`TRVM-P0 — Checked Child Protocol Registration`**
  (failing-first; generic/versioned registration or dispatch; no `if (protocol === "GRAPHONOMOUS…")`; all existing
  certificate/nest-check vectors unchanged; Graphonomous checker and TRVM checker agree on the same positive/refusal
  vectors; no derivation-language/`prim` work; receipt + separate local TRVM commit, not pushed). GAP-T9 is certificate
  authority, not graph rule execution — never conflated with the `prim` basis.
- **G0-F** after G0-D: the pinned factory canonical ref (`d217ee2`, exact commit resolved before ingestion) as an
  independent authoritative source; tests the `inv` namespace against a second producer, qualified/unqualified id
  collision rules, whether equivalent claims converge on one statement + multiple assertions or stay distinct with
  explicit relations (text equality is never identity); preserves source authority; measures new fault types rather
  than normalizing them away; proves certificate sensitivity (new source commitment → new snapshot commitment; semantic
  additions move root and certificate; the pre-G0-F certificate still verifies against its frozen snapshot;
  reordering/dropping a source cannot alias a certificate); seals under frozen v0 or stops with a v1 proposal (D-050).
- Not this round: UI/G0.5, broad G1, `graphonomous.evidence.v0`, the TRVM primitive-basis round.

## D-055 — GAP-T9 classified from a reproducer: the gap is real; `TRVM-P0 — Checked Child Protocol Registration` is executed as design (a′) (2026-09-03, R13, D-054 discipline)

- **Reproducer** (`research/probes/g0d/probe_g0d_nest_child.mjs`, TRVM `fd0df4c`, read-only): `verifiedClaimSemId` mints
  for `GRAPHONOMOUS-PROJECTION-v0` (`vclaim-c278d3b2…`, preimage re-derived by hand, equal); every judge-side path is
  closed — `IMPLEMENTED_CHILD_PROTOCOLS` is frozen (`nest_check.mjs:151-159`; assignment → `TypeError`), an opts
  registry is refused `nest-policy-weakened` (`effectivePolicy :129-133`), the producer throws
  `nest-bundle-unknown-child-protocol` (`nest_bundle.mjs:220`), and `checkNestBundle` returns
  `nest-child-protocol-unsupported` plus five consequential codes with `checker_evaluations = 0`; `compose_check`
  refuses identically. **Class: INTEROP_GAP confirmed** — TRVM can mint but cannot check or register a child protocol
  except by the hard-coded table.
- **Why the table is hard-coded, honoured.** `round-11-ledger.md:3601-3604`: the artifact must never name its own claim
  field or checker (P1.1/P2.1/P3 lineage); `spec_agreement.mjs:91-97` pins the table against the normative schema. The
  rule protected is *a VERIFIER names the checker set*, so a caller-supplied registry is lawful when the caller is the
  verifier, built-ins cannot be overridden, and the verdict names which checker set produced it.
- **Design (a′) chosen.** `checkNestBundle(bundle, {store, child_protocols})` / `checkNestBytes(raw, {store,
  child_protocols})`: `child_protocols` destructured beside `store` so it never reaches `effectivePolicy`; each entry
  `{claim_field, check, composed:false, checker_id}` validated (`nest-child-protocol-malformed`); a key already in
  `IMPLEMENTED_CHILD_PROTOCOLS` refused (`nest-child-protocol-override-refused`); `composed:true` refused; the effective
  table built inside `checkOwned` and used at the dispatch; `measured.child_protocol_set` reported and a
  `child_protocol_set_id` folded into the reported verifier policy id **only when a set is supplied**, so every existing
  verdict, vector and id is byte-identical. The producer `buildNestBundle` accepts the same supplied table so an
  agreement vector can be built. Rejected: (b) module-level `registerChildProtocol` (global mutable authority channel;
  a second registrant collides), (c) a CAS descriptor (the CAS holds JSON, never a checker; letting the citation supply
  the claim field is the P3 defect — acceptable only as the `checker_id` identity).
- **Batteries that must stay green:** `gov-nest`, `gov-proof`, `gov-spec`, `gov-negative`, `gov-harness`, `gov-grid`
  (Makefile); `nest_bundle`/`proof_bundle`/`domain_bundle` write into the tree (deterministic — a re-run must leave
  `git status` clean); no new governance file (`artifacts.json`/`grid_check` refuse an undeclared one); no ledger or
  grid edits by this lane; separate local TRVM commit, not pushed; receipt in `STACK_FIX_RECEIPTS/`.
- **G0-D protocol** follows R13 §6: claim = projection root + order-independent, dropped-source-sensitive
  `snapshot_commitment` (measured: reorder HOLDS, drop MOVES, duplicate refused — needed because the manifest binds only
  the snapshot *label* and the stored snapshot hash is order-dependent) + ruleset + schema set + adapter contract + spec
  + checker-owned `scope` (D-054's "must not mean" list as refusable values); `chain_ids` = the TRVM pin + projector/
  checker ids; `aggregate_id` = manifest facts; certificate = `verifiedClaimSemId`. **Projection and evaluation roots
  must not move** (D-049): the snapshot identity record enters the CAS as an artifact beside the manifest, never as a
  manifest entry.

## D-056 — G0-F scope decided from the factory-ledger census (2026-09-03, R12 at `d217ee2`, read-only)

- **Pin.** `d217ee29a3322c68db0d43be47491f0e9d4fbc64` = `refs/heads/invariant-canonical` = tag `INV-R9.4`; tree `11ab2c61…`;
  `CLAIM_LEDGER.json` blob `23141cd1…` (458,585 B); 10 mosaic blobs, 20 receipts; `cells.json` is in the same tree,
  byte-identical to the site repo. Read only via `git show`.
- **What the census measured.** 208 claims, 0 duplicate ids, 0 statuses outside `_statuses`, 84 settled; witnesses
  269/269 resolve and all 137 `§n` anchors exist; `cell:NN` 54/54 and `assumption_refs` 46/46 resolve; `assumptions[]`
  is 110 free-text items; `supersedes`/`superseded_by` agree on 8 pairs, one-sided on 6; dangles: 2 `prior_art`
  `SRC-MUTATION-ADEQUACY`, 8 prose `supersedes`.
- **Cross-source identity (the point of G0-F).** The registries meet only at the 4 ids the crosswalk already cites
  (EMB-AUTH-NONAMP qualified; EMB-CUT-EMPTY, TAX-RELATIONAL-2, TAX-FLOW bare — D-031); the factory tree mentions the
  E-world **zero** times (re-verified). Text near-duplicates: 0 exact, 0 at Jaccard ≥ 0.5; three name-level
  coincidences (E-40's `name` *is* the token `EMB-CUT-EMPTY`; E-41 paraphrases TAX-RELATIONAL-2) **stay distinct nodes**
  — text equality is not identity. Collisions that the lid namespaces keep apart: `S4` (crosswalk safety obligation vs a
  factory exhaustive-search-space label), `F1/F4/F5` (R0.8 findings vs "Fable R5.2" review findings), intra-factory
  `INC-` (3 claims vs 46 incidents). **No same-proposition (kind, source, target) case exists across the registries at
  this pin**; what folds is node-level (the 4 `claim:factory:*` stubs gain a second assertion; `cell:cells:27a`; one
  `loc:factory:` object). The factory's `obligation` vocabulary (9 logical shapes) is a different axis from S1..S6 and
  is never merged (Q-10). The one real two-assertion *relation* case is intra-factory: 8 `SUPERSEDES` pairs stated by
  both `supersedes` and `superseded_by` — one relation, two assertions (D-029).
- **v0 fit (D-050 guard).** The core ledger seals under frozen v0: REGISTRY/CLAIM/MEMBER_OF, WITNESS→WITNESSES→CLAIM (+
  LOCATED_IN), ASSUMES, BINDS→CELL, CLAIM→SUPERSEDES→CLAIM, CITES→ARTIFACT (`artifact:factory:SRC-*` — the contract's
  `cite:` prefix does not exist in the lid grammar), ROUND/RECEIPT with PRODUCED_BY. **Does not fit v0:** arguments
  (`SUPPORTS` has no `[CLAIM, CLAIM]` pair), 62 of 68 defeaters (`ATTACKS` reaches only CLAIM/MECHANISM), instruments,
  objectives, occupancy, operations, embodiment (no role), `ASSUMPTION → CLAIM` discharge refs (no kind).
- **Decision.** G0-F ingests the v0-safe core — (1) REGISTRY + 208 CLAIM (full attrs, `evidence_state {token,
  vocabulary: factory-ledger}`) + MEMBER_OF; (2) WITNESS nodes/edges with `outcome` from status + LOCATED_IN at the
  pinned blob with `§n` anchors; (3) ASSUMES — typed `ASM-*` ids to `assumption:factory:*`, free text under the existing
  `text` namespace (so a sentence shared with the crosswalk co-refers by D-030, never by a per-registry prefix); (4) BINDS
  → `cell:cells:NN`; (5) SUPERSEDES from both fields (one relation, two assertions); (6) CITES → `artifact:factory:SRC-*`;
  (7) ROUND/RECEIPT from the 20 receipts with PRODUCED_BY and `invariants.established` → CLAIM PRODUCED_BY ROUND. The 4
  crosswalk stubs must fold without CONTRADICTION (the adapter emits the same attr values for `claim_id`,
  `registry_hint`, `present_in_pinned_ledger`, or omits them). **Deferred to a v1 proposal, recorded as measurement:**
  arguments, defeaters (the 6 claim-targeted ones may enter as FALSIFIER→ATTACKS), incidents-as-FINDING, instruments,
  objectives, occupancy, operations, embodiment, `retyped` transitions (prose), `mosaic/derived/`. Faults expected:
  `SETTLED_WITHOUT_WITNESS` 8 (new; a fact about the source, legal by the factory's own gate), `UNRESOLVED_LINK` ~11,
  `STATUS_OUTSIDE_VOCABULARY` 0 (new), `DANGLING_CELL_BINDING` 0, `DANGLING_WITNESS` 0; `implementation_binding` stays
  an attribute (81 `UNSUPPORTED_SOURCE_FORM` avoided by not inventing locations from prose).
- **Consequence for the profile.** The core ledger sealing under v0 is itself the D-050 test passing for the second
  source; the argument/defeater layer is the first measured **v1 obligation** (`SUPPORTS [CLAIM, CLAIM]` or an
  ARGUMENT role; `ATTACKS` to ASSUMPTION/WITNESS/RECEIPT) — proposed, not built, in this round's handoff.

## D-057 — TRVM-P0 as built: a verifier-supplied `child_protocols` registry; two deviations recorded (2026-09-03; TRVM `fd0df4c` → `9e91c96`, receipt `STACK_FIX_RECEIPTS/TRVM-P0.md`)

- **Decision (TRVM-owned, recorded for the lane).** Design (a′) of D-055 as specified: `child_protocols` beside `store`
  in `checkNestBundle`/`checkNestBytes`/`buildNestBundle`; exact-shape entries; built-ins unoverridable; composition
  stays the checker's; the effective set named in the measured record and folded into the reported policy id only when
  supplied; `compose_check.mjs` left unchanged (superseded carriage model, not symmetric). Failing-first (6/7 new
  vectors fail at `fd0df4c`); after: NEST-FORGERIES 43/43, SPEC-AGREEMENT 28 codes unchanged, all six batteries green
  incl. gov-negative 392/392; every regenerated bundle and the `cas/` listing byte-identical; the R13 reproducer prints
  a byte-identical refusal set without a table.
- **Deviation 1 (honest stand-in).** New refusal codes cannot be minted without a normative schema revision
  (`spec_agreement.mjs` pins the emitted code set to `nested-composition-v2.json`, digested by the release), so the
  malformed-entry and override refusals ride under `nest-policy-weakened` with distinguishing detail, asserted by code
  AND detail. R13 §4's prediction that `spec_agreement` was unaffected missed this gate. Filed as GAP-T14 / TRVM-P0.1
  (spec revision, TRVM-owned, non-blocking) — the same shape as WRL-P0.1.
- **Deviation 2 (the tree's own remedy).** `blind-run.json` pins a package digest over the nest files; the ruled
  remedy was `--abort` with the TRVM-P0 reason then `--pin` (deterministic, no holdout scoring implied): superseded
  `brun-c39b708f…` → ABORTED `brun-740403c7…` → PINNED `brun-74f54466…`; the superseded id is recorded in the receipt
  because the TRVM ledger is outside this lane.
- **Consequence for G0-D.** The TRVM pin moves to `9e91c96` (the five Graphonomous-pinned blobs are unchanged; the
  commit is in `chain_ids`), so every G0-D certificate is re-minted and the golden vectors are recorded at the new pin;
  the TRVM agreement test runs against the committed checker. GAP-T9 **CLOSED**.

## D-058 — G0-F as built: the factory ledger is the second authoritative source; the core seals under frozen v0; certificates re-minted at the TRVM-P0 pin (2026-09-03)

- **Pin.** Factory `d217ee29a3322c68db0d43be47491f0e9d4fbc64` (= `refs/heads/invariant-canonical` = tag `INV-R9.4`), tree
  `11ab2c61…`, `CLAIM_LEDGER.json` blob `23141cd1…`; read only through the bare repository. `adapters/factory.mjs`
  implements D-056 (1)–(7) and nothing more; the contract's measured deviations are appended to
  `INGESTION_CONTRACTS/factory-ledger.md` (registry lid `registry:factory:factory-ledger@INV-R9.4`; unsettled witness
  `outcome = {unknown: "not-stated"}`; every `_settled` status → `pass`; no `ROUND SUPERSEDES ROUND` — the receipt
  parent chain is lineage, not replacement; inverse statements `cited_by`/`used_by` enter as second assertions;
  `mosaic/evidence.json` not read).
- **Multi snapshot** `snapshot:g0:multi-ba4e625-d217ee2` (`snapshots/multi.json`, `params.adapters: [crosswalk,
  factory]`, 6 sources / 101 files — the factory source widened from 3 to 66 files), commitment
  `gsnap-2e5252881fc3192a912d95b0b8ccf010be619ece8cb9a3dc6ccb0ddfd35a944e`. Projection root
  **`root-48ac3e32dfc56cd1450e43b92c7a38d83d71a95113da8b243951dfa305fd2213`** — 7,639 manifest entries (node 778, relation
  1,574, assertion 3,270, loc 1,929, fault 86, run 2); `g0 verify` 7,639/7,639, Python twin equal; four-order A8 holds
  (a latent defect found and fixed on the way: `order_index` recorded the *run* order, so reversing two adapters moved
  the root — it is now the declared position; single-adapter roots unaffected, the frozen roots reproduce). Evaluation
  root `root-472a5d32b783051536703b4149838bd38d395a7d91c0b6e6e3af91f5592a912f` (1,011 facts; checker 1,016/0).
  Faults: UNRESOLVED_LINK 56 (42 baseline + 14 factory), UNSUPPORTED_SOURCE_FORM 11, **SETTLED_WITHOUT_WITNESS 8** (new;
  a fact about the source, legal by its own gate), TRUNCATED_FIELD 5, UNQUALIFIED_REFERENCE 3, DANGLING_WITNESS 2,
  AMBIGUOUS_IDENTIFIER 1; STATUS_OUTSIDE_VOCABULARY 0, DANGLING_CELL_BINDING 0, CONTRADICTION 0.
- **Cross-source identity, measured** (`test/factory.test.mjs`): the 4 crosswalk-cited factory ids are ONE node each
  with assertions from both registries and 0 CONTRADICTION; the folded nodes are exactly `cell:cells:27a` + those 4
  claims; only `obligation:inv:S4` exists — no `claim:factory:S4`/F1/F4/F5 node or edge; E-40 / EMB-CUT-EMPTY and E-41 /
  TAX-RELATIONAL-2 stay two nodes joined only by the crosswalk's CITES; **0 relations carry assertions from both
  registries** (the census prediction held); the two-assertion mechanism is exercised intra-factory (SUPERSEDES 8/14,
  typed ASSUMES 45/52, SRC CITES 20/45); 105 `assumption:text:*` (97 factory, 8 crosswalk), **0 shared verbatim**.
- **Frozen-profile guard (D-050) passed:** the multi semantic world seals under v0 unchanged —
  **`sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea`**, 2,707 objects / 1,574 relations / 2,721,943
  canonical bytes, kernel `rel-` 1,574/1,574, `rev-` 1,574/1,574; the v0 golden worlds are untouched.
- **Certificate sensitivity, measured** (`test/factory_certificate.test.mjs`): the multi commitment ≠ baseline's; multi
  root and certificate ≠ baseline's; dropping the factory source — or narrowing it back to the baseline's 3 files —
  refuses `gproj-snapshot-commitment-mismatch` (a source's file set is part of its identity); reordering sources and
  file lists gives the same commitment and the SAME certificate.
- **Re-mints, recorded for traceability.** Adding the second adapter moved the projector code id and two fault codes
  moved the schema set, so the fd0df4c-era G0-D certificates (`vclaim-897ec409…` baseline, `vclaim-a6ba3b33…`
  historical; D-055-era vectors) were superseded twice within this round: first at fd0df4c + G0-F code
  (`vclaim-5252b9c4…` / `vclaim-29fbcc64…` / multi `vclaim-d9f0eaf9…`), then by the TRVM-P0 re-pin (`TRVM_PIN.commit`
  `fd0df4c` → `9e91c96`, the five pinned blobs unchanged) to the **final vectors: baseline
  `vclaim-c90547a6de6d46e5a79750ca897a58f3f4305971c300c567cab712436b7bd851`, historical
  `vclaim-bf81cc6d8deaa393638f0d13028cf4a6c9f737b7bf4a7c7869bd651fa880e0cf`, multi
  `vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2`** (`G0D_GOLDEN_VECTORS.md`). Root,
  snapshot commitment, adapter contract and aggregate of baseline/historical never moved.
- **The old certificate still verifies — under the checker that minted it.** Measured by the main session: the
  pre-G0-F baseline bundle (`vclaim-897ec409…`, preserved under `projections/pre-g0f/`) checked with the Graphonomous
  code at commit `14f77e0` against the unchanged baseline directory → **VERIFIED**; the same bundle under the current
  checker → REFUSED on exactly `gproj-certificate-stale + gproj-chain-id-mismatch + gproj-schema-set-mismatch`, never on
  root, snapshot, adapter contract or aggregate (tested). This is the TRVM `chainIds()` discipline: chain ids are
  relations to the live checker, so a certificate names *under which code* it was reconstructed, and a newer checker
  says precisely which coordinate moved.

## D-059 — After G0-F: `graphonomous.semantic.v1` is PROPOSED, `graphonomous.evidence.v0` is NOT justified yet (2026-09-03)

- **v1 obligation (`handoff/G0F_V1_OBLIGATION.md`, proposal only, D-050).** The factory's argument / defeater /
  incident layer and five registries have no v0 home. Smallest new obligation measured at `d217ee2`: **two roles
  (`ARGUMENT`, `DEFEATER`), one kind (`DISCHARGED_BY`), nine endpoint pairs**. v1 is a new profile id, so every v0 golden
  identity (`sem-0f952f03…`, `sem-3ae051cf…`, `sem-b8d82827…`) is unchanged by construction; nothing is built.
- **Evidence profile (`handoff/G0F_EVIDENCE_PROFILE_NOTE.md`): NOT YET.** Across two source families every requirement
  of this round — cross-source co-reference, snapshot-relative provenance, exact source locations, the certificate's
  source-set commitment — was met by assertion records + projection root + semantic-world separation; no consumer of a
  provenance *identity* exists. Shared provenance concepts (assertion shape, pinned locations, executed flags, raw
  status/outcome vocabularies) and source-specific ones are listed for the next source family to test against.
- **Next after acceptance.** Unchanged from D-046/D-054: no UI/G0.5, no broad G1, no evidence.v0, no primitive-basis
  round in this lane without a ruling.

## D-060 — GPT Adjudication v5 recorded: G0-D and G0-F are TESTED, `GRAPHONOMOUS-PROJECTION-v0` semantics are FROZEN, and three certificates + the multi v0 world are golden vectors (2026-09-03, GPT v5 §0–§3, §6)

- **Independent verification.** GPT verified the submitted ZIP (`80c4af99…`) against its internal `SHA256SUMS`:
  **28,630 entries, 0 missing, 0 mismatches**, and reran the self-contained suites file-by-file from the ZIP —
  **101 pass / 0 fail / 3 skip**, the skips being the cases that need the real pinned repositories rather than the
  verification copies. The full-tree receipts (Graphonomous 121/0/1, WRL 900/900, TRVM batteries green) are accepted as
  **submitted receipt evidence**, explicitly not claimed as independently rerun. Freeze commit `b61ff2e` is accepted as
  a historical checkpoint; D-049…D-054 are accepted as a correct record of GPT v4.
- **`GRAPHONOMOUS-PROJECTION-v0` — protocol semantics FROZEN.** The frozen meaning is: *under the certificate's exact
  pinned source/snapshot commitment and bound Graphonomous reconstruction protocol coordinates, the verifier
  reconstructs the exact projection root and structural aggregate claimed by the certificate.* It does **not** certify
  truth of the graph's claims, evidence sufficiency, promotion of evidence state, authority to mutate any registry,
  TRVM derivation of G0-E facts, or the correctness of an LLM adjudication. The checker-owned `scope` fields
  (`truth_claimed:false`, `evidence_sufficiency_claimed:false`, `state_promoted:false`, `registry_written:false`,
  `trvm_derivation:false`) are accepted as the mechanism that makes that list refusable. **A change to this meaning
  requires a new protocol version, never a silent edit.**
- **Golden certificate vectors, at the exact certificate/verifier coordinates recorded in the bundle** (TRVM
  `9e91c96`): baseline `vclaim-c90547a6de6d46e5a79750ca897a58f3f4305971c300c567cab712436b7bd851`, historical
  `vclaim-bf81cc6d8deaa393638f0d13028cf4a6c9f737b7bf4a7c7869bd651fa880e0cf`, multi
  `vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2`. The corresponding `gclaim-`, `gsnap-`,
  projection roots, aggregate identities and chain identities are **part of each vector** and must remain reproducible.
- **G0-F multi v0 world is golden**: snapshot `snapshot:g0:multi-ba4e625-d217ee2`, projection root
  `root-48ac3e32dfc56cd1450e43b92c7a38d83d71a95113da8b243951dfa305fd2213`, certificate `vclaim-cf3b2570…`, WRL world
  `sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea`, **and the exact shipped v0 `rel-`/`rev-` set
  for the multi world**. Factory pin `d217ee29a3322c68db0d43be47491f0e9d4fbc64` is accepted for this vector. The
  baseline/historical v0 worlds remain unchanged.
- **Vocabulary rule, now binding.** Of a historical code-bound certificate, write **"verifies under its pinned verifier
  coordinates"** — never the unqualified "still verifies". D-058's re-mint semantics are accepted as stated: an old
  certificate remains valid evidence of the reconstruction performed under the coordinates that minted it; a newer
  checker may refuse it when chain/schema/checker coordinates moved; that refusal does **not** make the old projection
  root, source commitment or aggregate retroactively false; re-minting creates a **new** certificate, never a mutation,
  renewal or rename; old and new receipts coexist. **Never make the current checker accept historical certificates by
  ignoring chain ids.** An archival verifier-resolver that locates the pinned checker by chain id is permitted but is
  not to be built without a concrete consumer.

## D-061 — TRVM-P0 accepted; TRVM-P0.1 is required owning-layer closure (2026-09-03, GPT v5 §4–§5)

- **TRVM-P0 ACCEPTED** at `9e91c96f2d50f3c3bd143fc94ec4267a6b03195a` as the second Graphonomous-driven owning-layer
  stack repair. The design is accepted **because the extension point belongs to the verifier, not the child artifact**:
  artifacts cannot name or inject executable checker code, built-ins cannot be overridden, supplied child checkers are
  explicit verifier configuration, the effective checker set is measured, `child_protocol_set_id` contributes to the
  verifier-policy identity, and absent the extension table the prior behaviour and vectors are byte-identical.
- **Critical interpretation, to be kept explicit in docs and tests.** A supplied checker returning `VERIFIED` does not
  create universal TRVM truth; the result is scoped to the exact `verifier_policy_id`, `child_protocol_set_id`, checker
  id and certificate chain. Downstream code must never consume the bare token `VERIFIED` while discarding the
  verifier-policy coordinate. The general rule: **verification without verifier identity is incomplete evidence.**
- **Deviation 1 — overloaded `nest-policy-weakened`: accepted for P0, REQUIRED follow-up.** Refusal did occur and the
  tests assert both code and distinguishing detail, so no false verification is possible from the naming debt — but this
  is real normative spec debt, not optional cleanup. **TRVM-P0.1 must add dedicated refusal semantics** distinguishing
  at minimum (a) malformed child-protocol registration and (b) attempted built-in child-protocol override, through the
  proper normative schema/release revision. **Do not merely loosen `spec_agreement`.** All old valid vectors and all old
  refusal meanings must remain stable.
- **Deviation 2 — blind-run re-pin: accepted, ledger closure required.** The re-pin followed TRVM's own abort/pin
  mechanism and the superseded/aborted/new ids are preserved in the stack-fix receipt, which suffices for accepting
  TRVM-P0. The next TRVM-owner pass must also record the supersession in whatever **authoritative TRVM ledger** the
  blind-run protocol requires — superseded `brun-c39b708f1d96f2b6df1562d66c33c3eee3d13e2307274e42adbff79025b13ad8`,
  aborted `brun-740403c7…`, current pinned
  `brun-74f54466247c3ccbfcf15ada42242605c7a299961a8b7413e1c914f18fe8c264`. If TRVM has no authoritative place for it,
  **do not invent a ledger** — document precisely why the existing receipt is canonical enough. This closes GAP-T14.

## D-062 — `graphonomous.semantic.v1` is OPEN NOW; the 2-role/1-kind/9-pair surface is a CANDIDATE pending a target-completeness audit (2026-09-03, GPT v5 §7)

- **OPEN IT NOW. Do not wait for a third source family.** This is exactly the condition the frozen-v0 guard was designed
  to expose. G0-F measured authoritative factory structures that could not be represented under v0 and were
  **intentionally omitted rather than forced**: 27 ARGUMENT records, 68 DEFEATER records, argument
  premise/evidence/assumption structure, defeaters targeting claims / arguments / assumptions / witnesses / receipts and
  consumption-rule/code targets, assumption discharge relations, incident semantics, and additional instrument/process
  vocabularies. **The fact that the v0-safe subset seals successfully does not prove v0 is semantically sufficient** —
  it proves the adapter respected the frozen contract.
- **Accepted now as design direction** (use unless the census finds a direct contradiction): `ARGUMENT` is a **distinct
  role**, not a CLAIM sub-kind — it has premises/conclusion/evidence and is not merely another asserted claim, and the
  alternative would need `SUPPORTS [CLAIM, CLAIM]`, changing what every existing CLAIM→CLAIM edge could mean.
  `DEFEATER` is a **distinct role**, not a FALSIFIER synonym — a v0 FALSIFIER is an executable construction that
  falsifies claim/law semantics, while defeaters frequently attack things other than claims. `DISCHARGED_BY` is a
  **distinct relation kind** for the measured assumption→claim relation, because overloading `SUPPORTS` in the opposite
  direction weakens its existing meaning more than a specific discharge kind does.
- **Do NOT freeze the submitted "2 roles / 1 kind / 9 pairs" surface yet.** Before v1 is frozen, run a **v1
  target-completeness audit** over the refused factory layer — especially the 34 `consumption_rule` defeater targets,
  the argument-target dictionaries carrying file/revision/digest/section/symbol, and the exact semantic status of
  incident FINDING records. **Every authoritative refused structure must receive exactly one explicit disposition:**
  (1) REPRESENTED in v1; (2) DEFERRED because no current semantic consumer requires it, with raw/source evidence
  preserved; (3) SOURCE-REPAIR because the source form cannot support a semantic identity honestly; (4) OUT-OF-SCOPE
  process metadata, with a stated reason.
- **Prohibited shortcuts.** Do not invent a `CONSUMPTION_RULE` role, do not abuse `SOURCE_LOCATION`, and do not widen
  `MECHANISM` merely to make the counts fit. If the source supplies only code coordinates, the honest v1 may preserve
  the target as source-addressed evidence while **deferring a semantic ATTACKS endpoint**. If the audit shows a tenth
  endpoint pair or another role is the smallest honest representation, **change the v1 proposal before freezing it**.
  Incident FINDINGs must not be merged with crosswalk FINDINGs by textual similarity; if `finding_source` is merely
  provenance, keep it out of semantic identity unless a query demonstrates otherwise.
- **v0 non-regression is absolute.** Never edit `graphonomous.semantic.v0`. v1 must be a new WRL profile row/id. All v0
  baseline/historical/multi golden identities remain byte-identical. Statement LIDs shared by v0 and v1 remain
  cross-world semantic names.

## D-063 — `graphonomous.evidence.v0` stays NOT YET; G0.5 is a READ-ONLY UI, authorized after v1 (2026-09-03, GPT v5 §8–§10)

- **`graphonomous.evidence.v0`: KEEP `NOT YET`.** G0-F was the second-source measurement asked for and it still does not
  demonstrate a concrete requirement for provenance/assertion occurrence to participate in WRL world identity. The
  present four-way separation remains sufficient: projection root = complete observed evidence/provenance; G0-E root =
  derived understanding; WRL semantic world = statement/object semantics; G0-D certificate = reconstruction receipt over
  the projection. **Do not create an evidence WRL profile merely for symmetry.** Re-open only when a concrete consumer
  requires provenance relation allocation that must be world-addressable through WRL, evidence-world identity
  independent of the projection/CAS root, cross-world composition of assertion/provenance objects, or a
  query/authority/certificate operation impossible to state correctly under the current separation. **G0.5 does not
  automatically count** — it may display projection assertions directly.
- **Development order, authorized.** `record v5` → `TRVM-P0.1 spec/ledger closure` → `semantic.v1 target-completeness
  audit` → `semantic.v1 profile + factory argument/defeater ingestion` → rebuild projection/evaluation/certificate →
  seal v1 world through WRL → `G0.5 minimal read-only Graphonomous UI` → stop for GPT adjudication. TRVM-P0.1 and the v1
  pre-freeze research may run in parallel but remain **separate owning-layer work** with separate commits/receipts.
  **Do not start broad G1, autonomous mutation, evidence.v0, or the TRVM primitive-basis round in this round.**
- **G0.5 authority boundary — READ ONLY.** The UI may not promote or reject evidence, modify authoritative registries,
  mint claims, rewrite factory/crosswalk state, trigger stack repair autonomously, or label an advisory LLM answer as
  deterministic derivation. No LLM-generated explanation may replace the deterministic G0-E `explain` tree in the
  acceptance demo; an LLM summary may be layered later and labelled advisory. No write controls disguised as disabled
  future buttons unless clearly labelled nonfunctional. **Layout coordinates, open panels, filters and viewport state
  are non-semantic UI state and must not move projection or WRL identities.** The UI's implementation
  language/framework is host machinery and need not be WRL; the demo claim is that *the displayed semantic graph is
  derived from authoritative sources, deterministically projected, certified, and sealed as a real WRL world.*
- **Required G0.5 surfaces** (GPT v5 §10): snapshot/world selector (baseline v0, historical v0, multi v0, multi v1);
  semantic graph over statement LIDs; node inspector (role, semantic attrs, evidence state, source-family assertions,
  source locations); relation inspector separating statement LID / WRL `rev-` / world-scoped `rel-` / assertion
  occurrences; explain panel distinguishing `observed` vs `derived` and showing `trvm_derivation:false`;
  provenance/source-location drill-down; fault panel navigable to the affected record; A1–A7 executable; identity panel
  showing projection root, evaluation root, G0-D certificate/verifier coordinate and WRL `sem-` together; and, if v1 is
  built, ARGUMENT/DEFEATER exploration.
