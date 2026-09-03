# Ingestion contract — `CROSS_REGISTRY_CLAIM_MAP.json` (package v2.6) + `evidence_state.json`

**State:** DESIGNED 2026-09-02 (no code). Source of record for the first adapter (G0-B).

## Pin

| | value |
|---|---|
| repository | `invariant-r10/` (own git repo) |
| revision read for this contract | `699fbc2859ef` (HEAD at snapshot); package content identical to the v4 return commit `0270e81` for `package-v2.6/` |
| files | `package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json` (sha256 recorded at ingest), `package-v2.6/evidence_state.json` |
| self-declared status | crosswalk header: `"DRAFT — preserves registry origin; nothing merged into CLAIM_LEDGER.json"` — carried onto every record as `registry_status: DRAFT` |

The adapter reads `git rev-parse HEAD` **and** hashes both files before parsing; both identities enter every record's
provenance. Reading a working tree whose HEAD differs from the pinned OID is a fault (`SOURCE_MOVED`), not a warning.

## Records yielded

| Source element | Normalized kind | Logical id | Notes |
|---|---|---|---|
| top-level document | `REGISTRY` | `registry:crosswalk@<crosswalk_version>` | `crosswalk_version` = `r10-pre-v2.6-2026-09-02-v3-adjudication-applied` |
| `records[i]` | `CLAIM` | `claim:crosswalk:<record_id>` | 56; `record_id` matches `^E-\d{2}[abc]?$` |
| `semantic_obligations` keys S1…S5 | `OBLIGATION` (axis `safety`) | `obligation:S1` … `obligation:S5` | names from the map values |
| `semantic_obligations` CROSS / DEF / REPR / COR | not obligations: `LAW` (cross-cutting), `DEFINITION`, `REPRESENTATION` categories used by the `relation` mapping below | — | COR appears in the vocabulary but on no record |
| `liveness_candidates["L1?"]` | `OBLIGATION` (axis `liveness`, promotion `candidate`) | `obligation:L1?` | witnesses → WITNESS nodes; `fairness`/`temporal_eventuality` kept as attributes |
| `factory_candidates["FAC-CONTROL-SENSITIVITY"]` | `OBLIGATION` (axis `factory-epistemic`, promotion `candidate`) | `obligation:FAC-CONTROL-SENSITIVITY` | `generic_rules_v3` A–H as attributes |
| `resolved_candidates["S6?"]` | `OBLIGATION` (axis `safety`, promotion `resolved-into`) | `obligation:S6?` | plus relation `REDUCES_TO obligation:S1` with the quoted disposition as `basis: observed` |
| `r0_8` | `ROUND` | `round:computedriven:R0.8` | `status`, `f35_status`, `open_findings[]` → FINDING nodes `finding:F35`, and unnamed findings minted as `finding:R0.8:open:<n>` with `unnamed: true` |
| `r0_8.closed_by_adjudication_v3[]` | `FINDING` + `CLOSES` relation from `adjudication:gpt-v3` | `finding:F31` … parsed by `^F\d+` | the profile in the sentence becomes `SCOPED_BY` a PROFILE |
| `promotions[]` | `EVIDENCE_STATE_TRANSITION` | `transition:crosswalk:<record_id>:<promoted_in>` | `from`/`to` (Q-02 truncation flagged), `sensitivity_witness` → RECEIPT (`sha256`, `type`), `pre_fix_witness`/`repair_witness` → RECEIPT, `runtime` → ARTIFACT (image digest parsed when present) |
| `witness_paths[]`, `receipts[]` | `WITNESS` / `RECEIPT` | `witness:<root-id>:<normalized-path>` | roots in order: package dir, lane root, `computedriven@efa8881`; fragment `#X` kept as `anchor`; unresolved → `DANGLING_WITNESS` fault |
| `scope_profile`, `trust_profile`, `conditions[]` | `PROFILE` (scope/trust) / `ASSUMPTION` | `profile:text:<sha256(normalized text)[:16]>` | `unnormalized: true` (Q-05) |
| `source_ids[]` | `SOURCE_LOCATION` (file-level) + `MECHANISM` when the id carries a code symbol after the path | `loc:<source_registry>:<path>` · `mechanism:<repo>:<symbol>` | symbol = last whitespace-separated token when the first token ends in `.rs`/`.ex`/`.mjs`/`.py` |
| `derivation_links[]` | `DERIVES_FROM` when the item matches `^E-\d{2}[abc]?$`; otherwise an `UNRESOLVED_LINK` fault carrying the text | — | Q-01 |
| `split_from` | `SPLIT_FROM` | — | E-13 → a/b/c, E-50 → a/b; the parent becomes a `CLAIM` with `superseded: true` if absent from `records` |
| `adjudication_v2_6`, `adjudication_v3`, section citations in text (`GPT v3 §1`) | `ADJUDICATION` | `adjudication:gpt:<v>:<section>` | text citations are parsed by the regex `GPT v(\d) §(\d+(?:–\d+)?)`; parse failures are faults, not omissions |

## Relation mapping (observed, from the `relation` field)

| `relation` value | edge | from → to |
|---|---|---|
| `direct` | `STATES` | claim → obligation |
| `mechanism` | `IMPLEMENTS` | claim → obligation |
| `corollary` | `DERIVES_FROM` | claim → obligation |
| `definition` | `DEFINES` | claim → obligation (or the DEF category) |
| `representation` | `REPRESENTS` | claim → obligation |
| `cross-cutting` | `CROSS_CUTS` | claim → LAW category |

Every edge carries: `basis: observed`, `asserted_by: registry:crosswalk@…`, `source_location: <file>#/records/<i>/relation`.

## Evidence state

`evidence_class_token` is the current state (vocabulary `crosswalk`); `evidence_class` is its full text;
`evidence_class_token_v2_5`, `evidence_class_v2_4`, `evidence_class_before_v2_3`, `status_before_v2_3` are **historical
states** and become `EVIDENCE_STATE_TRANSITION` nodes in package order (before_v2_3 → v2_4 → v2_5 → current) with
`basis: observed` and no witness unless a `promotions[]` entry supplies one. A transition without a witness is legal
data and is what the G1 rule "promotion without sensitivity witness" is written against.

## Determinism obligations

- Output records are sorted by logical id; arrays inside records keep source order (source order is a fact) except
  where the spec declares a set (then sorted canonically).
- No timestamps, no host names, no absolute paths enter any record. The adapter's own identity (`adapter_id` =
  hash of its source file) enters the run record, not the facts.
- Two runs over the same pinned bytes must produce byte-identical normalized output; the G0-G gate shuffles input
  order and re-runs.

## Faults this adapter can emit

`SOURCE_MOVED` · `SCHEMA_UNEXPECTED_FIELD` · `SCHEMA_MISSING_FIELD` · `DANGLING_WITNESS` · `UNRESOLVED_LINK` ·
`TRUNCATED_FIELD` · `UNPARSEABLE_CITATION` · `UNKNOWN_TOKEN` (a token outside the vocabulary observed at contract time —
reported, then admitted as a new token with `first_seen` provenance) · `DUPLICATE_ID`.

## Addendum — v2.7 and the adapter as built (G0-B, 2026-09-02; D-025, D-027, D-028)

**Pins.** One adapter reads both `package-v2.6` at `699fbc2` (historical) and `package-v2.7` at `ba4e625` (baseline);
every v2.7-only field (`evidence_class_token_v2_6`, `subject_identity`, `adjudication_ref`, `adjudicator`,
`adjudicated_at`, `history_note`, `projection`, `r0_8.profile`) is optional. Six pinned trees resolve references, in
this order: the package directory and lane root of `invariant-r10`, `computedriven@efa8881`, `super@7651697`,
`TRVM@fd0df4c`, `WRL@1f4c5fd`, the factory ref `invariant-canonical@d217ee2`.

**Mapping as built** (`adapters/crosswalk.mjs`): record → `CLAIM` with `evidence_state {token, vocabulary: crosswalk}`
and history; `relation` → `STATES` / `IMPLEMENTS` / `DERIVES_FROM` / `DEFINES` / `REPRESENTS` / `CROSS_CUTS` to
`obligation:inv:S<n>` or a category node; witness paths → `WITNESS` nodes asserted at the citing pointer and
`LOCATED_IN` the pinned file; promotions → `EVIDENCE_STATE_TRANSITION` + `RECEIPT` (`sha256` verified at the pin) +
`ARTIFACT` (`subject_identity`) + `ADJUDICATED_BY`; `scope_profile`/`trust_profile`/`conditions` → `PROFILE` /
`ASSUMPTION` (text-hash lids, `unnormalized: true`); id-shaped `derivation_links` → `DERIVES_FROM`, `law:` → `CITES`
a `LAW`, prose → `UNRESOLVED_LINK`; `source_ids` → `SOURCE_LOCATION` (+ `MECHANISM` when a symbol resolves to a line),
`LAW`, factory `CLAIM`, `CELL`, `EXPERIMENT`; `r0_8` → `ROUND` with `OPENS`/`CLOSES`; `liveness_candidates`,
`factory_candidates`, `resolved_candidates` → `OBLIGATION` nodes on their axes (`S6?` `REDUCES_TO` `S1`);
`witnesses` and `projection` hashes verified; `evidence_state.json` → a DERIVED registry whose classes are
cross-checked against the crosswalk tokens (a disagreement is a `CONTRADICTION`).

**Faults the real data raises** (baseline): `UNRESOLVED_LINK` 42 · `UNSUPPORTED_SOURCE_FORM` 11 · `TRUNCATED_FIELD` 5 ·
`DANGLING_WITNESS` 2 · `AMBIGUOUS_IDENTIFIER` 1; no `CONTRADICTION`, `DUPLICATE_ID` or `SOURCE_MOVED` at either pin
(see `projections/EVIDENCE.md` for the exact counts of the shipped build).

## Addendum — G0-B.1 identity normalization (2026-09-03; D-029, D-030, D-031, D-032)

- **Relations are propositions.** Every `E.rel(kind, source, target, at, {attrs, asrt})` call names the proposition and
  the asserting location; `attrs` (relation-level) is limited to `relation_field` and the `STATE_TRANSITION_OF` from/to text (was `SUPERSEDES` until D-037, 2026-09-03: a transition moves a claim's evidence state, it does not replace the claim);
  everything about the citation — `role`, `what`, `part`, `outcome`, `executed`, `sensitivity_type`, `type`, `note`,
  `source_id`, `cited_as`, `section`, `listed_as`, `mention`, `text`, `declared`, `disposition`, `as_of`,
  `asserted_by_record`, `raw_token`, `qualified`, `resolution_basis`, `resolved_namespace`, `resolved_in` — is on the
  assertion. A receipt cited as sensitivity and repair witness of one record is one relation with two assertions.
- **Unnamed findings** are `finding:inv:h.<sha256(round lid ‖ NUL ‖ sentence)[:16]>`; the node keeps `text`, `container`.
- **Bare tokens** in `claim-ledger` records' `source_ids`: resolved only when unique across the factory ledger, the
  crosswalk record ids and the crosswalk obligation/candidate keys; `UNQUALIFIED_REFERENCE` reported; ambiguous → no edge.
- **Faults this adapter can emit** now also include `UNQUALIFIED_REFERENCE`.
- **Baseline faults after B.1:** `UNRESOLVED_LINK` 42 · `UNSUPPORTED_SOURCE_FORM` 11 · `TRUNCATED_FIELD` 5 ·
  `UNQUALIFIED_REFERENCE` 3 · `DANGLING_WITNESS` 2 · `AMBIGUOUS_IDENTIFIER` 1 (64; same at the historical pin).
