# `graphonomous.semantic.v1` — PROPOSAL from the G0-F measurement (D-050, D-056; 2026-09-03; no code)

**Status: PROPOSED, not built.** `graphonomous.semantic.v0` is a frozen contract (D-050). The factory ledger's core sealed
under it unchanged (`projections/multi/world`: `sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea`,
2,707 objects, 1,574 relations, every `rel-`/`rev-` kernel-minted at WRL `b072db0`). What did NOT fit — and was therefore
left out of `adapters/factory.mjs` rather than forced — is the factory's **argument / defeater / incident** layer plus five
registries that have no role. This document is the smallest new obligation that would carry it, with the counts R12
measured at `d217ee2`, and the non-regression statement D-050 requires.

## 1 · What v0 refused, by count (R12 §3, §5)

| factory element | records | what it needs | v0 says |
|---|---|---|---|
| `mosaic/arguments.json` `ARG-*` | 27 (roles: domain_coverage 15 · citation_scope 8 · premise_mediation/defeater_elimination/cited_lemma/proposition_subsumption 1 each) with `conclusion_claim` 25/25, `premise_claims` 6/6, `evidence_refs` 24 witness + 6 claim + 13 source, `assumption_refs` 23/23, `obligation_discharged` | an ARGUMENT object that SUPPORTS a CLAIM and is itself supported by witnesses/claims/sources | `SUPPORTS` allows only `WITNESS|RECEIPT|FINDING → CLAIM|LAW`; **no `[CLAIM, CLAIM]`** and no ARGUMENT role |
| `mosaic/defeaters.json` `DEF-*` | 68 (undercutting 46 · undermining 19 · rebutting 3); `target_type`: consumption_rule 34 · argument 12 · assumption 6 · evidence 5 · receipt 5 · claim 3 · claim_evidence 3 | a FALSIFIER-like object that ATTACKS an argument / assumption / instrument / receipt / consumption rule | `ATTACKS` allows only `FALSIFIER → CLAIM|MECHANISM`: **6 of 68** fit (the claim-targeted ones), **62** have no pair |
| `mosaic/defeaters.json` `incidents` `INC-R<n>-*` | 46 (`revision_found`, `fixed_by`, `defeater_ref` 46/46, severity unsound 32 · stale 11 · latent 3, all `status: fixed`) | FINDING opened/closed by a ROUND or RECEIPT; `FINDING FALSIFIES CLAIM` for the 1 claim-subject incident | fits the *pairs* (`ROUND|RECEIPT OPENS|CLOSES FINDING`) but is a **second FINDING semantics** beside the crosswalk's open-findings sentences — measure before merging (D-056: deferred) |
| `mosaic/evidence.json` instruments `INS-*` | 12, with `assumption_refs` 17/17; `kinds` 11 with `means`/`does_not_mean` | an INSTRUMENT (or DEFINITION of an evidence kind) that a witness is TESTED_UNDER / MEASURED_BY | no role; `DEFINITION`/`PROFILE` are semantically wrong and their pairs do not reach a witness |
| `mosaic/objectives.json` `SO-*` 5, `EVAL-*` 4, `H1–H7` | 16 | an OBJECTIVE / EVALUATOR / HARD_CONSTRAINT vocabulary | no role |
| `mosaic/occupancy.json` `OCC-*` | 3 rules, each naming a claim | a rule object → CLAIM | no role |
| `mosaic/operations.json` matrix, `mosaic/embodiment.json` `CAP-SYNTHETIC-*` | 6 ops; 4 capabilities (all synthetic) | — | no role |
| `assumption.discharge_state.evidence_refs → claim` | 3 claim + 1 mosaic ref | ASSUMPTION → CLAIM "discharged by" | **no kind** in either direction |
| receipts `invariants.retyped` | 26 prose lines (`ID — FROM to TO. …`) | `EVIDENCE_STATE_TRANSITION STATE_TRANSITION_OF CLAIM` + `PRODUCED_BY ROUND` | fits the pairs, but the source is prose (D-021: not parsed) — a **source repair**, not a profile change |
| `mosaic/derived/*` | 4 files | — | DERIVED, never facts (contract) |

Everything else in the ledger (208 claims, 87 witnesses, 269 witness citations, 29 typed + 110 free-text assumptions,
54 cell bindings, 14 supersessions, 46 citations, 20 receipts / 21 rounds, 106 established links) sealed under v0.

## 2 · The smallest new obligation

Ordered by how much of the refused layer each item admits. v1 = v0 plus exactly these; nothing in v0 is removed or
re-typed.

1. **New role `ARGUMENT`** (27 objects) and the pairs `SUPPORTS [ARGUMENT, CLAIM]` (25 `conclusion_claim`),
   `CITES [ARGUMENT, *]` (already `*→*`; 6 premise claims, 13 sources, 24 witnesses — the witness refs may equally be
   `WITNESSES [WITNESS, ARGUMENT]`, one more pair), `ASSUMES [ARGUMENT, ASSUMPTION]` (23). Rejected alternative: modelling
   ARG-* as a CLAIM sub-kind by attribute (the contract's design) — refused because it would need `SUPPORTS [CLAIM, CLAIM]`,
   which changes what every existing CLAIM→CLAIM edge could mean.
2. **New role `DEFEATER`** (68 objects; `kind` ∈ undercutting/undermining/rebutting as an attribute) and the pairs
   `ATTACKS [DEFEATER, CLAIM]` (3 + 3 claim_evidence), `ATTACKS [DEFEATER, ARGUMENT]` (12), `ATTACKS [DEFEATER, ASSUMPTION]`
   (6), `ATTACKS [DEFEATER, WITNESS]` (5 evidence), `ATTACKS [DEFEATER, RECEIPT]` (5). The 34 `consumption_rule` targets
   and the 12 argument `target` dicts (`{file, revision, digest, section|symbol}`) are code locations: `ATTACKS [DEFEATER,
   SOURCE_LOCATION]` would carry them, or `LOCATED_IN` from the defeater with the rule as an attribute — decide from a
   census of those 39 dicts (digests not yet re-checked at the pin). Reusing `FALSIFIER` for DEF-* was considered: a
   falsifier in v0 is an executable construction that falsifies a claim; 62 of these target something other than a claim,
   so the word would be stretched.
3. **Pair `CLOSES [ROUND, FINDING]` for incidents** — already in v0; the obligation is semantic, not structural: declare
   that a FINDING may come from an incident registry (attribute `finding_source: "incident"`) and measure whether the two
   FINDING populations (12 crosswalk sentences, 46 factory incidents) ever need to co-refer (at this pin they cannot —
   different namespaces, `inv`/`computedriven` vs `factory`).
4. **New kind `DISCHARGED_BY [ASSUMPTION, CLAIM]`** (3) — or reuse `SUPPORTS [CLAIM, ASSUMPTION]`; the latter widens
   SUPPORTS' target set, so the new kind is the smaller change.
5. **New role `INSTRUMENT`** (12) with `TESTED_UNDER [WITNESS, INSTRUMENT]` and `ASSUMES [INSTRUMENT, ASSUMPTION]` (17) —
   only if a consumer needs instruments as objects; otherwise carry `instrument` as a witness attribute (0 witness
   citations at this pin name an instrument, so this is the least urgent).
6. Objectives, occupancy, operations, embodiment: **no role proposed.** They describe the factory's process, not its
   claims; carry them as REGISTRY attributes (the `_registries` table already names the files) until a query needs them.

Total new surface of the recommended v1: **2 roles (ARGUMENT, DEFEATER), 1 kind (DISCHARGED_BY), 9 endpoint pairs**, and
one policy note (incident-sourced FINDING). Items 5–6 are explicitly NOT in the smallest obligation.

## 3 · Migration / non-regression statement (D-050)

- **Every v0 golden identity is unchanged by construction**, because v1 is a **new profile id**. WRL selects the row by
  `profile_id` (WRL-P0, D-047); the v0 row `V2_PROFILES["graphonomous.semantic.v0"]` at `b072db0` is not edited. The golden
  worlds `sem-0f952f03…` (baseline) and `sem-3ae051cf…` (historical), their `rev-`/`rel-` sets in
  `projections/{baseline,historical}/world/identities.json`, and the multi world `sem-b8d82827…` remain the v0 receipts;
  a v1 submission of the same projection mints a *different* `sem-` (the `profile_id` is in the sealed bytes) and that is
  the intended behaviour, not a regression — the statement lids (cross-world proposition identity, D-049 §1) are identical
  in both worlds.
- **Ingestion is additive.** `adapters/factory.mjs` would gain the argument/defeater/incident emitters behind the same
  `params.adapters` switch; the D-056 core (208 claims, …) is emitted identically, so a v1 projection's node/relation set is
  a superset of the v0 one and every v0 relation lid reappears unchanged (lids do not carry the profile).
- **Guard to add when built:** `test/wrl_world.test.mjs` "declaration reconcile" runs for both profile ids; a new test seals
  the multi projection under v0 and v1 and asserts the v0 `sem-`, the v0 `rev-` set, and every statement lid are unchanged,
  and that the v1 world contains exactly the v0 relations plus the counted additions (25 + 6 + 13/24 + 23 SUPPORTS/CITES/
  WITNESSES/ASSUMES from arguments; 3+3+12+6+5+5 ATTACKS; 3 DISCHARGED_BY; 46 incidents with 46 OPENS + 46 CLOSES).
- **What must NOT happen**: no edit to the v0 row, no re-typing of an existing v0 pair, no lid change for any existing
  object, no parsing of `retyped` prose (that is a source repair filed with the factory: write `{claim, from, to}`).

## 4 · Why this is a proposal and not a build

D-056 decided the v0-safe core; the sealing result above is that decision passing its own test. The refused layer needs a
WRL row (an owning-layer change, the WRL-P0 protocol) and a ruling on whether ARGUMENT is a role or a CLAIM sub-kind —
both are for GPT adjudication, not for an adapter to decide by emitting.
