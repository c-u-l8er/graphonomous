# Ingestion contract — the invariant factory canonical ref (`CLAIM_LEDGER.json` + `mosaic/*`)

**State:** DESIGNED 2026-09-02 (no code). Census detail (dangling witnesses, id regexes per prefix) pending R7A.

## Pin

| | value |
|---|---|
| repository | bare `~/.invariant-factory/canonical.git`; **ref** `refs/heads/invariant-canonical` |
| revision at snapshot | `d217ee2` (INV-R9.4, `_round.id = INV-R9.4`, `_round.date = 2026-08-26`) |
| read method | `git show <oid>:<path>` only — never the stale worktree `wt-r9` (behind the ref, locally modified) |
| files | `CLAIM_LEDGER.json`; `mosaic/{evidence,assumptions,arguments,sources,objectives,occupancy,operations,embodiment,factory,defeaters}.json`; `mosaic/receipts/*.json` (20); `mosaic/derived/*.json` (DERIVED — read for cross-checks, never as facts) |
| authority | AUTHORITATIVE; promotion finality is the ref itself (`scripts/factory-station.mjs`, compare-and-swap on the ref); a tag `INV-R9.4` is the immutable revision identity |

## Records yielded

| Source element | Kind | Logical id | Notes |
|---|---|---|---|
| document | `REGISTRY` | `registry:factory-ledger@INV-R9.4` | `_statuses` (8) become the registry's vocabulary; `_settled.statuses` (5) is a **policy** attribute of the registry, not a fact about claims |
| `claims[i]` (208) | `CLAIM` | `claim:factory:<claim_id>` | prefixes seen: FAC 40 · FED 38 · MOS 29 · EMB 22 · ASR 19 · LED 17 · IMPACT 9 · TAX 6 · EVID 5 · ESC 4 · INC 3 · LINEAGE 3 · SUPPORT 3 · MEDIATION 3 · REPRO 2 · ADMISSION 2 · TERM/CONTROL/RECEIPT 1 each |
| `status` | `evidence_state` (vocabulary `factory-ledger`) | — | PROVED 52 · DECLARED 71 · OPEN 46 · REFUTED 19 · KNOWN 7 · PROVISIONAL 7 · CONDITIONAL 3 · MEASURED 3 at snapshot |
| `obligation` (`universal_affirmation` · `universal_refutation` · `existence` · …) | attribute on the claim | — | the logical shape the support must establish — kept separate from status exactly as the ledger does |
| `evidence_kind` (`deductive_proof` · `counterexample` · `constructive_witness` · …) | attribute; joins `mosaic/evidence.json#kinds` | — | the kind's `means`/`does_not_mean` text becomes the `WITNESS.kind` definition node `evidence-kind:<name>` |
| `witnesses[]` (`scripts/check-federation-invariants.mjs §1`) | `WITNESS` + `WITNESSES` edge (`outcome` from status: PROVED/REFUTED → pass of *that* obligation; OPEN → not-run/unknown) | `witness:factory:<path>#<section>` | path resolved against the ref's tree; `§n` kept as `anchor`; missing file → `DANGLING_WITNESS` |
| `assumptions[]` | `ASSUMPTION` + `ASSUMES` | `assumption:factory:<id or sha256(text)[:16]>` | ids that resolve in `mosaic/assumptions.json` link to that record; free text is minted with `unnormalized: true` |
| `implementation_binding: cell:NN` | `BINDS` to `cell:NN` | — | join with the cells adapter; a binding to a cell absent from `cells.json` is a fault |
| `prior_art` | `CITES` → `SOURCE_LOCATION`/external citation node | `cite:<sha256(text)[:16]>` | `mosaic/sources.json` records (`SRC-…`, with `hypotheses[]` and `used_by[]`) become `CITED_RESULT` attributes on the same node when the ids match |
| `finding`, `statement`, `evidence` (prose) | attributes | — | verbatim; never parsed for facts |
| `last_verified`, `refutation_scope` (`timeless`) | attributes | — | dates are strings from the source, not timestamps minted by the adapter |
| `mosaic/receipts/INV-R*.json` | `RECEIPT` + `ROUND` | `round:factory:<INV-Rx>`, `receipt:factory:<file>` | round receipts bind derived counts; their digests are checked, not recomputed here |
| `mosaic/arguments.json`, `defeaters.json`, `objectives.json` | `CLAIM` sub-kinds by attribute (`argument`, `defeater`, `objective`) with `SUPPORTS`/`ATTACKS` edges as the records state them | `argument:factory:<id>` … | shapes pending R7A |
| `mosaic/occupancy.json#kind_vocabulary.declared` | the cells' kind vocabulary (read, never copied) | — | the same rule `_invariants/build/build.mjs` follows |

## Faults specific to this source
`STATUS_OUTSIDE_VOCABULARY` (a claim status not in `_statuses`) · `SETTLED_WITHOUT_WITNESS` (a settled status with an
empty `witnesses[]` — reported as a fact about the source; the factory's own gate decides whether it is legal) ·
`DANGLING_CELL_BINDING` · `DANGLING_WITNESS`.

## Determinism
Records sorted by lid; the ref OID and the blob OIDs of every file read enter the snapshot; the worktree is never consulted.

## Measured deviations (G0-F as built, 2026-09-03 — `adapters/factory.mjs` at pin `d217ee29a3322c68db0d43be47491f0e9d4fbc64`; where this section and the table above differ, D-056 wins)

**State:** IMPLEMENTED + TESTED (`test/factory.test.mjs`, `test/factory_certificate.test.mjs`); scope is exactly D-056 (1)–(7).
Numbers are read from `projections/multi` (root `root-48ac3e32…`, `projections/EVIDENCE.md` § multi).

| designed above | as built | why |
|---|---|---|
| REGISTRY lid `registry:factory-ledger@INV-R9.4` | `registry:factory:factory-ledger@INV-R9.4` | the lid grammar is `<prefix>:<namespace>:<local>`; the namespace is the SOURCE (`factory`, as every `claim:factory:*` already is), the local keeps the contract's name and the `_round.id`. The tree registry `registry:factory:invariant-factory@d217ee29a332` (from the snapshot) stays the `registry` of every `loc:factory:` location, whichever adapter cited it |
| `evidence_kind` joins `mosaic/evidence.json#kinds`, whose `means`/`does_not_mean` become a `WITNESS.kind` definition node `evidence-kind:<name>` | `evidence_kind` is a claim ATTRIBUTE; `mosaic/evidence.json` is NOT read | instruments and evidence-kind definitions have no role under frozen v0 (D-050, D-056 deferred list); `G0F_V1_OBLIGATION.md` §2 item 5 |
| `witness:factory:<path>#<section>` with `§n` kept as `anchor`; missing file → DANGLING_WITNESS | lid as designed; the section is the attribute `section`, and the `§n` is RESOLVED to the line of its section BANNER (`// ═══ §1 · …`, `*   §1  …`) — attribute `line`, `LOCATED_IN loc:factory:<blob>:<path>#L<n>` (precision `line`); a `§n` with no banner would keep the raw `§n` as a heading-precision fragment + HEADING_WITHOUT_NUMBER (0 at this pin; 48/48 resolved) | D-056 (2): "LOCATED_IN at the pinned blob with `§n` anchors"; the crosswalk's markdown heading resolver does not apply to `.mjs` banners, so the factory has its own (`sectionLine`), covered by a synthetic test |
| `WITNESSES.outcome` from status: PROVED/REFUTED → pass of that obligation; OPEN → not-run/unknown | `outcome: "pass"` for every status in the registry's own `_settled.statuses` (PROVED, CONDITIONAL, REFUTED, KNOWN, MEASURED — 118 assertions), `outcome: {unknown: "not-stated"}` for DECLARED/OPEN/PROVISIONAL (151); every assertion also carries `raw_status`, `outcome_basis: "status"`, `settled`, `cited_as`, `obligation` | the settled predicate is the registry's declared policy (its `_settled` comment explains why it is not checker-local); "not-run" would assert a fact the source does not state, so the `unknown` enum's `not-stated` is used. The rule `supports(W, C)` derives 118 facts from it |
| `assumption:factory:<id or sha256(text)[:16]>`; free text `unnormalized: true` | typed refs → `assumption:factory:ASM-*` (29 nodes, from `mosaic/assumptions.json`, 46 refs + the 51 inverse `cited_by` statements as second assertions on the same ASSUMES propositions: 45 two-sided, 6 `cited_by`-only, 1 `assumption_refs`-only); free text → the crosswalk's **`text` namespace** `assumption:text:<encoded or h.hash>` (97 nodes, 110 occurrences) | D-056 (3): a per-registry prefix would forbid the cross-registry co-reference D-030 wants; measured 0 sentences shared verbatim at this pin (105 candidates) |
| `cell:NN` binding → BINDS; absent from cells.json → fault | as designed: 54 BINDS → 7 `cell:cells:NN` (node attrs exactly the crosswalk's `{num, registry_hint: "cells"}` so `cell:cells:27a` folds without CONTRADICTION); DANGLING_CELL_BINDING 0; the 122 PATH bindings (81 with trailing prose) stay the attribute `implementation_binding` with `binding_form` ∈ cell / path / path-with-prose | D-056: no location invented from prose (81 UNSUPPORTED_SOURCE_FORM avoided) |
| `prior_art` → CITES → `cite:<sha256(text)[:16]>` external citation node; SRC records become `CITED_RESULT` attributes | `SRC-*` ids lifted from `prior_art` (26 mentions), from `evidence_qualifiers.citation_ref` (8) and the inverse `used_by` (33) → `CITES claim → artifact:factory:SRC-*` (45 propositions, 20 with 2–3 assertions; 24 ARTIFACT nodes with `role: "cited-result"` and the sources.json record as attrs); prose prior_art without an SRC id stays an attribute; unknown SRC → UNRESOLVED_LINK (2: `SRC-MUTATION-ADEQUACY`); `cites_bound` → `CITES claim → claim` (1, `needs: upper`) | `cite:` is not a prefix of the lid grammar and `CITED_RESULT` is not a role; ARTIFACT is (D-056 (6)) |
| `round:factory:<INV-Rx>`, `receipt:factory:<file>`; receipts bind derived counts | as designed: 20 RECEIPT (`receipt:factory:mosaic/receipts/<f>.json`; attrs receipt_version, transition, parent, candidate, invariants, decision) `PRODUCED_BY` their `transition.to` ROUND (21 rounds incl. the INV-R4.1 `from`); 106 `CLAIM PRODUCED_BY ROUND` from `invariants.established`; **0 `ROUND SUPERSEDES ROUND`** — the parent chain is lineage, not replacement (D-037), and the one non-null `lineage.supersedes` (INV-R8-RECOVERY) is prose that itself says "not superseded in the ledger sense" → UNRESOLVED_LINK; `retyped` (26 prose) deferred; digests checked nowhere here (contract: never recomputed) | D-056 (7) |
| arguments / defeaters / objectives as CLAIM sub-kinds with SUPPORTS/ATTACKS | NOT emitted | no v0 pair (`SUPPORTS` has no `[CLAIM, CLAIM]`; `ATTACKS` reaches only CLAIM/MECHANISM) — `G0F_V1_OBLIGATION.md` |
| `occupancy.json#kind_vocabulary` read, never copied | not read | nothing in scope consumes it |
| faults: STATUS_OUTSIDE_VOCABULARY, SETTLED_WITHOUT_WITNESS, DANGLING_CELL_BINDING, DANGLING_WITNESS | those four (0 / 8 / 0 / 0 from the factory) plus, measured: UNRESOLVED_LINK 14 (10 `supersedes` prose — including the 2 prose values that mention a resolvable id, never parsed per D-021 —, 1 `superseded_by` prose, 2 SRC, 1 receipt lineage prose), HEADING_WITHOUT_NUMBER 0, DANGLING_SUPERSESSION 0, SCHEMA_UNEXPECTED_FIELD 0 (every claim key is one of the 24 the census saw); the two new codes entered `schemas/fault.schema.json` (`build_schemas.mjs`) | D-056 expected ~11 UNRESOLVED_LINK; the difference is the 2 prose-with-id values and the receipt lineage line |
| — | `supersedes` / `superseded_by`: exact id → ONE `SUPERSEDES claim → claim` proposition with an assertion per stating field (`stated_by`, `raw_token` on the assertion; relation attrs `{}`): 14 relations, 8 two-sided; an id-shaped token absent from the ledger → DANGLING_SUPERSESSION (0) | D-029 / D-056 (5) |
| — | `evidence_qualifiers.applicability.local_bindings` objects keyed by phrases ("join tree", "the model provider", …) are re-encoded as `{keyed_entries: [{key, value}]}` in source order (3 claims, 5 entries, 4 phrase keys) — the attrs grammar `^[A-Za-z_][A-Za-z0-9_]*$` cannot spell them | a structural re-keying, not a normalization of content |
| — | the 4 claims the crosswalk stubs (`claim_id`, `registry_hint: "factory-ledger"`, `present_in_pinned_ledger: true`) fold with the ledger record: the adapter emits the same `claim_id` and `registry_hint` and omits `present_in_pinned_ledger`; 0 CONTRADICTION | D-056 |
| files read | `CLAIM_LEDGER.json`, `mosaic/assumptions.json`, `mosaic/sources.json`, `mosaic/receipts/*.json` (20), `opensentience.org/_invariants/data/cells.json`, and every witness path (45 files, bytes read only for the 12 with `§` sections, blob ids for all) — 66 files pinned by `g0 snapshot --factory-ledger` (`factoryFiles()`); `mosaic/{evidence,arguments,defeaters,objectives,occupancy,operations,embodiment,factory}.json` and `mosaic/derived/*` are NOT read (embodiment.json is pinned only because a claim cites it as a witness) | D-056 scope |
