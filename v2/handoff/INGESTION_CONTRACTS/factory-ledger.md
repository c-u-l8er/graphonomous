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
