# `graphonomous.semantic.v1` — TARGET-COMPLETENESS AUDIT (2026-09-03, GPT v5 §7, D-062)

**Verdict: the candidate surface in `G0F_V1_OBLIGATION.md` was wrong in three places and is superseded by this file.
The smallest honest v1 is 3 roles / 1 kind / 10 endpoint pairs, not 2 / 1 / 9.** GPT v5 §7 anticipated exactly this
outcome — *"If the audit shows a tenth endpoint pair or another role is actually the smallest honest representation,
change the v1 proposal before freezing it"* — and it is what the measurement found.

Everything below is measured at factory pin `d217ee29a3322c68db0d43be47491f0e9d4fbc64`, read through
`git archive d217ee2 mosaic/` (the pin, never the working tree; every extracted blob re-hashed against
`git rev-parse d217ee2:<path>` — MATCH), and cross-checked against the shipped multi projection
(`projections/multi`, root `root-48ac3e32…`) so that every proposed endpoint is shown to resolve to a node **that
already exists**. Raw census: `research/R14/census.json` (282 KB, every record dumped verbatim) and `R14/CENSUS.md`.

---

## 0 · What the candidate got right, and what it got wrong

The obligation's **§1 population counts are accurate — 23 of 23 checked agree**: 27 arguments with the exact
15/8/1/1/1/1 role split; 24 witness + 6 claim + 13 source evidence_refs; 23 assumption_refs; 6 premise_claims; 25
conclusion_claims; 68 defeaters with the exact 46/19/3 kinds and the exact 34/12/6/5/5/3/3 target types; 46 incidents
with 32/11/3 severities all `fixed`; 12 instruments with 17 assumption_refs; 11 evidence kinds; 16 objectives; 3
occupancy rules; 6 operations; 4 synthetic capabilities; 26 retyped prose lines; 4 derived files; and the whole v0-safe
core (208 claims, 87 witnesses, 269 citations, 29 typed + 110 free-text assumptions, 20 receipts).

**Its errors are all in §2 — where it described the *shape* of what it had counted.** Three are material:

| # | The candidate said | Measured | Consequence |
|---|---|---|---|
| **E1** | *"the 12 argument `target` dicts (`{file, revision, digest, section\|symbol}`)"* | **Zero of 27 arguments carry a `target` key.** The 39 structured target dicts are **34 `consumption_rule` + 5 `receipt`**, all on DEFEATERs. `check-mosaic.mjs`'s `histTargetResolves` actively *refuses* a `target` on a non-historical defeater, so the candidate's shape is impossible. Its own arithmetic never closed: 34 + 12 = 46 ≠ 39. | The 12 argument-targeted defeaters are the **cleanest symbolic edge in the file** (`target_ref` = a bare `ARG-*` id), not a code coordinate. And the **5 receipt targets were never mentioned**. |
| **E2** | `ATTACKS [DEFEATER, WITNESS]` — *"(5 evidence)"* | `target_type: "evidence"` **resolves in `mosaic/evidence.json` instruments**, by the registry's own vocabulary. All 5 name an `INS-*`: `INS-KERNEL-LAWS`, `INS-MUTATION-SURFACE` ×3, `INS-PANEL`. **No witness is targeted by any defeater.** | The proposed pair does not exist. The pair that does is `ATTACKS [DEFEATER, INSTRUMENT]`, which needs the **INSTRUMENT role the candidate ranked last and called "the least urgent"**. |
| **E3** | `DISCHARGED_BY [ASSUMPTION, CLAIM]` — *"(3)"* from *"3 claim + 1 mosaic ref"* | **12 refs across 9 records: 8 witness + 3 claim + 1 source.** And **7 of the 9 records have `status: "undischarged"`** — one of the three claim refs (`EMB-CUT-EMPTY`, under `ASM-CAPABILITY-NOT-IN-PRIORS`) is on an undischarged assumption. | A `DISCHARGED_BY` minted from an `undischarged` record **would assert the opposite of what the source says**. The honest population is **2**, gated on status. |

Two further corrections, non-material to the surface but recorded: the target dicts carry **5 keys, not 4** (every one
has `digest_bits`, which the factory's gate treats as load-bearing — *"the strength of a binding is part of the
binding"*); and the claim-subject incidents number **4, not 1**.

---

## 1 · The question GPT asked first: what identity does a `consumption_rule` target supply?

**Code coordinates only. No rule identity exists.** Five falsifiable facts, all at the pin:

1. **No rule-id key exists.** Key union over all 34: `{revision:34, file:34, digest:34, digest_bits:34, section:27,
   symbol:7}`. There is no `rule`, `rule_id`, `id` or `name`, and `target_ref` is absent from all 34.
2. **The registry offers a place, not a name.** `target_types.consumption_rule.resolves_in`, verbatim: *"a rule in
   `scripts/check-mosaic.mjs` (`consume()` or a numbered section) or in `mosaic/evidence.json` consumption. R6 requires
   a revision-scoped `target` — at R5.2 this resolver returned `true` unconditionally, so the target could be any
   sentence at all."*
3. **The digest binds the FILE, not the rule.** `digestAtRevision(rev, path)` returns the *file's* sha256 from that
   revision's receipt.
4. **The locator is unbound, and the factory says so in its own gate:** *"the tree retains no historical BYTES, only
   historical digests. So the file is bound to its revision and the SYMBOL is not — the symbol check below is a
   HEAD-existence check and is labelled as one. INC-HIST-SYMBOL is that gap and it is open."* `section` is weaker still
   — it is read on exactly one line, as a non-emptiness test, and never again. The 21 distinct locators mix five
   schemes: JS identifiers (`consume`), JSON keys (`consumption`), section numbers (`§1`), prose (`§staging`,
   `§hermetic gate`), and **a CLAIM id used as a section** (`§FAC-ROUND-SERIALIZABLE`).
5. **It is not injective.** 34 defeaters → **28 distinct payloads**; `DEF-CONSUME-STATUS-INFERS-OBLIGATION`,
   `DEF-CONSUME-COVERAGE-PRESENCE` and `DEF-CONSUME-CITATION-PRESENCE` are byte-identical.

**Ruling — GPT v5 §7's own escape clause, taken:** *"If the source gives only code coordinates, the honest v1 may
preserve the target as source-addressed evidence while deferring a semantic ATTACKS endpoint."* The 34 targets become
**attributes on the DEFEATER node** (`target_file`, `target_revision`, `target_digest`, `target_digest_bits`,
`target_symbol`/`target_section`) and **no `ATTACKS` edge is minted**. No `CONSUMPTION_RULE` role is invented; `MECHANISM`
is not widened; and `LOCATED_IN` is **not** used, because a defeater is not *located at* `check-mosaic.mjs` — its target
is, and saying otherwise to make an edge appear is the abuse GPT named.

*(Recorded alternative, rejected: all 8 target files already exist as pinned `SOURCE_LOCATION` records in the multi
projection, so `ATTACKS [DEFEATER, SOURCE_LOCATION]` is mechanically available. Rejected because `SOURCE_LOCATION` is
where a statement was found, not a thing that can be attacked; an edge into it would make "34 defeaters attack a source
location" a queryable falsehood. Re-open if the factory gives consumption rules ids — INC-HIST-SYMBOL closing would be
the trigger.)*

**The receipt five are the opposite case and were missed entirely by the candidate.** Their `target.file` is
`mosaic/receipts/INV-R5.1.json`, `INV-R6.2.json`, `INV-R8.1-CONCURRENCY-OBSERVED.json`, `INV-R8.3.json`,
`INV-R9.1.json` — and the factory adapter **already mints a receipt node whose lid IS that path**
(`receipt:factory:mosaic/receipts/INV-R5.1.json`). Resolution is a lookup, not a guess: **5/5 resolve to existing
RECEIPT nodes.** So the split is not `consumption_rule` vs everything; it is **{consumption_rule} vs everything**, with
`receipt` on the symbolic side despite looking structural — exactly as `histTargetResolves` declares. `section`/`symbol`
on those five is a location *within* the receipt and stays an attribute.

---

## 2 · Every proposed endpoint, resolved against the shipped projection

Measured against `projections/multi/records/node.jsonl` (778 nodes) — these are nodes that **already exist**, so v1 adds
edges into a graph it does not have to invent:

| proposed pair | records | resolve | node kind reached |
|---|---|---|---|
| `SUPPORTS [ARGUMENT, CLAIM]` | 25 | **25/25** | CLAIM |
| `WITNESSES [WITNESS, ARGUMENT]` | 24 | **23/24 resolve; 1 minted** (see §3) | WITNESS |
| `ASSUMES [ARGUMENT, ASSUMPTION]` | 23 | **23/23** | ASSUMPTION |
| `ASSUMES [INSTRUMENT, ASSUMPTION]` | 17 | **17/17** | ASSUMPTION |
| `ATTACKS [DEFEATER, ARGUMENT]` | 12 | 12/12 (in-file) | ARGUMENT *(new)* |
| `ATTACKS [DEFEATER, ASSUMPTION]` | 6 | **6/6** | ASSUMPTION |
| `ATTACKS [DEFEATER, CLAIM]` | 3 | **3/3** | CLAIM |
| `ATTACKS [DEFEATER, INSTRUMENT]` | 5 | 5/5 (in-file) | INSTRUMENT *(new)* |
| `ATTACKS [DEFEATER, RECEIPT]` | 5 | **5/5 via `target.file`** | RECEIPT |
| `DISCHARGED_BY [ASSUMPTION, CLAIM]` | 2 | **2/2** | CLAIM |
| *(premise_claims — no new pair: `CITES` is already `[*, *]` in v0)* | 6 | 6/6 | CLAIM |
| *(argument `source` evidence_refs — `CITES [*, *]`; SRC-* are already ARTIFACT nodes)* | 13 | — | ARTIFACT |

**INS-\* has zero nodes in the projection today** (`0` node lids contain `INS-`), so the INSTRUMENT role is not
cosmetic: without it those 5 `ATTACKS` have no target at all.

---

## 3 · `WITNESSES [WITNESS, ARGUMENT]` — 23 resolve, 1 must be minted

**Corrected during implementation, and the correction is recorded rather than quietly applied.** The first draft of this
section read *"19 resolve to exactly one witness node; 5 match several"* and proposed an `AMBIGUOUS_IDENTIFIER` fault
for the five. That was measured with the **wrong lid rule**: it split `witness:factory:<path>#<n>` on `#` and treated
`<n>` as an occurrence index within a claim's witness list. It is not — `#n` is a **section banner** (`§n`), and
`adapters/factory.mjs` builds the lid as `path + (section ? "#" + section : "")`.

Re-measured with the adapter's own rule, against the 172 WITNESS nodes of the shipped multi projection:

- **23 of 24 resolve to an existing witness node** (both the bare-path and the sectioned forms).
- **1 does not**: `witness:factory:scripts/check-federation-invariants.mjs` — the argument cites the script with **no**
  section, and every claim that cites it names a section, so the bare-path node was never minted.
- **0 are ambiguous.** There is nothing to guess.

**Ruling: mint all 24.** The one unresolved ref is not a dangling link — the file is in the pinned factory tree — it is
a witness node no *claim* happened to create. An argument's `evidence_refs` is as authoritative a statement that a path
is a witness as a claim's `witnesses` list is, so the adapter mints the node by the same construction (path, blob,
`LOCATED_IN` its pinned location) and the fault count does not move.

**Related, and deliberately NOT acted on (DISC-2).** 44 of 269 witness citations are byte-equal to an instrument's
`name` field, covering 9 of the 12 instruments. That is textual equality between a `name` and a `path`, and GPT v5 §7 is
explicit that **text/name equality alone does not co-refer**. No `TESTED_UNDER [WITNESS, INSTRUMENT]` is proposed: **0**
witness citations name an instrument by `INS-*` id. Recorded as the strongest candidate for the next source family to
settle.

---

## 4 · Disposition of every authoritative refused structure

Every item gets exactly one of GPT's four dispositions. Nothing in the refused layer is unlisted.

### REPRESENTED in v1

| structure | n | how |
|---|---|---|
| `mosaic/arguments.json` `ARG-*` | 27 | new role `ARGUMENT`; `role`, `rule`, `remaining_trust`, `obligation_discharged` as attrs |
| argument → conclusion | 25 | `SUPPORTS [ARGUMENT, CLAIM]` |
| argument ← witness evidence | 24 (23 resolve, 1 minted) | `WITNESSES [WITNESS, ARGUMENT]` |
| argument → assumptions | 23 | `ASSUMES [ARGUMENT, ASSUMPTION]` |
| argument → premise claims, source refs | 6 + 13 | `CITES` — **already `[*, *]` in v0, no new pair** |
| `mosaic/defeaters.json` `DEF-*` | 68 | new role `DEFEATER`; `kind` (undercutting/undermining/rebutting), `target_type`, disposition as attrs |
| defeater → argument / assumption / claim / instrument / receipt | 12 + 6 + 3 + 5 + 5 = **31** | five `ATTACKS` pairs |
| `mosaic/evidence.json` `INS-*` | 12 | new role `INSTRUMENT`; `procedure`, `produces`, `independence_claim_ref` as attrs |
| instrument → assumptions | 17 | `ASSUMES [INSTRUMENT, ASSUMPTION]` |
| assumption discharged by a claim, **where the source says it is discharged** | 2 | new kind `DISCHARGED_BY [ASSUMPTION, CLAIM]`, `status` on the assertion |
| `defeaters.json` `incidents` `INC-*` | 46 | existing role `FINDING` + `finding_source: "incident"`; **`OPENS`/`CLOSES [ROUND, FINDING]` are already v0 pairs** — all 15 rounds named already exist as ROUND nodes, and 10 incidents open and close at *different* rounds, so the two edges are not redundant. **This needs no new profile surface at all.** |

> **The distinction this makes explicit: v1 *projection content* ≠ v1 *profile surface*.** 46 incidents and 92 of
> their edges enter the v1 projection under the **v0 contract**. They are absent from the v0 multi world only because
> the adapter did not read them, not because the profile refused them.

### DEFERRED — no current semantic consumer; raw source preserved

| structure | n | why, and what is kept |
|---|---|---|
| `consumption_rule` defeater targets | 34 | §1. Code coordinates only, unbound locator, not injective. Kept as five attributes per defeater + the defeater's own pinned source location. |
| `claim_evidence` defeater targets | 3 | **The endpoint resolves — 3/3 to CLAIM nodes — and the source says it would mean something else.** The registry's own note: *"a stale count inside a claim's evidence field does not attack the proposition, it attacks the support the record offers for it. The taxonomy forced the distinction."* Minting `ATTACKS [DEFEATER, CLAIM]` here would assert what the factory explicitly separated. Kept as `target_type` + `target_ref` attrs. Re-open when a claim's `evidence` field has an identity. |
| discharge `evidence_refs` on `undischarged` records | 10 of 12 | 7 of 9 records say `status: "undischarged"`; their refs point at *where the assumption is unmet*, not at a discharge. A `DISCHARGED_BY` edge would invert the source. Kept as assertions with `status` and `scope`. |
| argument `conclusion_defeater` (`ARG-ELIM-1PA-REDUCTION`) | 1 | An argument that eliminates a defeater. Real (`role: defeater_elimination`) but a single record; `ATTACKS [ARGUMENT, DEFEATER]` is the alternative and is recorded, not taken. |
| argument `subsumption` (`ARG-INTEGRATION-SUBSUME-RECEIPT-BINDS`) | 1 | A claim→claim subsumption; v0 has `REFINES`/`EQUIVALENT_TO` nearby. One record, no consumer. |
| `mosaic/evidence.json` `kinds` with `means`/`does_not_mean` | 11 | A vocabulary definition. `DEFINITION` exists in v0 but its pairs do not reach a witness or an instrument; no query needs it. |
| `mosaic/occupancy.json` `OCC-*` | 3 | **The weakest deferral here, flagged as such.** Each names a *resolvable* claim (`TAX-AUTH`, `TAX-COMPOUND`, `TAX-RELATIONAL-2`) with a status and refutation witnesses, so it is **not** process metadata. Deferred only because a rule object has no role and the claims it names already exist as nodes. First candidate to promote. |

### SOURCE-REPAIR — the source form cannot support a semantic identity honestly

| structure | n | the repair |
|---|---|---|
| receipts `invariants.retyped` | 26 prose lines (`ID — FROM to TO. …`) | The pairs exist in v0 (`EVIDENCE_STATE_TRANSITION STATE_TRANSITION_OF CLAIM`, `PRODUCED_BY ROUND`); the *source* is prose. D-021 stands: **do not parse prose**. Filed with the factory: write `{claim, from, to}`. Unchanged from the candidate. |
| `consumption_rule` locators | 34 | The factory's own open item **INC-HIST-SYMBOL**: the symbol is checked at HEAD, not at the pinned revision. Closing it would make §1's deferral re-openable. |

### OUT-OF-SCOPE — process metadata, with the reason

| structure | n | reason |
|---|---|---|
| `mosaic/objectives.json` `SO-*`/`EVAL-*`/`H1–H7` | 16 | describes how the factory chooses what to work on, not what it claims |
| `mosaic/operations.json` matrix | 6 | operational capability matrix; reachable from the claim graph only through 5 assumption `discharge_state` refs, which are themselves deferred |
| `mosaic/embodiment.json` `CAP-SYNTHETIC-*` | 4 | all four are declared **synthetic** |
| `mosaic/derived/*` | 4 files | DERIVED by contract, never facts (D-056) |

### NOT IN THE PINNED SOURCE SET — a fifth case the four dispositions do not cover

`mosaic/integration/INV-R9-from-INV-R7.5.json` (22 KB; `claims` / `forwarded_shared_claims` / `authority_transfer` /
`conflicts`) appears in **no row of the candidate's table** and, checked here, is **not among the 66 pinned factory
files** — `factoryFiles()` reaches `mosaic/{factory,assumptions,sources,evidence,objectives,occupancy,operations,
embodiment}.json`, `mosaic/receipts/**`, `mosaic/derived/*` and witness paths, but nothing under `mosaic/integration/`.
It is therefore outside this snapshot's commitment and **cannot be given a semantic disposition from this pin**.
Recorded because widening the factory source to include it would move `gsnap-` and is a decision, not an oversight.

---

## 5 · The frozen v1 proposal

**3 roles · 1 kind · 10 endpoint pairs.**

```
roles      + ARGUMENT      (27 records)   ports: ["node"]
           + DEFEATER      (68 records)
           + INSTRUMENT    (12 records)

kinds      + DISCHARGED_BY

endpoints  SUPPORTS      + [ARGUMENT,   CLAIM]        25
           WITNESSES     + [WITNESS,    ARGUMENT]     24
           ASSUMES       + [ARGUMENT,   ASSUMPTION]   23
           ASSUMES       + [INSTRUMENT, ASSUMPTION]   17
           ATTACKS       + [DEFEATER,   CLAIM]         3
           ATTACKS       + [DEFEATER,   ARGUMENT]     12
           ATTACKS       + [DEFEATER,   ASSUMPTION]    6
           ATTACKS       + [DEFEATER,   INSTRUMENT]    5
           ATTACKS       + [DEFEATER,   RECEIPT]       5
           DISCHARGED_BY + [ASSUMPTION, CLAIM]         2
```

Reached for free, no new pair: `CITES [*, *]` (premise claims 6, source refs 13, and any argument citation),
`LOCATED_IN [*, SOURCE_LOCATION]`, `MEMBER_OF [*, REGISTRY]`, `OPENS`/`CLOSES [ROUND, FINDING]` (46 + 46).

**Design rulings carried unchanged from GPT v5 §7**, because the census found no contradiction with any of them:
`ARGUMENT` is a distinct role and not a CLAIM sub-kind (an ARG-* has premises, a conclusion and evidence, and typing it
as CLAIM would need `SUPPORTS [CLAIM, CLAIM]`, changing what every existing CLAIM→CLAIM edge could mean);
`DEFEATER` is a distinct role and not a FALSIFIER synonym (a v0 FALSIFIER is an executable construction that falsifies
claim/law semantics — **62 of 68 defeaters target something other than a claim**, and 39 of them target something with
no semantic identity at all); `DISCHARGED_BY` is a distinct kind (overloading `SUPPORTS [CLAIM, ASSUMPTION]` widens
SUPPORTS' target set more than a specific kind costs).

**Non-regression, by construction and by test.** v1 is a **new profile row/id**; the `graphonomous.semantic.v0` row is
not edited. The v0 golden worlds `sem-0f952f03…`, `sem-3ae051cf…`, `sem-b8d82827…` and their `rel-`/`rev-` sets are
untouched, and statement LIDs do not carry the profile (`lib/lid.mjs` hashes only the local part, or composes
`rel:g0:<kind>:<source>:<target>`), so every v0 relation lid reappears in v1 unchanged and remains a cross-world
semantic name.

## 6 · Where this file disagrees with `G0F_V1_OBLIGATION.md`

That document is **kept as written** — it is the record of what the G0-F round proposed, and rewriting it would erase
the fact that a proposal was corrected by a measurement. Where the two differ, **this file governs**: E1 (no argument
`target` dicts; 5 receipt targets exist), E2 (`evidence` targets are instruments, not witnesses), E3 (`DISCHARGED_BY` is
2, gated on status), the 5-key target shape, and the 4 claim-subject incidents.
