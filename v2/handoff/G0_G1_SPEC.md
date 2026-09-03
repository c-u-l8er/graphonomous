# G0/G1 SPEC — Graphonomous as a derived semantic/evidence graph

**Status: FROZEN for G0 on 2026-09-02 (G-PR0), with the open items of §17 — none of which changes a contract below (item 1 was resolved the same day).**
Every choice cites the evidence that decided it: the source census (`research/R7A_*`, `R7B_*`), the two stack audits
(`research/R5_WRL_CAPABILITY_AUDIT.md`, `research/R6_TRVM_DERIVE_AUDIT.md`), the three research reports
(`research/R1`, `R2`, `R3`), the measurements in `TEST_FIXTURES/`, and the decisions in `DECISION_LOG.md`. A change
to a frozen section is a new decision entry that cites the section, never a silent edit.

> **Amendments by decision (2026-09-02, GPT Adjudication v1):** §13/§14 A6 naming → D-022 (`EXEC_RECEIPT_OBSERVED` ·
> `NO_EXEC_RECEIPT_OBSERVED` · `EXEC_RECEIPT_UNDECIDABLE_FROM_SOURCE`; the word *unsupported* is withdrawn); §14 pins →
> D-023 ("baseline / current-at-freeze", never moved to follow HEAD); §6.2 decimal-string encoding and §4.1 ASCII lids
> → D-026; §7.5 `gsem-`/`sem-` supersession → D-017; GAP-W9 → D-018; §3.2 relation kinds `DEFINES`, `REPRESENTS`, `CROSS_CUTS` → D-027. The section text below is left as frozen.
>
> **Amendments by decision (2026-09-03, GPT Adjudication v2, G0-B.1):** §4.3 relation identity — a relation is the
> proposition `(kind, source, target[, declared semantic qualifier])`, citation location never enters it, occurrence
> metadata lives on the assertion → D-029 (withdraws D-028 §1); unnamed findings → context-bound identity
> `hash(container ‖ NUL ‖ sentence)` → D-030 (amends D-028 §5); §12 fault vocabulary gains `UNQUALIFIED_REFERENCE` and
> bare identifiers follow resolve-when-unique-and-report → D-031; §13 / §10.2 rules become assertion-aware over
> `asrt/3`, `aattr/3` and the executed-receipt admissibility rule is stated → D-032; order G0-B.1 → G0-E → G0-C → D-033.
>
> **Amendments by decision (2026-09-03, GPT Adjudication v3, D-034 → WRL-P0 → G0-C):** §3.2 gains
> `STATE_TRANSITION_OF` (transition → claim) and `SUPERSEDES` is frozen as replacement between comparable entities only,
> never inferred from temporal order → D-037 (rules D-034 for option A); §7.2/§7.5 `rel-` is only ever WRL-minted under a
> WRL-sealed `sem-`, the spike's preimage ids are `grelpre-` provisional → D-038; §7 the profile is sealed by a WRL static
> profile mechanism (WRL-P0), final canonicalization belongs to WRL, three identities (projection root · evaluation root ·
> `sem-`) → D-039, D-041; §7.3 lid → `\w+` encoding accepted as a profile adapter → D-040; §7.5 profile shape candidate →
> D-042; statement lid / `rev-` / `rel-` law → D-043; §13 `has_exec_receipt(Subject)` is generic → D-044; checkpoint
> commits + execution order → D-045, D-046. The section text below is left as frozen.
>
> **Amendments by decision (2026-09-03, GPT Adjudication v4 — G0-C FROZEN):** §7 the two golden worlds, the WRL pin
> `b072db0` and the six-point identity interpretation are FROZEN → D-049; the profile `graphonomous.semantic.v0` is a
> frozen contract, changes go to `graphonomous.semantic.v1` → D-050; §7.5 the measured `sem`/`gsem` equality is
> non-normative → D-051; WRL-P0.1 spec text is WRL debt → D-052; `graphonomous.evidence.v0` deferred → D-053; §8.3 what
> the `GRAPHONOMOUS-PROJECTION-v0` certificate may mean (reconstruction identity, not truth; not a warrant) and the
> GAP-T9 / TRVM-P0 discipline, then G0-F → D-054. The section text below is left as frozen.

## 1. Purpose and boundary

Graphonomous G0 is a **deterministic, read-only projection** of what the ComputeDriven invariant program currently
claims to understand — its obligations, the claims and mechanisms that serve them, the witnesses and receipts that
support or falsify those claims, the profiles and assumptions that scope them, and the adjudications that moved their
evidence state — reconstructed from authoritative registries at pinned revisions **without losing identity,
provenance, scope, evidence state, or authority boundaries**.

- G0 writes nothing back to any registry. It emits a projection, faults, and (from G1) proposals.
- Authority stays with the owning registry. A fact in the projection is *attributed*, never *asserted by Graphonomous*.
- The projection is deletable and rebuilt byte-identically from the same input snapshot (§6.6, A8).
- Graphonomous is the S2 discipline applied to itself: observation and reasoning mint no authority (D-002).

## 2. Vocabulary

| Term | Meaning here |
|---|---|
| **source** | a file, git object or registry document at a pinned identity (git OID for tracked files, `sha256:` for loose files) |
| **snapshot** | the set of pinned source identities one ingestion run read; the projection is a pure function of it |
| **record** | one normalized unit an adapter produced from a source element; the atom of provenance |
| **node** | an entity in the projection (kind from §3.1), carrying one or more records |
| **relation** | a typed, directed edge (kind from §3.2) with its own identity, revision and provenance |
| **statement** | the proposition a relation states — `(kind, source lid, target lid)` — independent of who states it |
| **assertion** | one source stating a statement (or a node) with attributes; the unit that lets two sources state one relation with different evidence states (R1 §1: RDF 1.2's proposition/occurrence split) |
| **basis** | `observed` (an adapter read it) · `derived` (a rule produced it; carries a derivation) · `proposed` (a G1 candidate; binds nothing; excluded from current views by default) |
| **evidence state** | the source's own status token in the source's own vocabulary; never translated onto a common scale (Q-10) |
| **witness field** | a record field excluded from identity (timestamps, hosts, durations, run ids) — R2 rule 8 |
| **current view** | the set of records not superseded or retracted within the snapshot; a pure function, never a stored flag |

## 3. Ontology (closed for G0; extended only by a decision entry)

The dataset already reads every row through a five-level ontology — **semantic obligation / enforcement property /
mechanism instance / witness / trust profile** (`CROSS_REGISTRY_CLAIM_MAP.json#/ontology`, frontier §1b). G0 adopts it
as the spine and adds the evidence-lifecycle kinds the brief requires. Kinds the brief listed and where they went:
OBLIGATION, LAW, MECHANISM, PROFILE, ASSUMPTION, WITNESS, FALSIFIER, EXPERIMENT, RECEIPT, ARTIFACT, ADJUDICATION,
FINDING, PROPOSAL are kinds; COROLLARY, REPRESENTATION and IMPLEMENTATION are relations or attributes (see below);
POLICY is deferred (§16); COUNTEREXAMPLE is a `WITNESS.kind`; RELEASE_OR_ROUND is `ROUND`.

### 3.1 Node kinds

| Kind | What it is | First sources (census) |
|---|---|---|
| `OBLIGATION` | a semantic obligation on an `axis` ∈ safety (S1–S5) · liveness (L1?) · factory-epistemic (FAC-CONTROL-SENSITIVITY); `promotion` ∈ working · candidate · resolved-into | crosswalk `semantic_obligations`, `liveness_candidates`, `factory_candidates`, `resolved_candidates` |
| `ENFORCEMENT_PROPERTY` | a capability the trusted substrate must supply (S3(a) currentness, S3(b) history continuity) | frontier §1 prose; model check M1 (`adversarial_worlds.py`) — minted only where a record names it |
| `CLAIM` | a registry record asserting something, with an evidence state in its registry's vocabulary | crosswalk E-records (56); research ledger P/C/X/D claims (19); factory ledger claims (208) |
| `LAW` | a registered law in citation form `law:<id>@<rev>`, a numbered TRVM binding law, a WEK W-law, or a cross-cutting known law | `invariant-grid.json#law_registry` (138 entries / 107 ids), `LAWS.md` (11 ids), crosswalk `wek-w-laws` (4), CROSS category |
| `MECHANISM` | an implementation that discharges an enforcement property on a profile | code symbols in `relation: mechanism` records' `source_ids` (E-01 `LifecycleAdmission`, E-02 `reconstruct`); the cd-core `pub` item census (R7B) |
| `DEFINITION` · `REPRESENTATION` | a definition record; a representation invariant | crosswalk DEF / REPR categories |
| `PROFILE` | a scope / trust profile under which a mechanism earns a property; `unnormalized: true` when minted from free text | `scope_profile` (56), `trust_profile` (42 non-empty), frontier column 4 |
| `ASSUMPTION` | a stated antecedent or condition | `conditions[]` (3 records), factory `mosaic/assumptions.json` (29 `ASM-*`), ledger `assumptions[]` |
| `WITNESS` | an artifact that can bear on a claim; `kind` from the factory's evidence vocabulary (`deductive_proof`, `counterexample`, `constructive_witness`, `exhaustion`, `cited_result`, `measurement`) or `compile-fail-gate` · `model-check` · `result-document` · `tla-unexecuted` · `page`; `executed` ∈ true · false · `unknown{reason}` | `witness_paths` (93), ledger `witnesses` (269), `mosaic/evidence.json#kinds` |
| `FALSIFIER` | a control designed to fail a claim (NC-series scripts, `--mutate` controls, compile-fail gates, checker self-mutations) | `lab/scripts/nc*.sh` (10), `lab/falsifiers/` (2), `tools/compile-fail/` (21), gate mutations |
| `FINDING` | a defect established by falsification, with a lifecycle (F1–F37 in the R0.8.x series; the R0.4.x `f<n>` series is a different namespace) | `r0_8`, `receipts/*-FALSIFIED.md` headings `## F<n> — `, commit subjects |
| `EXPERIMENT` | a planned or executed experiment (EXP-1…EXP-8, R0.8.x lab series, model checks M1–M7), `executed` state | `06_R10PRE_EXPERIMENTS.md`, `experiments/*/RESULT.md` (8 dirs; EXP-2 does not exist) |
| `RECEIPT` | a hash-bound artifact recording an execution: `sha256`, `runtime`, `executed_by`, `result` | `promotions[].sensitivity_witness` (9 hashes, all MATCH at the pin), `px13/*.tar.gz`, `receipts/*-FINAL-*.json`, `mosaic/receipts/*` (20) |
| `ARTIFACT` | a source tree, commit, binary or image referenced by identity, never ingested (in-toto ResourceDescriptor + DigestSet, R2 §3) | `computedriven@efa8881`, `ampd@7651697`, `trvm_world.mjs v0.12.0`, `cd-r05-runner:v3 sha256:…` |
| `ADJUDICATION` | a ruling by an agent with stated `authority` ∈ advisory (GPT/Fable sections) · ruling (Travis) · factory (a promoted round) | `inputs*.md` sections (`# 1. S6? ruling — ACCEPT…`), `REVISION_REGISTER.md` R1–R43, `mosaic/receipts` |
| `EVIDENCE_STATE_TRANSITION` | one movement of a claim's evidence state, with or without a typed sensitivity witness | `promotions[]` (5), `evidence_class_*` history fields |
| `ROUND` | a release or round (`R0.8.5`, `package-v2.6`, `INV-R9.4`, `WRL Core 0.1.2`) | git history, `_round`, package headers, receipts |
| `CELL` | a periodic-table cell (46) bound to claims by the ledger | `cells.json`; binding is reverse-only (`implementation_binding: cell:NN`, 54 claims → 7 cells) |
| `REGISTRY` | the source document itself: id, revision, status vocabulary, authority class | every adapter |
| `SOURCE_LOCATION` | file (+ pointer / heading anchor / line range) at a pinned identity, with `precision` | every adapter |
| `FAULT` | a malformed / ambiguous / contradictory / unsupported source state, attached to what it concerns (§12) | every adapter |
| `PROPOSAL` (G1) | a candidate relation or reclassification with its evidence; `basis: proposed` | G1 rules only |

### 3.2 Relation kinds (directed; endpoints carry roles `source` → `target`; multigraph allowed, see §4.3)

| Kind | From → to | Observed from | Derived by |
|---|---|---|---|
| `STATES` | claim → obligation | crosswalk `relation: direct` | — |
| `IMPLEMENTS` | claim / mechanism → obligation or enforcement property | `relation: mechanism` | — |
| `DERIVES_FROM` | claim → claim / obligation | `relation: corollary`; id-shaped `derivation_links` (20 of 61 resolve) | transitive closure, labelled (G1) |
| `REDUCES_TO` | obligation / claim → obligation | `resolved_candidates` (S6? → S1) | G3 proposals only |
| `REFINES` | claim → claim | narrowed / reworded records (C-2, C-5) | — |
| `SPLIT_FROM` | claim → claim | `split_from` (E-13 → a/b/c, E-46 → a/b/c, E-50 → a/b) | — |
| `SUPERSEDES` | record revision → record revision; round → round; claim → claim | ledger `supersedes`/`superseded_by`, grid lineage fields, package succession | snapshot succession |
| `RETRACTS` | adjudication / round → assertion | explicit retractions (nanopub pattern, R1 §3) | — |
| `REQUIRES` | claim → claim | ledger `dependencies[]` | — |
| `WITNESSES` | witness / receipt → claim, `outcome` ∈ pass · fail · not-run · `unknown{reason}` | `witness_paths`, `receipts`, `sensitivity_witness` | — |
| `SUPPORTS` · `FALSIFIES` | witness / finding → claim | explicit statements (`pre-fix-fail`, `FALSIFIED-KEPT-RED`) | from `WITNESSES.outcome` (G1) |
| `ATTACKS` | falsifier → claim / mechanism | NC / control naming | — |
| `TESTED_UNDER` · `SCOPED_BY` · `ASSUMES` | claim → profile / assumption | `scope_profile`, `trust_profile`, `conditions`, `tested`/`not_tested` | — |
| `CLOSES` · `OPENS` | round / adjudication / receipt → finding | `closed_by_adjudication_v3`, `open_findings`, commit subjects | — |
| `PRODUCED_BY` | receipt / artifact → experiment / round / runtime artifact | receipt fields | — |
| `ADJUDICATED_BY` | transition / claim → adjudication | `GPT v(\d) §(\d+)` citations (58 mentions, 33 distinct) | — |
| `LOCATED_IN` | any node → source location | every adapter | — |
| `MEMBER_OF` | claim → registry; record → round | every adapter | — |
| `BINDS` | claim ↔ cell | `implementation_binding` | — |
| `CITES` | claim → cited result / source | `mosaic/sources.json` (24 `SRC-*`), ledger `prior_art` | — |
| `INDEPENDENT_OF` | enforcement property ↔ enforcement property | model check M1 | — |
| `CONFLICTS_WITH` · `EQUIVALENT_TO` | claim ↔ claim | — | G1 diagnostics / G3 proposals only |

Distinctions the brief requires and where they live: obligation vs mechanism (`OBLIGATION` vs `MECHANISM`, joined by
`IMPLEMENTS`); law/primitive vs corollary (`OBLIGATION.promotion` + `DERIVES_FROM` / `REDUCES_TO`); evidence vs claim
about evidence (`RECEIPT`/`WITNESS` vs `CLAIM`, joined by `WITNESSES` with an `outcome`); plan vs executed vs receipt
(`EXPERIMENT.executed`, `WITNESS.executed`, `RECEIPT`); current state vs transition (`CLAIM.evidence_state` vs
`EVIDENCE_STATE_TRANSITION`); scope / profile / assumption (three kinds); negative / unknown / open (§5.5); source
authority vs semantic confidence (`REGISTRY.class` + `asserted_by` vs a source's own confidence carried as a decimal
string); artifact identity vs the claims it supports (`ARTIFACT` vs `WITNESSES`).

### 3.3 Namespaces

Identifiers collide across sources (R7B): computedriven's R0.4.x compile-fail `f15` ≠ the R0.8.x finding `F15`; `S1`
is an obligation in dataset A, a store label in `nc28_foreign_successor.sh`, and a session label in the TRVM grid;
`E-8` is a grid exhibit label; ampd's `locus_test.exs` has its own `F1…F17`. **Every identifier entering the graph
carries a `(source, namespace)` qualifier in its lid** (§4.1). An adapter that cannot name the namespace emits
`AMBIGUOUS_IDENTIFIER` rather than guessing.

## 4. Identity rules

Two identities per node and per relation, never conflated — the split WRL §D8.1 made for relations, applied to
everything (R5 §2.2: `rel-` is a stable name minted from an allocation; `rev-` is the content-addressed value).

4.1 **Logical id (`lid`)** — stable across snapshots, human-readable, minted deterministically from the source's own
identifiers, restricted to `[A-Za-z0-9._:/@+-]` (R3 §3 rule 2). Grammar: `<kind-prefix>:<namespace>:<local id>`, e.g.
`claim:crosswalk:E-13b` · `claim:factory:FED-UNIV` · `claim:r10:C-7` · `law:trvm:kappa.monotonicity.unrestricted@1` ·
`law:trvm-binding:4` · `obligation:S3` · `finding:computedriven:F35` · `cell:36` · `experiment:r10:EXP-6` ·
`round:computedriven:R0.8.5` · `receipt:sha256:6ba8544c…` · `artifact:git:computedriven@efa8881` ·
`profile:text:<sha256(normalized)[:16]>` · `adjudication:gpt:exec-v1:§1`. A lid is a **name**, never a hash of
content: content changes must not rename (R2 rule 9).

4.2 **Revision id** — the content hash of the node's or relation's normalized record, written `sha256:<64 hex>`
(R2 rule 14). Relations additionally carry WRL's `rev-` computed by the WRL relation kernel over the relation's
revision value (§7.2); the two are different functions over overlapping bytes and both are stored. Two snapshots that
agree on a record's content share its revision id; a change produces a new one and a `SUPERSEDES`.

4.3 **Statement and relation lids.** `statement lid = rel:<kind>:<source lid>:<target lid>`. A relation that may
legitimately repeat (two receipts each witnessing one claim) gets a qualifier — the asserting source's lid — so
`rel:WITNESSES:receipt:sha256:21569669…:claim:crosswalk:E-48` is one relation and the same claim's other receipt is
another. The same statement made by two registries is **one** relation with two assertions (§4.4), not two relations
(R1 §1, §4: reifier ≈ edge id; declared identity keys make the multigraph deterministic).

4.4 **Assertion id** — `asrt:<relation or node lid>:<source location id>`. Assertions are the provenance leaves; a
relation's `assertions[]` is a set (sorted by canonical bytes).

4.5 **Source location id** — `loc:<registry lid>:<pinned identity>:<path>[#<pointer | anchor | L<a>-<b>>]` with
`precision` ∈ `pointer` (RFC 6901, JSON sources) · `heading` (Markdown heading anchor derived from the regular
grammars R7B found: `## F<n> — `, `# <n>. `, `## [MNQ]0-<n> — `) · `line` · `file`. A coarse location is never
presented as a fine one (Q-06); the pinned identity is the blob OID for tracked files (R7A/R7B record them) and
`sha256:` for loose files.

4.6 **Aliases and collisions.** A node may carry `aliases[]` (e.g. `obligation:S6?` ↔ `claim:r10:C-7` ↔
`claim:crosswalk:E-44` share a subject); aliasing is an observed relation (`SPLIT_FROM`, `REFINES`, `BINDS`) or a
G1 proposal, never an adapter merge. Two sources minting one lid with different content ⇒ `FAULT(DUPLICATE_ID)`, both
records kept.

4.7 **Supersession without deletion.** Nothing is removed from a projection's history. Within a snapshot, a source's
own history fields (`evidence_class_before_v2_3` → `_v2_4` → `_v2_5` → current; ledger `supersedes`) become
`EVIDENCE_STATE_TRANSITION` nodes and `SUPERSEDES` relations *(amended by D-037: the transition → claim edge is `STATE_TRANSITION_OF`; `SUPERSEDES` is reserved for replacement between comparable entities)*. Across snapshots, a later snapshot's records supersede by
lid. Retraction is a positive record (`RETRACTS`) with its own provenance (R1 §6: Datomic's one idea; nanopub
`npx:retracts`). The current view is derived (§13 rule `current`), never a stored flag (WRL §D9: the ledger grows;
the active view does not).

## 5. Provenance rules

5.1 `basis` is mandatory on every node and relation. `observed` records carry ≥ 1 assertion with a `SOURCE_LOCATION`;
`derived` records carry a `derivation` (§10.3); `proposed` records carry a derivation and the G1 rule that proposed
them, and are excluded from every current view unless asked for.

5.2 Field names follow PROV (R1 §2) so an export is a relabelling, not a redesign: `generated_by` (the adapter or
rule run), `derived_from[]` (premises), `plan` (the adapter's or rule's content-bound id), `attributed_to` (the
registry or agent), `invalidated_by` (the superseding or retracting record). PROV-O / OpenLineage are export adapters,
never storage (R2 §5).

5.3 `asserted_by` is the registry lid; `REGISTRY.class` ∈ AUTHORITATIVE · DERIVED · HISTORICAL · ADVISORY from
`SOURCE_INVENTORY.md`. An ADVISORY source (a GPT section) yields `ADJUDICATION` nodes and `ADJUDICATED_BY` relations
and **cannot change a claim's evidence state** — only a registry record can, and the registry says whether it did.
Three sources disagreeing about F35 (Q-09) are three assertions, visibly disagreeing; resolution is a G1 diagnostic
with all three shown.

5.4 **Adapter run record** (R2 §5): identity part `{adapter: RD(gitBlob of the adapter source), inputs: [RD(gitBlob |
sha256)…], params, source_commit, outputs: [record hashes…]}` is hashed; witness part `{started_at, finished_at,
host, exit_code, log_digests, run_id}` is not. Replay rule: same adapter digest + same input digests + same params ⇒
same output digests; a violation is a `NONDETERMINISM` finding about the adapter, never a new fact.

5.5 **Unknown, negative and open.** Absence is never falsity (R1 §7). Negatives are explicit and scoped:
`NOT_FOUND{registry, snapshot, adapter}` is a sound closed-world statement because the registry is finite and
enumerated at a named identity. Unknowns are typed with a reason code (FHIR `data-absent-reason` pattern):
`unknown{reason ∈ not-stated · not-executed · undecidable-from-data · source-dangling · masked}`. The sources' own OPEN
tokens are evidence states, copied verbatim. "Why is X not a primitive?" is answered by a *positive* derivation from
an adjudication or a resolved-candidate record, never by failure to find one.

5.6 Evidence state is copied verbatim with its vocabulary id; an adapter never normalizes `TESTED-CONDITIONAL` to
`TESTED`. A cross-vocabulary comparison is a G1 rule whose mapping table is data.

5.7 Every record carries the snapshot id; the projection root (§6.6) binds the snapshot's source identities.

## 6. Normalized record model and canonical bytes

6.1 **Record shape.** `{lid, kind, basis, attrs, assertions[] | derivation, snapshot}` plus kind-specific fields;
field names `^[a-z][a-z0-9_]*$`; no field holds two of the §4 identities; optional fields are omitted, never `null`
(R2 rule 7); each record type declares its identity-bearing fields and the hash is computed with witness fields removed
(R2 rule 8).

6.2 **Value domain (the G0 profile of RFC 8785).** Objects, arrays, strings, integers within ±(2^53−1), `true`,
`false`, `null`. **No native floats**; a source float is carried as the decimal string from the source bytes with
`number_form: "decimal-string"` (`1.0` stays `"1.0"`). Keys are ASCII `^[A-Za-z_][A-Za-z0-9_]*$`. Strings are
well-formed Unicode scalar values, literal UTF-8, with no C0 control other than U+0009/U+000A/U+000D and no U+007F.
Set-valued fields are declared in the schema and sorted by the canonical bytes of their elements; duplicates refused.
Measured basis: five of six registries canonicalize byte-identically in Node and Python under this discipline and
the sixth diverges on exactly one `1.0` (`TEST_FIXTURES/canon-divergence-2026-09-02.md`); the three in-house
canonicalizers agree on exactly this intersection domain and diverge outside it (R6 §4, R5 §3.2); under these
restrictions the bytes equal RFC 8785 output in Python, Node and Elixir (R2 §1, measured).

6.3 **Canonical bytes = TRVM `canonicalBytes`** (`TRVM/governance/derive_protocol.mjs:308-351`, RFC 8785-measured)
applied to the 6.2 domain: recursive key sort by UTF-16 code unit (= byte order under ASCII keys), compact separators,
no trailing newline, JSON-mandatory escapes only. The Node implementation imports it; the Python twin is
`json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=False, allow_nan=False)` after a float/NaN refusal;
both must pass a conformance corpus on every build — RFC 8785 Appendix B integer rows, the §3.2.3 sort example
restricted to ASCII keys, WRL's `test/projection-vectors.json`, TRVM's `jcs_vectors.mjs`, and every fixture in
`TEST_FIXTURES/` — failing on any single-byte disagreement between runtimes (R2 rule 17). Elixir is not a G0 host
(§16).

6.4 **Hash form.** `sha256:` + 64 lowercase hex over the canonical bytes; `sha256` is the only algorithm at G0; the
prefix exists so a second can be added without re-hashing.

6.5 **External artifacts** are ResourceDescriptors `{name?, uri, digest: {alg: hex}, media_type?}` with
`alg ∈ {sha256, gitCommit, gitTree, gitBlob, dirHash1}` (in-toto DigestSet, R2 §3); content is never embedded; a
tarball is hashed only if built reproducibly, otherwise the tree is.

6.6 **Projection manifest and root.** The manifest is a record `{kind: "graphonomous.projection", spec: <this
spec's revision id>, snapshot, entries: [[lid, sha256:…]…] sorted by lid, count, per_kind: [[kind, digest]…]}`; the
**projection root** is the CAS root of that manifest (§8.2), computed over the sorted entries and therefore
independent of adapter order, traversal order and scheduling. Leaves are `SHA-256(0x00 ‖ canonical bytes)` (RFC 9162
leaf form) so a Merkle tree or transparency log can be layered later without re-hashing (R2 §4, §6). A git tree id of
the canonical files is published beside the root as a witness, never as the definition (R2 §6: modes, the
directory-as-`/` sort and the SHA-1 default leak in).

## 7. WRL representation (decided from the R5 audit, WRL `1f4c5fd`, conformance 890/890)

7.1 **What WRL can carry today.** The writable surface is one frozen circuit profile (five roles, two edge kinds, one
texture, `forge.world.core.v1`); a G0 spelling is refused at parse (`WRL_UNSUPPORTED_FEATURE role 'claim' not in the
frozen v1 surface registry`), a new profile id at `validateGraph` (`unknown profile … this compiler only serves
forge.world.core.v1`), and a V2 relation with kind `supports`, domain `evidence`, non-empty `attributes`, arity ≠ 2 or
a non-solid texture at the V2 world gate (R5 §1.3, §2.4). Beneath that gate the **relation kernel is family-neutral and
executable**: `relation-identity.js` hashes a G0 `evidence.SUPPORTS` revision with nested attributes to a `rev-`, mints
`rel-` from a named allocation, enforces endpoint roles, terminal uniqueness and canonical endpoint order, and refuses
`provenance` inside a revision by design (R5 §2.5; law `the-revision-model-is-family-neutral`, D8.9). `ProfileSchemaV1`
(§D6.1), relation attributes' type system, the §D8.3 event provenance and all of §D9 have zero code (R5 §4–§5).

7.2 **G0 is kernel-native now and seal-native when WRL can seal it (D-009).** The semantic world is a V2-shaped
artifact: `ir_version: "2.0"`, `profile_id: "graphonomous.semantic.v0"`, `objects[]` with `role` = the §3.1 kind,
`object_id` = the lid, one nominal port `node` per object (the R5 G7 adapter: a terminal must name a port), attributes
in `static_config`; `relations[]` = `{identity_seed: {variant: "named-initial", relation_name: <statement lid>},
revision: {domain: "semantic", kind: <§3.2 kind>, orientation: "directed", texture: "solid", endpoints: [{role:
"source", terminal: {object_id, port: "node"}}, {role: "target", …}], attributes: {evidence_state?, scope?,
outcome?, …}, policy: "graphonomous.semantic.rules.v0"}}`. `rev-` ids come from `canonicalizeRelationRevision` /
`relationRevisionId` and `rel-` ids from `relationIdFromAllocation` in `WRL/relation-identity.js`, called directly
(the kernel accepts them today, R5 §2.5). The world id is computed with `serializeArtifact` + sha256 over the same
bytes rule but carries the prefix **`gsem-`**, never `sem-`: WRL did not seal it, and a G0 id must not impersonate a
spine identity. `rel-` ids are world-scoped to that `gsem-` (D8.5).

7.3 **The profile as data.** `WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json` states, in the §D6.1 shape, the role
declarations (the eight-item list lacks them — R5 §5.1's spec-text hole, recorded as GAP-W1), relation signatures
(domain, kind, orientation, arity, admissible endpoint roles), endpoint-role constraints per kind (e.g. `FALSIFIES:
source ∈ {FALSIFIER, FINDING, WITNESS, RECEIPT}, target ∈ {CLAIM, LAW}`), enumerated types (each registry's evidence
vocabulary as its own enum), canonical defaults (an omitted `evidence_state` is omitted, never `"open"`), and the
uniqueness/cardinality validators G0 enforces. G0's own validator applies it until WRL can load it. It is
authored in G0-C and versioned with the spec.

7.4 **D8 rulings adopted as constraints now:** provenance lives on the event/assertion, never in the revision value
(D8.3 — matches §4.4 and R5 G4's interim); one home for lifecycle (D8.2); stable name vs content-addressed value
(D8.1); world-scoped relation ids (D8.5); attributes carry no floats (`WRL_NUMERIC_RANGE` is the kernel's refusal and
§6.2's rule); `revision.policy` is set to the constant above and never used as an attribute slot (R5 G9).

7.5 **Labelled adapter and its removal condition (brief §10).** Computing `gsem-` outside the spine is the temporary
adapter. It is removed when WRL ships a profile mechanism with a *static* profile kind (R5 G1, G6: a `PROFILES[profile_id]`
data table with `forge.world.core.v1` as row one so both pinned `sem-` ids stay put, plus a static kind that carries
no admit/film/runtime-state policies) — at which point the same artifact seals to a real `sem-` and the `gsem-` ids
are superseded, not silently renamed. That change is proposed to the WRL owner in the handoff; it is not made here
because WRL Core is a frozen family and the profile mechanism is ladder step 3 of its own direction document.

7.6 **Sandbox demo (brief §8, DEMO step 9).** A sandbox copy of the semantic world is edited as V2-shaped text
(`[name]: [a] --kind--> [b]` under the G0 profile, parsed by G0's reader since `wrl.js` refuses the header),
re-canonicalized, its `gsem-` moves, and the projection reflects exactly the edited relation; the WRL kernel's `rev-`
for the edited relation changes and every other `rev-` holds. That is the bidirectional integration WRL supports
today, stated at its real size.

## 8. TRVM contract (decided from the R6 audit, TRVM `fd0df4c`, grid 1.69.0)

Real, testable participation — each item was exercised on Graphonomous-shaped data in `research/probes/trvm/`:

8.1 **Canonical bytes** are TRVM `canonicalBytes` (§6.3). G0 ships no fourth canonicalizer.

8.2 **Content-addressed store.** Normalized records and the projection manifest are stored through
`TRVM/governance/cas.mjs` unchanged: `root-` + sha256(`TRVM-ARTIFACT-ROOT-v2|` ++ canonical bytes); resolution
re-canonicalizes, requires raw == canonical, re-derives the root and names one of eight outcomes (`ok`,
`non-canonical-wire`, `root-mismatch`, …). Measured: a record and a manifest round-trip `ok`; pretty-printed bytes under
an honest root → `non-canonical-wire`; a duplicate-key forgery refused (R6 §3.1). Limits accepted: JSON only, local
directory or memory store, 8 MiB per artifact (policy, `cas.mjs:125`); larger things stay outside by identity (§6.5).

8.3 **Claim certificate.** A projection publishes `verifiedClaimSemId({protocol: "GRAPHONOMOUS-PROJECTION-v0",
claim_sem_id, aggregate_id, chain_ids})` (`certificate.mjs:60-68`); it moves on claim/evidence/chain change and holds
on prose edits, and it is **not a warrant** — G0 ships its own checker for the protocol (GAP-T9) and copies
`live_dag.mjs`'s rule that ids compare as relations, not values.

8.4 **Derivations.** Every `derived` record carries `derivation = {rule_sem_id, premises[], inputs: [root-…],
evaluator}` where `rule_sem_id` follows the `programSemId` discipline (id = H(core id | canonical rule AST), never a
name). The frozen derive core issues genuine, replayable, footprint-bound receipts only for **numeric** facts
(`add/sub/mul/len` over grants); every rule that decides something (equality, quantification, conditional verdicts,
traversal) is outside the core **by ruling** — probe: `program-unknown-op` for `forall`, `eq`, `and`, `if`, `get`,
`prim`; only `sub(len(scope …), 1)` binds (R6 §2.1; GAP-T1…T4, T6, T11). Therefore in G0 the projector evaluates
rules itself (§10) and records a **provenance record** in the CAS labelled `kind: "graphonomous.rule-evaluation",
trvm_derivation: false`. This is a labelled temporary adapter under brief §10, removed when a `prim` catalog carrying
`eq.canonical/1`, `get.field/1`, `set.count_where/1`, `set.all/1`, `if.value/1` (R6 §2.2) ships and re-hashes the
core; until then no G0 document may call a rule evaluation a TRVM derivation receipt. Where a rule *is* numeric
(counts per obligation, receipts per claim), G0 issues it through the derive authority so the receipt path is
exercised for real (`derive_battery.mjs` 45/45 at `fd0df4c`).

8.5 **Grants.** When G0 uses the derive authority, the read grant is a snapshot slice keyed by lids at the
snapshot's identities (`version` may be a string, `checkGrants :648`); sets are never passed through `scope` until
GAP-T7 is ruled (the World's scope digest hashes an unsorted `JSON.stringify`).

8.6 **Not used in G0.** The interaction-calculus reducer (GAP-T13): the lowering covers `const/add/input/sub/mul`
only and refuses reads; a Graphonomous fact never reaches the calculus. A G2+ design reference for merging replicas.

## 9. Projection store and indexes (decided from R3 §6 and R2 §6)

9.1 The store of record is a **directory of canonical JSON** — one file per kind (`nodes/<kind>.json`,
`relations/<kind>.json`, `assertions.json`, `derivations.json`, `faults.json`, `snapshot.json`, `manifest.json`) —
whose bytes are exactly the records' canonical bytes joined by `\n` in lid order, plus the CAS directory for the
per-record `root-` objects and the manifest. Deleting the directory and rebuilding from the snapshot reproduces it
byte-for-byte (A8).

9.2 **SQLite is a throwaway index**, never the store and never a digest surface (rowids renumber on VACUUM;
deleted content lingers; implicit order is undefined — R3 §6). It is built from the JSON, keyed by lid as
`TEXT PRIMARY KEY`, queried only with `ORDER BY`, and may be deleted at any time. Hosts: `node:sqlite` (RC) /
Python `sqlite3`. No FTS5, no `sqlite-vec`, no daemon, no network store in G0.

9.3 The browser page (§11) loads the JSON files into the same ESM query module; no SQLite in the browser at G0.

## 10. Query and explanation API (decided from R3 §4–§5)

10.1 **Surface.** One dependency-free ESM module shared by the CLI (JSON in / JSON out) and the page, exposing exactly:
`node(lid)`, `neighbors(lid, kind?, direction)`, `path(a, b, kinds?)`, `facts(rule_id | kind, filter?)`,
`explain(lid | fact_key)`, `as_of(snapshot_id)`. No Cypher/GQL, no SPARQL, no GraphQL (R3 §4: none adds a
derivation, each adds a parser).

10.2 **Rules are data.** The G0 rule set (§13) is a canonical JSON program; `rule_sem_id` = H(`G0-RULESET-v1` |
canonical rules) with per-rule ids `<rule_sem_id>#<rule name>`. The evaluator is a ~300-line stratified semi-naive
Datalog evaluator (R3 §1: build, not adopt — Soufflé and Nemo ship no Node/Python artifact, CozoDB is dormant, DDlog is
archived, nothing else records provenance) with: negation only over lower strata (stratification refuses a negative
cycle at load); iteration over arrays sorted by canonical key, never Map order; at most `max_alt` (4) derivations kept
per fact, sorted by `(depth, canonical bytes)` so the minimal-depth proof is first and ties break by bytes; output
sorted by canonical bytes. A Python port of the same shape cross-checks the derivation set's digest.

10.3 **Explanation object** (R3 §5; JTMS justification shape): `{id: sha256(JCS({rule, conclusion, premises})), rule,
conclusion, premises: [fact_key | {absent: pattern}…] in body order, bindings, depth}`; base facts carry
`source: {registry, pinned identity, path, pointer}` and depth 0. `explain` unfolds the first derivation
recursively, rendering `{absent}` as leaves ("no executed receipt for E-10 at snapshot S") — never by failure to find.

10.4 **Independent checker** (~50 lines, sharing no code with the evaluator): substitute `bindings` into the rule,
confirm each positive premise is a fact, each `absent` premise has no match in the lower strata, and the instantiated
head equals `conclusion`; walk premises to rebuild the tree. The checker runs in the G0-G gate on every derivation.

10.5 Every answer the API returns is a set of records with lids and identities; prose is composed by the caller from
record fields, never by the API.

## 11. Minimal UI (G0.5; requirements frozen; libraries decided by D-015 from the R4 measurements)

Pan/zoom; filters by kind, relation kind, subsystem (registry), evidence state, scope; select a node or relation →
panel with assertions, source locations (deep link to the file at its pinned identity), evidence state history,
derivation tree from `explain`; expand `IMPLEMENTS` / `SUPPORTS` / `FALSIFIES` / `DERIVES_FROM` neighbours;
supersession chains across snapshots; observed vs derived vs proposed distinguished by stroke style **and** a text
badge, never by colour alone (WCAG 1.4.1). The page reads the projection JSON and imports the §10 module; it computes
nothing the CLI does not. Layout is a derived view: coordinates are never persisted as truth; a layout cache, if any,
is keyed by the projection root and is a witness file outside the digest. Deterministic layouts (layered) are
preferred; a force layout must take a fixed seed.

Libraries (D-015): Cytoscape.js 3.34.2 (cdnjs ESM) with cytoscape-dagre 4.0.1 for sub-graph layered views (≲ 500
nodes) and ELK layered 0.12.0 (fixed `randomSeed`, `considerModelOrder`) for whole-graph deterministic layering from a
digest-keyed cache; fcose only for non-layered overviews (no seed — never a reproducibility surface); fallback and
export `@viz-js/viz` 3.30.0 → SVG → `svg-pan-zoom` 3.6.2; Sigma 3 past ~5k nodes. Measured (R4): at 2,000 nodes /
10,000 edges Cytoscape renders in 667 ms while dagre exceeds 240 s, ELK takes 12.3 s and Graphviz `dot` 11–14 s;
`dot`/ELK rerun identically, dagre is insertion-order-sensitive — hence canonical sort before every layout.

## 12. Fault and error semantics

A fault is data attached to the record it concerns and it reaches the projection root (a projection with a fault has
a different root than one without). Faults never stop a build unless an input is unreadable. Shape (SHACL-shaped
report with positions, R2 §7): `{code, rule, source: RD(gitBlob | sha256), pointer | anchor, range: {start: {line,
column, offset}, end}?, message, concerns: [lids]}`. Vocabulary: `SOURCE_MOVED` · `SCHEMA_UNEXPECTED_FIELD` ·
`SCHEMA_MISSING_FIELD` · `DANGLING_WITNESS` · `DANGLING_SUPERSESSION` · `DANGLING_CELL_BINDING` · `UNRESOLVED_LINK` ·
`TRUNCATED_FIELD` · `UNPARSEABLE_CITATION` · `HEADING_WITHOUT_NUMBER` · `DUPLICATE_SECTION_NUMBER` · `UNKNOWN_TOKEN` ·
`DUPLICATE_ID` · `AMBIGUOUS_IDENTIFIER` · `WORKTREE_DIFFERS` · `UNSUPPORTED_SOURCE_FORM` (a source shape G0 does not
ingest, named rather than skipped) · `NONDETERMINISM` (§5.4) · `CONTRADICTION` (G1). `SOURCE_QUALITY_FINDINGS.md` lists
the faults the first dataset is already known to raise (Q-01…Q-21).

## 13. The G0 rule set (data; stratified; every rule content-bound)

Stratum 0 (positive):
`has_exec_receipt(C) :- witnesses(R, C), receipt(R), executed(R, true)` ·
`reduces_to(A, B) :- rel(A, REDUCES_TO, B)` · `reduces_to(A, C) :- reduces_to(A, B), rel(B, REDUCES_TO, C)` ·
`derives_from*(A, B)` likewise · `superseded(X) :- rel(_, SUPERSEDES, X)` · `superseded(X) :- superseded(Y), rel(X,
SUPERSEDES, Y)` · `retracted(A) :- rel(_, RETRACTS, A)` · `not_primitive(S) :- reduces_to(S, _)` ·
`supports(W, C) :- witnesses(W, C, outcome: pass)` · `falsifies(W, C) :- witnesses(W, C, outcome: fail)` ·
`mechanism_of(M, O) :- rel(M, IMPLEMENTS, O)`.
Stratum 1 (one negation each, over stratum 0 and observed facts):
`current(X) :- record(X), not superseded(X), not retracted(X)` ·
`unsupported(C) :- claim(C), token_contains(C, "TESTED"), not has_exec_receipt(C)` — and, because 48 of 56 crosswalk
records carry `executed: null` (Q-03), a companion `undecidable_support(C) :- claim(C), token_contains(C, "TESTED"),
receipts_untyped(C)` so A6 partitions into supported / unsupported / undecidable-from-data and the third bucket is
never folded into either of the others.
Every derived fact records its rule id and premises (§10.3). Rule text lives in
`INGESTION_CONTRACTS/../rules/g0.rules.json` from G0-A on; this section is its human reading.

## 14. Acceptance tests (G0) — traversals over stored records, verified this round against real artifacts

**Snapshot pins (D-008).** Current: `invariant-r10` at `ba4e625` (v5 return, `package-v2.7/`); historical:
`699fbc2` (`package-v2.6/`); factory ref `refs/heads/invariant-canonical` at `d217ee2` (INV-R9.4); TRVM `fd0df4c`;
WRL `1f4c5fd`; computedriven `21a1452` (docs, receipts, git log; `efa8881` as the ARTIFACT the packages vendored);
super `c4160fd` (HEAD only; the worktree is volatile); opensentience.org `2c0f523`. A v2.7 delta census precedes G0-B.

| # | Query | Expected traversal (records verified to exist at `699fbc2`; the v2.7 delta may add premises, never remove these) |
|---|---|---|
| A1 | *Why isn't S6 a primitive?* | `obligation:S6?` —`REDUCES_TO`→ `obligation:S1` (observed: crosswalk `resolved_candidates["S6?"]`); premises: `claim:crosswalk:E-44` (`relation: corollary`, `TESTED`, witnesses `experiments/rust/results/S6_locus_birth.md`, `s6_birth.rs`, two compile-fail gates), `experiment:r10:S6-locus-birth` (RESULT: "two births … both act; a warden of one birth finalizes the other; the World admission refuses the second birth; reuse fails to compile"), `adjudication:gpt:exec-v1:§1` ("ACCEPT the reduction to S1 … I do not see a residual semantic property that requires a distinct S6", `inputs-gpt-execution-adjudication.md` ll. 116–176), the framing rule `adjudication:gpt:v2-audit:§6` (ll. 353–369), `claim:r10:C-7` (`status_before_v2_3: UNKNOWN` → `TESTED`; `classification_v2_4: S1 corollary`; `semantic_map C-7 → S6?` kept as origin) |
| A2 | *Why is R0.8 still open?* | at `699fbc2`: `round:computedriven:R0.8` (`status: OPEN`) —`OPENS`→ 5 findings (F35 OPEN-UNADJUDICATED; power-loss UNCLAIMED; post-rename durability; single host; trusted anchor namespace as assumption); —`CLOSES`← `adjudication:gpt:v3` for F31/F23/F24/F32/F33/F34/F22/F30 each `SCOPED_BY` its profile; `shipped_not_adjudicated`: `receipt:sha256:cffc0218…` (R0.8.6 handback). At `ba4e625` (v2.7): F35 `CLOSES`← `adjudication:gpt:v4`, and the open set becomes the NC29 cut with F36/F37 (`px13/COMPUTEDRIVEN_R087_FOR_GPT.*`). The answer is per snapshot and `as_of` shows both. |
| A3 | *What currently supports S5?* | `obligation:S5` ←`IMPLEMENTS`— `claim:crosswalk:E-48` (`TESTED under the exact stated profile`, `executed: true`, `tested[6]`/`not_tested[5]`, 12 witness paths incl. `phase_crash_naive_after.json`, sensitivity witness `sha256:21569669…`, runtime "Elixir 1.19.4 (Erlang/OTP 28) · 8 BEAM boots"), ←`DERIVES_FROM`— `E-50a`, `E-50b` (`FALSIFIED-KEPT-RED`), `E-51` (`EXHAUSTIVE-IN-MODEL`; its receipt `effect_identity_model.output.txt` matches `sha256:6966c054…` only at `699fbc2` — Q-14), plus E-16 (ARGUMENT), E-17, E-18 (in_tree), and `claim:r10:P5` (`TESTED`, was SUPPORTED) |
| A4 | *What assumptions/scopes constrain this receipt?* | `receipt:sha256:6ba8544c…` (R0.8.5 handback) —`WITNESSES`→ `E-13b`, `E-14`; those —`ASSUMES`→ three / two `conditions[]` items; —`TESTED_UNDER`→ `profile:text:…` ("single host · one protected deployment-owned canonical deployment anchor namespace … F35 open"); E-14 also carries `committed[3]` / `not_claimed[3]`; the transitions `transition:crosswalk:E-13b:v2.6` / `E-14:v2.6` name it as `pre-fix-fail` sensitivity witness with `pre_fix_witness` = the R0.8.4 tarball |
| A5 | *Which mechanism implements this obligation?* | `obligation:S1` ←`IMPLEMENTS`— `mechanism:computedriven:LifecycleAdmission` (from `E-01`'s `source_ids`; `cd-core/src/locus.rs` L69 at `21a1452`), `obligation:S2` ← `mechanism:computedriven:reconstruct` (`authority.rs` L36); the 8 `relation: mechanism` records; the frontier's prose mechanisms and `L1?.mechanism_instances_seen` are `UNSUPPORTED_SOURCE_FORM` until an adapter for them exists — **no registry has MECHANISM records** (R7A q5) |
| A6 | *Which claims are unsupported by an executed receipt?* | 22 TESTED* records at `699fbc2`: `executed: true` on 5 (E-13b, E-14, E-15, E-48, E-49); E-10 has no receipt at all; 11 cite only code or prose; receipts are bare strings without an `executed` marker — so the answer partitions into supported (5 + E-50a/b, E-51 outside TESTED*), unsupported (E-10), and undecidable-from-data (the rest), each with its `{absent}` premise |
| A7 | *Where did this relation come from?* | any relation → its assertions → `SOURCE_LOCATION` (registry lid, blob OID / sha256, path, pointer or heading, `precision`); for crosswalk records the precision is `pointer` for the record and `file` for `source_ids` (no line numbers exist in the file: R7A §1.2) |
| A8 | reconstruction | `project(snapshot)` twice with shuffled file order and reversed adapter order ⇒ identical projection root, identical CAS roots, identical derivation-set digest from the Python twin |

## 15. G1 contract (specified; implemented after G0-G)

Each diagnostic is a rule in the §13 program with its own id, evidence and reproduction; each emits `CONTRADICTION`
faults or `PROPOSAL` records, never a state change. From brief §9, with the source facts that already instantiate them:
equivalent-looking claims with conflicting status (the three F35 assertions, Q-09; the three ledger states, Q-15);
`TESTED`/`CLOSED` claims with no admissible executed receipt (§13 `unsupported`; the factory kit's rule D is the
independent gate — DEMO step 8); receipts referencing missing or unknown profiles (`profile:text:` nodes with one
citing record); mechanisms with no obligation they discharge; obligations with no mechanism where one is expected;
orphan findings/falsifiers (F37/NC29/NC30 exist only in computedriven at the census); duplicate semantic identities
under different registry names (`S6?`/`C-7`/`E-44`; `FAC-CONTROL-SENSITIVITY` present in the crosswalk and factory kit,
absent from the canonical ledger); status changed without a traceable transition (a token change with no
`EVIDENCE_STATE_TRANSITION`); relations whose source disappeared or no longer hashes to the recorded content (the E-51
receipt at `ba4e625`; the dangling `EVIDENCE-nc17-19-23-AFTER-efa8881.txt`); cross-subsystem terminology
inconsistency (the four status vocabularies, Q-10). A `PROPOSAL` is `{lid: proposal:<rule>:<sha256[:16]>, basis:
proposed, proposes: <relation or reclassification>, evidence: [lids], rule_sem_id}`.

## 16. Explicitly deferred (with the trigger that reopens each)

Transparency logs / SCITT / COSE receipts / Rekor (multiple writers or a verifier who cannot trust the git remote —
R2 §4); CIDs / IPLD (a cross-system consumer; a CID is derivable from our digest without re-hashing); incremental
evaluation (a rebuild that stops being seconds); bitemporal storage (a source that states valid time); the IC
reducer (G2+); WEK beyond quoted law statements (WEK code exists); an Elixir host (hex `rfc8785` needs OTP 29, this
box runs 28 — R2 §1); `POLICY` as a kind (a registry of policies appears); DSSE signing (records cross a trust
boundary); FTS / vector search (a text or embedding query G0 must answer).

## 17. Open at freeze — none blocks G0-A

1. ~~UI library~~ — resolved the same day by D-015 once R4 landed (Cytoscape.js + dagre/ELK; measured).
2. The WRL profile mechanism with a static profile kind (§7.5): proposed to the WRL owner; the labelled adapter stands until ruled.
3. The TRVM `prim` catalog (§8.4): proposed to the TRVM lane; the labelled adapter stands until it ships.
4. The brief's missing companions (`02_RESEARCH_AGENDA.md`, `03_STACK_REPAIR_PROTOCOL.md`, source note #2): requested from GPT; their absence changed nothing above that a delivered copy could not amend by a decision entry.
5. A v2.7 delta census before G0-B (the pin moved during G-PR0; both pins are recorded).
