# Census of the factory ledger's REFUSED LAYER

**Subject** — the authoritative structures in `invariant-factory` that the frozen
`graphonomous.semantic.v0` profile could not represent.

| | |
|---|---|
| repo | `invariant-factory` — bare at `/home/travis/.invariant-factory/canonical.git` |
| pin | `d217ee29a3322c68db0d43be47491f0e9d4fbc64` (tree `11ab2c6192ecf19fbf974da7b6483899903eca32`, 2026-08-26 16:51:38 -0500) |
| pin source | `/home/travis/ProjectAmp2/graphonomous/v2/snapshots/multi.json` → `sources[namespace=factory]` |
| doc under audit | `/home/travis/ProjectAmp2/graphonomous/v2/handoff/G0F_V1_OBLIGATION.md` |
| machine-readable | `census.json` beside this file (282 KB, every record dumped) |
| mutations | **none** — read-only; nothing in any tracked source was touched |

**Method.** The bare repo's `HEAD` *is* the pin (`git rev-parse HEAD` = `d217ee2…`), but nothing was
read from a working tree. `git archive d217ee2 mosaic/ | tar -x` into scratch, then every extracted
blob re-hashed: `git hash-object <extracted>` == `git rev-parse d217ee2:<path>` → **MATCH** for
`arguments.json`, `defeaters.json`, `evidence.json`. `CLAIM_LEDGER.json` read with
`git show d217ee2:CLAIM_LEDGER.json`. Every count below names the command that produced it.

---

## THE ANSWER: what identity does a `consumption_rule` defeater target supply?

> **Code coordinates only. There is no stable semantic rule identity anywhere in the payload —
> not a rule id, not a rule name, not a symbol that is historically bound.**

All 34 carry exactly five keys and no others:

```
{ "revision": "...", "file": "...", "digest": "...", "digest_bits": 64|256,
  "symbol": "..." XOR "section": "..." }
```

`git show d217ee2:mosaic/defeaters.json` — first record, verbatim:

```json
{"revision": "INV-R5", "file": "scripts/check-mosaic.mjs", "symbol": "consume",
 "digest": "95cb25d703ab6dd6", "digest_bits": 64}
```

Five findings, each falsifiable from the data:

**1. No rule-id key exists.** `target_key_union` over the 34 dicts is
`{digest: 34, digest_bits: 34, file: 34, revision: 34, section: 27, symbol: 7}`. No `rule`,
`rule_id`, `id` or `name`. `target_ref` is absent from all 34.

**2. The registry itself offers a *place*, not a *name*.** `mosaic/defeaters.json`
`target_types.consumption_rule.resolves_in`, verbatim:

> `"a rule in scripts/check-mosaic.mjs (consume() or a numbered section) or in mosaic/evidence.json consumption. R6 requires a revision-scoped `target` — at R5.2 this resolver returned `true` unconditionally, so the target could be any sentence at all."`

The R6 repair bound the **file** at a **revision**. It did not mint a rule identity.

**3. The digest binds the FILE, not the rule.** `scripts/check-mosaic.mjs` `digestAtRevision(revision, path)`
looks `path` up in that revision's receipt `provenance.digests` and returns that **file's** `sha256`
(or `sha256_16`, a 64-bit prefix, for INV-R5). Any edit anywhere in the file breaks the binding even
if the rule is untouched.

**4. The locator is unbound and is not a vocabulary.** The gate's own comment, verbatim:

> `"the tree retains no historical BYTES, only historical digests. So the file is bound to its revision and the SYMBOL is not — the symbol check below is a HEAD-existence check and is labelled as one. INC-HIST-SYMBOL is that gap and it is open."`

`section` is worse: `grep -n 't\.section' scripts/check-mosaic.mjs` returns **one** line — 576,
`if (!t.symbol && !t.section) out.push(...)`. It is checked for *non-emptiness* and never read again.
Across the 34 consumption_rule targets there are only **4 distinct `symbol`s** (over 7 records) and
**17 distinct `section`s** (over 27) — 21 distinct locators in five incompatible naming schemes at once:

| scheme | field | values |
|---|---|---|
| JS identifier | `symbol` | `consume`, `resolvesTarget`, `histTargetResolves` |
| JSON key name | `symbol` | `consumption` |
| section number | `section` | `§1`, `§2`, `§3`, `§6`, `§8` |
| prose label | `section` | `§staging`, `§exit`, `§promote`, `§hermetic gate`, `§declared build products`, `§2 enforced()`, `§1 the bucket loop` |
| bare JS identifier used as a "section" | `section` | `alreadyPresentTyped`, `forwardedSharedBound`, `forwardedTransformHolds`, `locateMaterials` |
| a **CLAIM id** used as a section | `section` | `§FAC-ROUND-SERIALIZABLE` |

(The 5 `receipt` targets add a sixth scheme again: `symbol: source_registry`, and sections
`decision.verdict`, `lineage`, `§honesty` — JSON dotted paths.)

**5. The target is not even injective.** 34 defeaters share only **28 distinct payloads**. Three
defeaters — `DEF-CONSUME-STATUS-INFERS-OBLIGATION`, `DEF-CONSUME-COVERAGE-PRESENCE`,
`DEF-CONSUME-CITATION-PRESENCE` — have a **byte-identical** target. Four INV-R5.2 `§1` defeaters
share one; two INV-R6.2 `§6` defeaters share one. A key that cannot separate three defeaters'
subjects is not an identity.

```
python3: len({json.dumps(x['target'],sort_keys=True) for x in defeaters
              if x['target_type']=='consumption_rule'})   -> 28   (of 34)
```

**Consequence for v1.** `ATTACKS [DEFEATER, SOURCE_LOCATION]` is the only pairing this data
supports. A `consumption_rule` node keyed by rule identity **cannot** be minted from this source
without inventing an id the factory does not have — and the 6 collisions prove any id derived from
the target alone would collapse distinct defeaters together. The SOURCE_LOCATION lid must carry
`digest_bits` (see DISC-5) and must not be read as identifying a rule.

**One thing the doc left open is now closed:** *"digests not yet re-checked at the pin."* They are
now. All **39** structured targets (34 consumption_rule + 5 receipt) re-verified by
re-implementing `digestAtRevision` over the pin tree: every revision receipt exists, every target
file exists in the pin tree, every `digest` and `digest_bits` equals what that revision's receipt
recorded. **0 mismatches.** All 5 distinct `symbol` values also pass the HEAD-existence substring
check (`consume` ×14, `resolvesTarget` ×3, `histTargetResolves` ×6, `consumption` ×3,
`source_registry` ×1 occurrences at the pin).

---

## DISCREPANCIES

Seven. Two are material to the v1 proposal.

### DISC-1 — MATERIAL. "the 12 argument `target` dicts" do not exist

`G0F_V1_OBLIGATION.md` §2 item 2 says the 39 dicts to census are
*"the 34 `consumption_rule` targets and the 12 argument `target` dicts."*

**Measured:** the 39 structured `target` dicts are **34 `consumption_rule` + 5 `receipt`**. **Zero**
`argument`-targeted defeaters carry a `target` dict. All 12 carry `target_ref` — a bare `ARG-*` id
string — and nothing else. The doc's own arithmetic does not close either: 34 + 12 = 46 ≠ 39.

```
collections.Counter(x['target_type'] for x in defeaters if isinstance(x.get('target'), dict))
  -> {'consumption_rule': 34, 'receipt': 5}
```

The gate makes the doc's shape impossible — `check-mosaic.mjs` `P.histTargetResolves`, verbatim:

```js
const structural = ['consumption_rule', 'receipt'].includes(d.target_type);
if (!structural) return d.target ? [`${d.id}: only historical targets carry \`target\``] : [];
```

**Why it matters:** the doc proposes `ATTACKS [DEFEATER, SOURCE_LOCATION]` to carry "those 39
dicts". But the 12 argument-targeted defeaters are the *cleanest symbolic edge in the file* —
`DEF-* → ARG-*` by id — which the separately-proposed `ATTACKS [DEFEATER, ARGUMENT]` already carries
exactly. The population that actually needs SOURCE_LOCATION is 34 + 5 **receipt**, and the receipt
five were never mentioned.

### DISC-2 — MATERIAL. "0 witness citations name an instrument" reverses item 5's ranking

§2 item 5 defers INSTRUMENT to last on the ground that *"0 witness citations at this pin name an
instrument, so this is the least urgent."*

**Measured:** 0 name one by `INS-*` **id**. But **44** of the 269 witness citations are byte-equal to
an instrument's `name` field, covering **9 of the 12** instruments.

```
ins_names = {i['name'] for i in evidence['instruments']}
wit = [w for c in claims for w in c['witnesses']]
len([w for w in wit if w in ins_names])                        -> 44
len([w for w in wit if w in {i['id'] for i in instruments}])   -> 0
```

| instrument name | citations |
|---|---|
| `scripts/check-mosaic.mjs` | 12 |
| `scripts/check-integration.mjs` | 8 |
| `AmpersandBoxDesign/box-and-box/test/laws.mjs` | 7 |
| `scripts/check-lineage.mjs` | 6 |
| `scripts/check-publication-identity.mjs` | 4 |
| `scripts/check-claim-ledger.mjs` | 3 |
| `scripts/check-derivation.mjs` | 2 |
| `scripts/check-mutation-surface.mjs` | 1 |
| `scripts/check-gate-import-closure.mjs` | 1 |

Only three instrument names are never cited: `check-escalation-claims.mjs`,
`check-federation-invariants.mjs`, and `"The three-model loop (Fable 5 research, Opus 5
implementation, GPT-5.6 audit)"` — the one instrument that is not a file.

**Why it matters:** `TESTED_UNDER [WITNESS, INSTRUMENT]` would be populated on day one with 44
edges, not empty. The edge exists in the data already; it is keyed by path string rather than by id.

### DISC-3 — "the 1 claim-subject incident" is 4

**Measured:** 4 incidents carry `subject_type: "claim"`. Only **one** names a bare resolvable claim id.

| incident | `subject_ref` | what it resolves to |
|---|---|---|
| `INC-R51-LEDGER-SETTLED-COUNT` | `MOS-CLAIM-OBLIGATION` | a bare claim id ✅ |
| `INC-R9-HISTOGRAM-DRIFT` | `FAC-INTEGRATION-READJUDICATE.evidence` | claim id + a **field suffix** |
| `INC-R93-PREDICATE-DRIFT` | `ASR-RESIDUAL-TYPED.evidence` | claim id + a **field suffix** |
| `INC-R61-ROUND-PROSE` | `CLAIM_LEDGER.json _round` | a **file + a top-level ledger field** — not a claim |

Full distribution:
`{consumption_rule: 18, gate: 13, receipt: 6, claim: 4, registry: 2, evidence: 1, assumption: 1, argument: 1}`.

**Why it matters:** minting `FINDING FALSIFIES CLAIM` from `subject_type=='claim'` yields 4 edges, of
which 2 point at `<CLAIM>.evidence` (a sub-field v0 has no node for) and 1 at a file. One of four is
clean.

### DISC-4 — assumption discharge refs: "3 claim + 1 mosaic ref" is 12 refs

**Measured:** 9 assumptions carry `discharge_state`; between them **12** `evidence_refs`:
**8 witness + 3 claim + 1 source**. By resolved target: 3 claim, **6 mosaic** (5 witness `path`s into
`mosaic/operations.json` ×3 and `mosaic/embodiment.json` ×2, plus the 1 `source` ref
`SRC-RRUV-2016-FILTER` resolving in `mosaic/sources.json`), 3 other (`scripts/*.mjs` witness paths).

The `3 claim` is right; `1 mosaic ref` undercounts by 5, and the 8 witness refs are dropped from the
table entirely. Those `ASSUMPTION → WITNESS` and `ASSUMPTION → SOURCE` edges have no v0 pair either.

### DISC-5 — the target shape is 5 keys, not 4; `digest_bits` is load-bearing

Doc says `{file, revision, digest, section|symbol}`. Every one of the 39 also carries **`digest_bits`**
(64 for the four INV-R5-bound targets, 256 for the other 35). The gate treats it as part of the
binding, verbatim:

```
`${d.id}: binds at ${want.bits} bits (${want.field}) and claims ${t.digest_bits ?? '(none)'}
 — the strength of a binding is part of the binding`
```

A SOURCE_LOCATION lid that drops it silently equates a 64-bit prefix binding with a 256-bit one.

### DISC-6 — the ARGUMENT role vocabulary is 7, populated 6

`mosaic/arguments.json` `roles` declares seven: `domain_coverage`, `citation_scope`,
**`sampling_model`**, `premise_mediation`, `cited_lemma`, `defeater_elimination`,
`proposition_subsumption`. `sampling_model` is used by **0** of the 27 records. A v1 role-attribute
vocabulary must carry 7 while only 6 are populated at this pin.

### DISC-7 — `mosaic/arguments.json` has no `target` key at all

Task section A asked for "the full shape of any `target` dictionary" in arguments. There is none:
`sum(1 for a in arguments if 'target' in a)` → **0** of 27. The argument key union is 16 keys and
`target` is not among them. Every `target` dict in the refused layer belongs to a *defeater*.

---

## A · `mosaic/arguments.json` — 27 ARG-* records

`len(json.load(open('mosaic/arguments.json'))['arguments'])` → **27**

**Key union — 16 keys** (`collections.Counter(k for a in arguments for k in a)`):

| key | present / 27 |
|---|---|
| `argument` | 27 |
| `assumption_refs` | 27 |
| `evidence_refs` | 27 |
| `id` | 27 |
| `premise_claims` | 27 |
| `remaining_trust` | 27 |
| `role` | 27 |
| `rule` | 27 |
| `conclusion_claim` | 25 |
| `obligation_discharged` | 25 |
| `residual_refs` | 5 |
| `conclusion_defeater` | 1 |
| `eliminates_by` | 1 |
| `state_binding` | 1 |
| `subsumption` | 1 |
| `terminator` | 1 |
| **`target`** | **0** |

**Roles** — `domain_coverage` 15 · `citation_scope` 8 · `premise_mediation` 1 ·
`defeater_elimination` 1 · `cited_lemma` 1 · `proposition_subsumption` 1 (declared but unused:
`sampling_model`).

**The 2 records without `conclusion_claim`** conclude something that is not a claim status, per the
file's own `role_conclusions` table: `defeater_elimination → conclusion_defeater`
(`ARG-ELIM-1PA-REDUCTION` → `DEF-1PA-REDUCTION-MISMATCH`) and `proposition_subsumption → subsumption`
(`ARG-INTEGRATION-SUBSUME-RECEIPT-BINDS`, a `{source_claim, canonical_claim, relation, discharged,
why_not_discharged, carries_disposition, withdrawn_at}` dict — a **typed CLAIM↔CLAIM relation**, the
one place an argument asserts a proposition-to-proposition edge).

**Reference totals** (all resolve):

| field | refs | records w/ ≥1 | resolves in |
|---|---|---|---|
| `conclusion_claim` | 25 (25 distinct) | 25 | `CLAIM_LEDGER.json` ✅ 25/25 |
| `premise_claims` | 6 | 5 | `CLAIM_LEDGER.json` ✅ |
| `evidence_refs` | **43** | 27 | see below |
| `assumption_refs` | 23 (only **7 distinct**) | 19 | `mosaic/assumptions.json` ✅ |
| `residual_refs` | 1 | 1 (4 more carry `[]`) | assumptions |

**`evidence_refs` by ref type** — `witness 24 · claim 6 · source 13 · other 0` (total 43).
Two payload shapes: `{kind, path}` for witness (20 bare + 4 with a `section`), `{kind, ref}` for
claim and source (19).

**`obligation_discharged`** — 25 present:
`universal_affirmation` 18 · `existence` 4 · `universal_absence` 2 · `universal_refutation` 1.

Per-record dumps: `census.json` → `A_arguments.records`.

---

## B · `mosaic/defeaters.json` — 68 DEF-* records

`len(...['defeaters'])` → **68**

**Key union — 10 keys:** `doubt` 68 · `id` 68 · `kind` 68 · `target_type` 68 · `disposition` 47 ·
`target` 39 · `target_ref` 29 · `why_open` 21 · `related_claims` 14 (19 refs) · `admits` 1.

**Kinds:** `undercutting` 46 · `undermining` 19 · `rebutting` 3.
The file states `kind` is *derivable* from `target_type` and the gate recomputes it
(`check-mosaic.mjs` line 1084 refuses disagreement).

**Target types and how identity is supplied** — the central table:

| `target_type` | n | `kind` | identity in the record | resolves in |
|---|---|---|---|---|
| `consumption_rule` | 34 | undercutting | **`target` dict — CODE COORDINATES ONLY** | *"a rule in `check-mosaic.mjs` … or in `evidence.json` consumption"* |
| `argument` | 12 | undercutting | `target_ref` = bare `ARG-*` id ✅ | `mosaic/arguments.json` |
| `assumption` | 6 | undermining | `target_ref` = bare `ASM-*` id ✅ | `mosaic/assumptions.json` |
| `evidence` | 5 | undermining | `target_ref` = bare `INS-*` id ✅ | `mosaic/evidence.json` instruments |
| `receipt` | 5 | undermining | **`target` dict — CODE COORDINATES ONLY** | `mosaic/receipts/` |
| `claim` | 3 | rebutting | `target_ref` = bare claim id ✅ | `CLAIM_LEDGER.json` |
| `claim_evidence` | 3 | undermining | `target_ref` = claim id, meaning its **`evidence` field** | `CLAIM_LEDGER.json`, the `evidence` field |

So the file uses **two incompatible identity regimes**: 29 defeaters name their target by a stable
symbolic id in another registry; 39 name it by file-at-revision code coordinates. The split is not
`consumption_rule` vs. everything — it is `{consumption_rule, receipt}` (the "historical" pair) vs.
everything, exactly as `histTargetResolves` declares.

**Target dict key shapes** (`collections.Counter` over the 39):

```
digest,digest_bits,file,revision,section  -> 31   (27 consumption_rule + 4 receipt)
digest,digest_bits,file,revision,symbol   ->  8   ( 7 consumption_rule + 1 receipt)
```

**consumption_rule spread:** 8 distinct files
(`scripts/check-mosaic.mjs`, `check-lineage.mjs`, `check-integration.mjs`, `integration-kernel.mjs`,
`factory-station.mjs`, `verify-review-artifact.mjs`, `make-invariant-review-bundle.sh`,
`mosaic/evidence.json`) across 11 revisions (INV-R5 → INV-R9.3); `digest_bits` 64 ×4, 256 ×30.

**The 5 `receipt` targets** (same shape, different subject — a receipt is its own witness because it
cannot digest itself):

| defeater | file | revision | locator |
|---|---|---|---|
| `DEF-RECEIPT-COPIED-COUNT` | `mosaic/receipts/INV-R5.1.json` | INV-R5.1 | `symbol: source_registry` |
| `DEF-R62-MIXED-LINEAGE` | `mosaic/receipts/INV-R6.2.json` | INV-R6.2 | `section: decision.verdict` |
| `DEF-R81-ARTIFACT-RECEIPT-LOOSE` | `mosaic/receipts/INV-R8.1-CONCURRENCY-OBSERVED.json` | INV-R8.1-… | `section: decision.verdict` |
| `DEF-R83-UNTRUSTED-COUNT` | `mosaic/receipts/INV-R8.3.json` | INV-R8.3 | `section: §honesty` |
| `DEF-R91-RECEIPT-LINEAGE-DRIFT` | `mosaic/receipts/INV-R9.1.json` | INV-R9.1 | `section: lineage` |

**Disposition:** 46 carry `{kind: "sustained", incident_ref: "INC-…"}` · 1 carries
`{kind: "terminated", terminator: {...}}` (`DEF-SUBSTRATE-MISEXECUTION`, `accepted_risk`) ·
**21 carry none and all 21 carry `why_open`** — the live open-doubt set.

Full verbatim payloads for all 68: `census.json` → `B_defeaters.records`; the 34 consumption_rule
targets are additionally isolated under `B_defeaters.consumption_rule_analysis`.

---

## C · `mosaic/defeaters.json` `incidents` — 46 INC-R*-* records

`len(...['incidents'])` → **46**. Every id matches `^INC-R[0-9]+`.

**Key union — 15 keys, 14 of them on 46/46:** `admits`, `closure`, `defeater_ref`, `discovered_by`,
`failure_mode`, `fixed_by`, `id`, `reproducer`, `revision_found`, `revision_introduced`, `severity`,
`status`, `subject_ref`, `subject_type` — plus `note` on 19.

**`severity`** `unsound` 32 · `stale` 11 · `latent` 3. **`status`** `fixed` 46/46 — nothing is open.

**`defeater_ref` ↔ defeater is a BIJECTION.** 46 incidents each name one defeater; 46 defeaters each
carry `disposition.incident_ref`; the two sets are equal. This is the strongest structural relation
in the refused layer and it is symmetric — v1 can mint it from either side.

**`revision_found` → `fixed_by` is not always the same round** — 10 incidents were carried:
7 found at INV-R6.2 → fixed by **INV-R8-RECOVERY**, 3 found at INV-R8.1-CONCURRENCY-OBSERVED → fixed
by INV-R8.2. The doc's proposed `46 OPENS + 46 CLOSES` guard is therefore correct to use two
different rounds per incident, not one.

**`closure`** (46/46, a dict): `mutation_ref` 46 · `bound_to_revision` 46 · `positive_control` 45 ·
`note` 32 · `observed_by` 14 · `external` 14. Every incident is closed by a *named mutation applied
to a copy of the registries and observed to be refused*, not by a status string.

**Does an incident ever name a claim?** Yes — via `subject_type`/`subject_ref`, and in three
different ways. See **DISC-3** above. Indirectly, 3 further incidents reach a claim through their
defeater's `target_ref` (`target_type` `claim`/`claim_evidence`), and 14 defeaters carry a
`related_claims` list (19 refs).

`subject_type` full distribution:
`consumption_rule 18 · gate 13 · receipt 6 · claim 4 · registry 2 · evidence 1 · assumption 1 · argument 1`.

Note `subject_ref` is **free text**, not an id space — e.g. `"scripts/check-mosaic.mjs consume()"`,
`"scripts/check-lineage.mjs §2 enforced()"`, `"the downloadable review artifact"`,
`"mosaic/defeaters.json DEF-FED-SEP-COST"`. It duplicates by prose what the defeater's `target` dict
holds structurally.

---

## D · Assumption discharge — 9 of 29 carry `discharge_state`

`len(...['assumptions'])` → **29**. Key union: `cited_by`/`discharge`/`discharged`/`id`/`kind`/
`statement` 29 each · `note` 19 · `discharge_state` **9**.

`kind`: `interface` 8 · `theorem` 7 · `environment` 4 · `observer` 4 · `resource` 2 ·
`distribution` 2 · `substrate` 2.

All 9 `discharge_state` dicts have the identical shape `{status, scope, evidence_refs, residual}`
(the key is `status`, **not** `state`). `status` values: `by_procedure` 1 · `partial` 1 ·
`undischarged` 7.

**12 evidence_refs total: witness 8 · claim 3 · source 1.** Resolved target kind:
**claim 3 · mosaic 6 · other 3.**

| assumption | `status` | evidence_refs → resolved kind |
|---|---|---|
| `ASM-1PA` | by_procedure | `scripts/check-federation-invariants.mjs` → other · `FED-1PA-DEC-IMPL` → **claim** |
| `ASM-TRANSFER-SOLE-MUTATOR` | partial | `scripts/check-mutation-surface.mjs` → other · `LED-MUTATION-SURFACE` → **claim** |
| `ASM-FILTER-DEFN-SUBSUMPTION` | undischarged | `SRC-RRUV-2016-FILTER` → **mosaic** (`sources.json`) |
| `ASM-CAPABILITY-CONTRACT` | undischarged | `mosaic/operations.json` §matrix → **mosaic** |
| `ASM-CAPABILITY-NOT-IN-PRIORS` | undischarged | `scripts/emb-battery-control.mjs` §2 → other · `EMB-CUT-EMPTY` → **claim** |
| `ASM-REFINEMENT-ADMITTED` | undischarged | `mosaic/operations.json` §matrix → **mosaic** |
| `ASM-COMMITMENT-PERSISTS` | undischarged | `mosaic/operations.json` §matrix → **mosaic** |
| `ASM-REMOTE-MODEL-IDENTITY` | undischarged | `mosaic/embodiment.json` §inference_support_envelope → **mosaic** |
| `ASM-MEDIATION-UNIVERSE` | undischarged | `mosaic/embodiment.json` §admission_mediation → **mosaic** |

`residual` names defeater ids (never prose): **7 refs across 5 records**, all resolving; the other
4 records carry `residual: []`. (Separately, 5 ARG-* records carry `residual_refs`, but only
`ARG-GATE-CLOSURE-COVERAGE` has a non-empty one — 1 ref, `ASM-STATIC-IMPORT-CLOSURE`.)

**This is also the only bridge into `operations.json` and `embodiment.json`** — see §F.

Verbatim `discharge_state` dumps: `census.json` → `D_assumption_discharge.records`.

---

## E · `mosaic/evidence.json` — 12 instruments, 11 kinds

**Instruments** `len(...['instruments'])` → **12**. Key union: `assumption_refs`,
`common_cause_refs`, `correlation_measurement_refs`, `id`, `independence_claim_ref`, `name`,
`origin_refs`, `procedure`, `produces` all 12/12 · `note` 2 · `known_dependence` 1 ·
`measured_runtime` 1.

`assumption_refs`: **17 refs**, 12/12 instruments carry ≥1, all resolve
(`ASM-SUBSTRATE-INTEGRITY` on all 12, plus `ASM-D-FINITE`, `ASM-GAMMA-FINITE`,
`ASM-BUNDLE-SOURCE-ONLY`, `ASM-TRANSFER-SOLE-MUTATOR`, `ASM-STATIC-IMPORT-CLOSURE`).

Ids: `INS-FED-GATE`, `INS-LEDGER-GATE`, `INS-MOSAIC-GATE`, `INS-MUTATION-SURFACE`, `INS-ESC`,
`INS-KERNEL-LAWS`, `INS-PANEL`, `INS-PUBLICATION-WALK`, `INS-DERIVATION`, `INS-INTEGRATION`,
`INS-LINEAGE`, `INS-GATE-CLOSURE`.

11 of the 12 `name`s are repo paths that exist at the pin; the twelfth is `INS-PANEL`, named
`"The three-model loop (Fable 5 research, Opus 5 implementation, GPT-5.6 audit)"` — the one
instrument that is not a file, and the one carrying `known_dependence: "UNMEASURED for this panel…"`.
`produces` histogram (18 declarations over 12 instruments): `exhaustion` 7 · `measurement` 4 ·
`deductive_proof` 2 · `counterexample` 1 · `constructive_witness` 1 · `randomized_search` 1 ·
`statistical_certificate` 1 · `model_judgment` 1.

**Kinds** `len(...['kinds'])` → **11**, and **11/11 carry both `means` and `does_not_mean`**:
`deductive_proof`, `counterexample`, `constructive_witness`, `exhaustion`, `randomized_search`,
`statistical_certificate`, `measurement`, `reproduction`, `attestation`, `model_judgment`,
`cited_result`. Also `example_in_ledger` 11 · `requires_qualifier` 5 · `note` 2 · `prior_art` 1.

Each entry is a **definition with an explicit negative clause** — e.g. `exhaustion.does_not_mean`
begins *"Anything about a randomized run."*, `model_judgment.does_not_mean` *"Anything about
truth."* Full text: `census.json` → `E_evidence_instruments_and_kinds.kinds.records`.

---

## F · The four registries with "no role proposed"

| file | records | id prefix | classification |
|---|---|---|---|
| `mosaic/objectives.json` | 7 `H*` + 5 `SO-*` + 4 `EVAL-*` = **16** | `H<n>-` / `SO-` / `EVAL-` | **process metadata** (with a caveat) |
| `mosaic/occupancy.json` | **3** rules | `OCC-` | **SEMANTIC** |
| `mosaic/operations.json` | **6** matrix rows | *none — keyed by `operation` verb-phrase* | **process metadata / declared-only** |
| `mosaic/embodiment.json` | **4** capabilities | `CAP-SYNTHETIC-` | **process metadata / synthetic** |

**objectives** — `subject: "The Periodic Table of Agent Invariants research loop (INV-R1 .. INV-R5)"`.
`SO-*` key set `{id, measurand, direction, instrument_refs, gaming_test}` + optional
`{value, why_unmeasured, measurement_ref, note}` — these measure the factory's own output.
`EVAL-*` key set `{id, role, version, writes, write_authority_over_objectives, note}` — the three
models and the human. `H1–H7` are prose strings, not records. **None of the 16 names a claim id**, so
none has an outgoing edge into the claim graph. Caveat: `H1..H7` are *enforced gate constraints*,
semantically closer to LAW than the rest — worth a second look if v1 ever wants a LAW role.

**occupancy — this one is not process metadata.** All 3 rules carry `claim` naming a real
`CLAIM_LEDGER.json` id (`TAX-AUTH`, `TAX-COMPOUND`, `TAX-RELATIONAL-2` — all resolve), a `status`
(`REFUTED` / `ENFORCED` / `ENFORCED`), an executable `{when, forbid}` predicate over
`opensentience.org/invariants.html`'s 46 cells, plus `refutation_witnesses` and `population_at_R5`.
`OCC-STAT-AUTH` is a rule *the project held and its own subject refuted 3 of 3*, kept so the
refutation stays reproducible. That is an evidential relation to a claim, not process bookkeeping —
the doc's "no role proposed" is the weakest of the four here.

**operations** — the file's own `status` field, verbatim: *"DECLARED. The matrix is a set of
obligations over operations this artifact does not perform. Nothing here is measured."* 6 rows
(`reload-model`, `replace-model`, `externalize-capability`, `migrate-substrate`, `rollback`,
`fork-agent`) × 8 quantity columns. No ids, no claims. Reachable from the claim graph **only**
through the 3 assumptions in §D that cite `mosaic/operations.json` §matrix.

**embodiment** — 4 capabilities, `synthetic: true` on all 4, each with a `why_synthetic` prose field.
A top-level `not_in_this_file` key explicitly excludes authority, exposure and real capabilities.
Reachable **only** through the 2 assumptions in §D that cite its sections.

---

## G · Every file in `mosaic/` at the pin — 35 files, nothing omitted

`git ls-tree -r -l d217ee29a3322c68db0d43be47491f0e9d4fbc64 -- mosaic/`

| path | bytes | top-level keys |
|---|---|---|
| `mosaic/arguments.json` | 53810 | `_comment, version, generated, round, roles, role_conclusions, arguments` |
| `mosaic/assumptions.json` | 28719 | `_comment, version, generated, round, kinds, discharge_states, assumptions` |
| `mosaic/defeaters.json` | 144750 | `_comment, version, generated, round, kinds, target_types, statuses, dispositions, terminators, strict_rules, elimination_modes, assurance_states, promotion_policy, severities, defeaters, incidents` |
| `mosaic/embodiment.json` | 56766 | `_comment, version, generated, round, support_evidence_kinds, monotonicity, capabilities, battery, not_in_this_file, inference_support_envelope, admission_mediation, impact_algebra` |
| `mosaic/evidence.json` | 28065 | `_comment, version, generated, round, kinds, qualifiers, obligations, consumption, status_obligation_domain, instruments, provenance_fields, origins` |
| `mosaic/factory.json` | 47149 | `_comment, version, generated, canonical_ref, quarantine_ref, git_dir, git_dir_why, tree, derivations, derivations_why, narrative, revisions, quarantine, working_tree_divergence, unpromoted_ref, promotion, quarantine_classes, artifact_additions, artifact_additions_why, render, publication` |
| `mosaic/objectives.json` | 15674 | `_comment, version, generated, round, subject, hard_constraints, soft_objectives, selection_rule, evaluators, exteriority` |
| `mosaic/occupancy.json` | 4289 | `_comment, version, generated, round, subject, kind_vocabulary, rules` |
| `mosaic/operations.json` | 33834 | `_comment, version, generated, round, status, proposal_audit, obligations, quantities, operations_not_registered, matrix, orders, strict_relations` |
| `mosaic/sources.json` | 24638 | `_comment, version, generated, round, sources` |
| `mosaic/derived/brief-facts.json` | 2052 | `_comment, round, facts` |
| `mosaic/derived/integration-delta.json` | 28367 | `_comment, generated_by, kind, integrations` |
| `mosaic/derived/measurements.json` | 2487 | `generated_by, round, _comment, measurements` |
| `mosaic/derived/occupancy.json` | 867 | `generated_by, inputs, rules, kind_coverage` |
| `mosaic/integration/INV-R9-from-INV-R7.5.json` | 22088 | `_comment, integration_id, generated, method, method_why, pinned_inputs, watermark, authority_transfer, claims, forwarded_shared_claims, files, conflicts` |
| `mosaic/receipts/INV-R5.json` | 9251 | 12 keys: `_comment, receipt_version, transition, contracts, invariants, authority, objectives, evidence, provenance, decision, lineage, honesty` |
| `mosaic/receipts/INV-R5.1.json` | 13362 | same 12 |
| `mosaic/receipts/INV-R5.2.json` | 16823 | same 12 |
| `mosaic/receipts/INV-R6.json` | 17362 | same 12 |
| `mosaic/receipts/INV-R6.1.json` | 16300 | same 12 |
| `mosaic/receipts/INV-R6.2.json` | 20045 | same 12 |
| `mosaic/receipts/INV-R7.1.json` | 15337 | same 12 |
| `mosaic/receipts/INV-R7.2.json` | 13508 | same 12 |
| `mosaic/receipts/INV-R7.3.json` | 16561 | same 12 |
| `mosaic/receipts/INV-R7.4.json` | 16264 | same 12 |
| `mosaic/receipts/INV-R7.5.json` | 24163 | same 12 |
| `mosaic/receipts/INV-R8-RECOVERY.json` | 40410 | 17: +`parent, candidate, tree_delta, source_artifacts, scope` |
| `mosaic/receipts/INV-R8.1-CONCURRENCY-OBSERVED.json` | 43397 | 18: +`amendment` |
| `mosaic/receipts/INV-R8.2.json` | 39929 | 17 |
| `mosaic/receipts/INV-R8.3.json` | 45527 | 18: +`next` |
| `mosaic/receipts/INV-R9.json` | 59113 | 19: +`integration, next` |
| `mosaic/receipts/INV-R9.1.json` | 48735 | 19: +`next, integration_note` |
| `mosaic/receipts/INV-R9.2.json` | 50695 | 18: +`next` |
| `mosaic/receipts/INV-R9.3.json` | 51253 | 18: +`next` |
| `mosaic/receipts/INV-R9.4.json` | 51393 | 18: +`next` |

**20 receipt files** (no `INV-R7.json` exists — the R7 line starts at `INV-R7.1`).
**4 `derived/` files**, matching the doc.
`mosaic/integration/INV-R9-from-INV-R7.5.json` is **not listed anywhere in
`G0F_V1_OBLIGATION.md`** — it is a 22 KB integration manifest with `claims`,
`forwarded_shared_claims`, `authority_transfer` and `conflicts` sections. It is the input
`INS-INTEGRATION` runs over. Not a discrepancy in a count, but worth naming: the refused-layer table
has no row for it.

`invariants.retyped` across the 20 receipts totals **26** prose lines, matching the doc
(R5.1 ×3, R6.1 ×1, R7.1 ×2, R7.2 ×3, R7.3 ×2, R7.4 ×3, R7.5 ×5, R8-RECOVERY ×1, R8.2 ×2, R8.3 ×2,
R9.3 ×1, R9.4 ×1).

---

## Everything the doc got right

23 checks, all verified — full list with commands in `census.json` → `VERIFIED_AGREEMENTS`.
Headline: 27 arguments and their exact role split · 24/6/13 evidence_refs · 23 assumption_refs ·
6 premise_claims · 25 conclusion_claims · 68 defeaters with the exact 46/19/3 kind split and the
exact 34/12/6/5/5/3/3 target_type split · "6 of 68 fit" · 46 incidents with 32/11/3 severities, all
`fixed` · 12 instruments with 17 assumption_refs · 11 kinds · 16 objectives · 3 occupancy rules ·
6 operations · 4 synthetic capabilities · 26 retyped lines · 4 derived files · 208 claims ·
87 witnesses / 269 citations · 29 typed + 110 free-text assumptions · 20 receipts.

The doc is accurate on **every population count in §1**. Its errors are all in §2 — where it
describes the *shape* of the things it counted.
