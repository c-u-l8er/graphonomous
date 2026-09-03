# G0-F measurement note — is `graphonomous.evidence.v0` justified? (D-053, 2026-09-03)

**Recommendation: NOT YET.** Two authoritative source families (the crosswalk + evidence_state pair and the invariant
factory ledger) now share one projection, one evaluation and one WRL-sealed semantic world, and **no concrete query,
identity or certificate requirement of this round needed anything the projection root + semantic-world separation does
not already give.** The evidence profile stays deferred; the measured reasons are below, and the one place a later round
might change the answer is named in §4.

Every number is read from `projections/multi` (root `root-48ac3e32…`, snapshot `snapshot:g0:multi-ba4e625-d217ee2`,
`projections/EVIDENCE.md` § multi) or from `test/factory.test.mjs` / `test/factory_certificate.test.mjs`.

## 1 · What the two families share (the assertion/provenance shape is one shape)

| concept | crosswalk / evidence_state | factory ledger | shared? |
|---|---|---|---|
| **assertion record** `{subject, location, asserted_by, precision, attrs}` | 1,272 assertions, 2 registries | 1,998 assertions, 1 registry (one lid for 4 files: ledger, assumptions, sources, 20 receipts) | **yes** — one schema, one lid rule `asrt:g0:<subject>:<location>`; the fold never needed a source-specific branch |
| **source location** at a pinned blob with a fragment | JSON pointers into the two package files; `L<n>` from markdown headings; file | JSON pointers into 23 factory files; `L<n>` from `§n` comment banners (48/48 resolved); file | **yes** — same record, same precision vocabulary (`pointer` 1,033 / `line` 48 / `file` 59 on the factory side); the tree registry of a location is a function of where the file is (`registry:factory:invariant-factory@d217ee29a332` on every `loc:factory:` whichever adapter cited it) |
| **registry as `asserted_by`** | `registry:crosswalk:<version>`, `registry:evstate:<version>` | `registry:factory:factory-ledger@INV-R9.4` | **yes** — the same lid shape; the cross-source test (a) reads nothing but `asserted_by` |
| **evidence_state on the assertion**, folded onto the node | `{token, vocabulary: "crosswalk"}` (56 claims) | `{token, vocabulary: "factory-ledger"}` (208 claims) | **yes in shape, never in vocabulary** (Q-10): two enumerations on one field, 0 `evidence_state` conflicts in the fold |
| **witness → claim with an occurrence `outcome`** | `outcome: {unknown: "not-stated"}` on 105 propositions | `outcome: "pass"` (118, from a settled status) or `{unknown: "not-stated"}` (151) with `raw_status`, `outcome_basis: "status"`, `obligation` | **yes** — `supports(W, C)` derives 118 facts from the factory through the rule that reads `aattr(A, outcome, "pass")` unchanged |
| **two statements of one proposition = one relation, two assertions** (D-029) | receipts cited as sensitivity + repair (148 relations with 2 assertions at the baseline) | `supersedes`/`superseded_by` (8 of 14), `assumption_refs`/`cited_by` (45 of 52), `prior_art`/`citation_ref`/`used_by` (20 of 45) | **yes** — the mechanism needed no extension; it also exposed 7 one-sided `cited_by`/`assumption_refs` statements and 6 one-sided supersessions as facts about the source |
| **the raw citing token** | `raw_token`, `source_id`, `cited_as` | `raw_token`, `cited_as`, `stated_by` | **yes** — `stated_by` (which field of the record made the statement) is the one occurrence attribute the factory added; it is the same role `role`/`listed_as` play for the crosswalk |
| **executed flag** | `executed` on 5 receipt-witness assertions and on typed promotions | — (the ledger has no executed flag; PROVED *means* "an executable check reproduces it here", a status, not an occurrence) | **source-specific** — `has_exec_receipt` derives 10 facts, all crosswalk-side; the factory contributes none and claims none |
| **typed promotion / transition** | 14 `EVIDENCE_STATE_TRANSITION` with `from_token`/`to_token`, receipts, adjudications | `retyped` (26 prose lines in receipts) — DEFERRED, prose | **source-specific**; the factory's transitions are prose at this pin |
| **adjudication** | 13 `ADJUDICATION` nodes (GPT v1–v4 sections) | `readjudicated {by, method, authority_transferred}` carried as a claim ATTRIBUTE (43) | **source-specific in shape**: the crosswalk's adjudication is a document section, the factory's is a typed field naming a round; both stay observed and neither needed a shared object |
| **round / receipt** | `round:computedriven:R0.8` opening findings; `receipt:sha256:<hash>` verified at the pin | `round:factory:INV-R*` (21) and `receipt:factory:<path>` (20) with `PRODUCED_BY`; 106 `CLAIM PRODUCED_BY ROUND` | **shared kinds, source-specific identity rule** — the crosswalk names a receipt by content hash, the factory by path in a pinned tree; both are pinned identities and both reach `PRODUCED_BY` under v0 |

## 2 · What is source-specific and stayed that way

- The **outcome basis**: the factory's `outcome` is derived from a *status* under the registry's own `_settled` policy;
  the crosswalk states no outcome at all. Both are honest and both are on the assertion, so a reader can tell them apart
  by `outcome_basis`. No profile is needed to keep them apart — the assertion record already does.
- The **obligation axis**: 9 logical shapes (`universal_affirmation`, …) on the factory versus S1..S6 safety obligations
  on the crosswalk (`obligation:inv:*`); never merged, never needed to be (`obligation` rides on the factory's WITNESSES
  assertion and as a claim attribute).
- **Typed provenance fields** (`imported_from`, `readjudicated`, `evidence_qualifiers`, `refutation_scope`) are attributes
  of the factory claim; the crosswalk's analogues (`history`, `promoted_in`, `adjudicated_at`) are attributes of its claim.
  A shared evidence profile would have to choose one vocabulary or carry both — carrying both is exactly what the node's
  `attrs` already do, at no identity cost (the semantic world hashes attrs; provenance vocabulary differences move `sem-`
  only when a claim's *attrs* change, which is the intended behaviour).

## 3 · Requirements of this round, and where each was met

| requirement | met by | evidence profile needed? |
|---|---|---|
| (a) one node per shared id with assertions from both registries, no CONTRADICTION | projection fold (`lib/project.mjs`), 5 folded nodes, 0 faults | no |
| (b) `S4` / `F1` / `INC-` collisions never meet | lid namespaces (`obligation:inv:S4` vs `claim:factory:FED-Q3-HYP-S4`) | no |
| (c) same-looking claims stay distinct (E-40 / EMB-CUT-EMPTY; E-41 / TAX-RELATIONAL-2) | identity is the source id, never the text; the only join is the crosswalk's own `CITES` | no |
| (d) one proposition, two assertions | D-029 relation identity; measured 0 cross-registry, 73 intra-factory | no |
| (e) verbatim sentence co-reference across registries | the `text` namespace with `Emitter.lid` (0 shared at this pin, 105 candidates) | no |
| (f) new fault kinds as facts, not normalization | `SETTLED_WITHOUT_WITNESS` 8, `STATUS_OUTSIDE_VOCABULARY` 0, `UNRESOLVED_LINK` 14 — fault records in the projection root | no |
| certificate sensitivity (new source → new commitment, root, certificate; old certificate still verifies; drop/reorder refusals) | `snapshotCommitment` over the source-identity SET + the projection root (`test/factory_certificate.test.mjs`, 7 tests) | no |
| sealing under frozen v0 | `sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea`, 2,707 objects, 1,574 relations, 1,574/1,574 kernel `rel-`/`rev-` | no — assertions are outside the world by design (D-049 §5) and nothing asked for them inside |
| queries: "which claims does the factory say are superseded", "which factory witnesses pass" | G0-E `superseded` 13, `supports` 118 over base facts `asrt`/`aattr` | no |

The one identity fact worth stating plainly: **adding 1,998 assertions and 22 faults moved the projection root and the
certificate; it did not move a single baseline `rev-`** — the two frozen worlds still seal to their golden `sem-` because
provenance occurrence is outside semantic identity (test/wrl_world.test.mjs (8) on the unchanged pins, and the multi
world contains the baseline's 588 statement lids unchanged). That separation is the argument D-053 made, and it held
under a second producer.

## 4 · What would change the answer

An evidence profile earns its place when a consumer needs a **sealed identity over provenance itself** — for example a
third party wanting to cite "the set of assertions that back claim X at pin P" by one `sem-`-class id, or a TRVM nest
bundle wanting to name the evidence world separately from the statement world. Nothing in G0-F asked for that: the
projection root already names the whole provenance set content-addressably, and the certificate binds it. Revisit when
(i) a second consumer of provenance identity exists, or (ii) a source family's provenance shape genuinely cannot be
carried on the assertion record (none found: the only re-encoding needed anywhere was `keyed_entries` for four
phrase-keyed objects, an attrs grammar matter, not a provenance one).

**Deferred with reasons: the assertion record + projection root are the evidence layer; a profile would add an identity
nobody is consuming yet.**
