# STATUS — Graphonomous G0/G1

Vocabulary (from the brief, used exactly): `DESIGNED` · `IMPLEMENTED` · `TESTED` · `FROZEN` · `BLOCKED` · `PROPOSED`.
Nothing is called TESTED because code exists. Every count below is copied from a command output named beside it
(`node --test test/*.test.mjs`, `node bin/g0.mjs verify|census|eval|verify-eval|world|certify|check-cert`, `python3
test/canon_twin.py --selftest`, `node tools/g0d_vectors.mjs`, `node tools/g05_build.mjs`, WRL `node
test/conformance.mjs`, TRVM `make governance`).

**Stage (2026-09-03, after GPT Adjudication v5 — D-060…D-064): TRVM-P0.1 → `graphonomous.semantic.v1` → G0.5 is
reached and stops here for review.** v5 recorded (D-060…D-063) → **TRVM-P0.1** closed in TRVM (`9e91c96` → `8816e59`,
spec revision 2, receipt `STACK_FIX_RECEIPTS/TRVM-P0.1.md`) → **v1 target-completeness audit** (`G0F_V1_AUDIT.md`,
which CORRECTS the candidate surface in three material places) → **`graphonomous.semantic.v1`** admitted by WRL
(`b072db0` → `53e5e89`), built, sealed and certified → **G0.5**, a read-only inspector over all four worlds. Nothing
pushed. Not started: broad G1, `graphonomous.evidence.v0` (still NOT YET, D-063), the TRVM primitive-basis round.

## Verdict

- **TRVM-P0.1 `TESTED` in its owning layer.** The overloaded `nest-policy-weakened` is split into
  `nest-child-protocol-override-refused` and `nest-child-protocol-registration-malformed` (28 → 30 codes) **by issuing
  spec revision 2** (`srel-4844df97…` → `srel-f5720a3d…`), not by loosening `spec_agreement` — which was in fact
  **enlarged**: `constants.id_prefixes` was declared normatively and compared to nothing, and is now compared against
  **7 prefixes measured by minting one id of each kind**. Falsified both ways before proceeding. New law
  `proof.verdict-names-its-verifier` and a vector measuring that two verifiers differing only in a `checker_id` both
  write `VERIFIED`. `make governance` 32/32 · NEGATIVE BATTERY 392/392 · NEST-FORGERIES 43 → **44/44** · FIELD-AUDIT
  46/46 · grid 139 entries at v1.70.0. **The blind-run ledger EXISTS and already held the supersession GPT asked
  about** — measured: 0 of 17 PINNED receipts carry `previous_run_id`, 14 of 18 ABORTED ones do, so the link is the
  abort's *by protocol* and TRVM-P0's record was never irregular. GAP-T14 **CLOSED**.
- **`graphonomous.semantic.v1` `TESTED`.** The audit measured every refused structure at `d217ee2` and the candidate
  surface **moved**: **3 roles / 1 kind / 10 pairs**, not 2 / 1 / 9. Three material corrections — the "12 argument
  `target` dicts" do not exist (arguments carry no `target`; the 39 structured targets are 34 `consumption_rule` + **5
  receipt**, and the receipt five resolve because a factory RECEIPT lid *is* the file path); `target_type: "evidence"`
  resolves to **INSTRUMENT**, not WITNESS, so the role the candidate ranked last is required; and `DISCHARGED_BY` is
  **2 records, gated on status**, because 7 of 9 discharge records say `undischarged` and an edge there would invert
  the source. A `consumption_rule` target supplies **code coordinates only** — no rule identity, unbound locator, 34
  defeaters carrying 28 distinct payloads — so those 34 and the 3 `claim_evidence` ones are **DEFERRED with their
  source bytes preserved and no edge**, which the UI shows.
- **G0.5 `TESTED` as a read-only inspector.** Four worlds, every value precomputed in Node by `lib/query.mjs` and
  rendered rather than recomputed; a test asserts the baked explanation **equals `Graph.explain()` live**, that no
  world file mixes snapshots, and that the payload holds no layout state.
- **v0 did not move.** The three golden `sem-` reproduce at a WRL commit that *gained a row*; the v1 projection is a
  **strict superset** of the v0 multi projection, record for record, with the same 86 faults code for code.

`node --test test/*.test.mjs`: **151 tests, 150 pass, 0 fail, 1 skipped by design** (was 122/121/0/1). WRL **901/901**
(was 900). TRVM `make governance` 32/32 at `8816e59`. `python3 test/canon_twin.py --selftest`: ok.

## The four projections (`projections/EVIDENCE.md` is the generated source)

| | baseline | historical | multi (v0) | **multi-v1 (NEW)** |
|---|---|---|---|---|
| profile | `graphonomous.semantic.v0` | v0 | v0 | **`graphonomous.semantic.v1`** |
| snapshot | `invariant-r10@ba4e625` + 5 | `@699fbc2` + 5 | baseline's 6 with the factory at 66 files | **the same six sources, byte for byte** |
| adapters | crosswalk | crosswalk | crosswalk + factory | **+ `factory_mosaic`** |
| snapshot commitment | `gsnap-d6743156…` | `gsnap-1e813566…` | `gsnap-2e525288…` | **`gsnap-2e525288…` — IDENTICAL** |
| projection root | `root-da4f3d7a…` FROZEN | `root-c7f9c759…` FROZEN | `root-48ac3e32…` FROZEN | `root-44659ae753a5396fbec7f064cd4349811d577c1d3957703fd8b65fac20c5236d` |
| nodes · relations · faults | 289 · 588 · 64 | 278 · 566 · 64 | 778 · 1,574 · 86 | **932 · 2,007 · 86** (same faults, code for code) |
| evaluation root | `root-c5d650b0…` | `root-edcd9f6f…` | `root-472a5d32…` | `root-57405697…` (1,165 facts) |
| WRL `sem-` (at `53e5e89`) | `sem-0f952f03…` FROZEN | `sem-3ae051cf…` FROZEN | `sem-b8d82827…` FROZEN | **`sem-e186186ea55e9e9a9d10a7676dd31180e248837db54fb66e388d594ff5406e66`** |
| **G0-D certificate** | `vclaim-67038bf96fe5a7c5042be05199157d7b728042ec652c1fd43440dda919ae8efa` | `vclaim-e148f86d613b5c5ec03ec455552e47cc5c3ec6e49ef3815c782e9b9e804df798` | `vclaim-7bbcc6d2c281f8d19c371bf32e759c88fc3d0cca3f8bedc0fd600d8c337459d6` | **`vclaim-1a029671389206f7051b7acd651c29acc56b7f991288fe96e0f63fdf4ada9b19`** |

Pins: TRVM **`8816e59055322fc608c9bc7dae9723c02d8402b7`** (TRVM-P0.1; the five pinned blobs unchanged from `9e91c96`) ·
WRL **`53e5e8995913995189f7017d2a94351ff69d5b31`** (the v1 row; kernel and spine byte-identical to `b072db0`) ·
factory `d217ee29a3322c68db0d43be47491f0e9d4fbc64`.

## Two re-mints this round, each isolating ONE coordinate (D-060 semantics, `test/factory_certificate.test.mjs`)

| preserved under | what moved | what held | the current checker refuses it on |
|---|---|---|---|
| `projections/pre-trvmp01/` (the three vectors GPT froze as golden) | `chain_ids.trvm_commit` only — **not one pinned TRVM blob** | root · commitment · `gclaim-` · aggregate · structure · schema set · adapter contract | `gproj-chain-id-mismatch` + `gproj-certificate-stale` |
| `projections/pre-v1/` | `schema_set_id` only — the vocabulary grew by 4 names | root · commitment · aggregate · adapter contract · **the TRVM pin did not move at all** | `gproj-schema-set-mismatch` + stale |

**An observation for the adjudicator, recorded rather than fixed.** `schemaSetId()` hashes *every* `schemas/*.schema.json`
in the repo, so growing v1's vocabulary moved `schema_set_id` for the **frozen v0 projections too**, and their claims
moved with it. v0's claim identity is therefore not independent of v1's evolution. The fix would be a profile-scoped
schema set, and `schema_set_id`'s meaning is part of `GRAPHONOMOUS-PROJECTION-v0`, whose semantics D-060 froze —
narrowing it is a **protocol change, not a refactor**, so it is not taken unilaterally. Precedent: G0-F moved the same
field for the same reason and GPT v5 §3 called that the expected diagnostic.

## The WRL identity result the G0.5 relation inspector was built to show (`test/v1.test.mjs` (5))

Over the **1,574 statements the v0 and v1 multi worlds share**:

- **1,574 / 1,574 carry the SAME `rev-`** — a statement's revision identity is world-independent;
- **0 / 1,574 carry the same `rel-`** — the allocation is world-scoped;
- 433 statements are v1-only; every v0 statement lid reappears, because **lids do not carry the profile**.

## Items

| Item | State | Evidence / note |
|---|---|---|
| `G0_G1_SPEC.md` | FROZEN | pointer blocks → D-037…D-064 |
| `DECISION_LOG.md` | IMPLEMENTED (document) | D-001…D-064 |
| `STACK_FIX_RECEIPTS/{WRL-P0,TRVM-P0,TRVM-P0.1}.md` | IMPLEMENTED | three receipts; GAP-W9/W13/T9/**T14** CLOSED; GAP-W14 spec debt OPEN, non-blocking |
| `handoff/G0F_V1_AUDIT.md` + `research/R14/{census.json,CENSUS.md}` | IMPLEMENTED (measurement) | every refused structure at `d217ee2` given exactly one of the four dispositions; 3 material corrections to the candidate |
| `WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v1.json` + the WRL row | TESTED | submitted and admitted declarations agree facet for facet (24 roles / 32 kinds / 102 pairs); WRL conformance 21j(k) |
| `adapters/factory_mosaic.mjs` · `snapshots/multi-v1.json` · `projections/multi-v1/` | TESTED | `test/v1.test.mjs` (7 tests): superset, exact delta, deferrals, rev/rel, commitment |
| `lib/acceptance.mjs` · `test/acceptance.test.mjs` | TESTED | A1–A7 as ONE definition, shared by the CLI, the tests and the page |
| `tools/g05_build.mjs` · `ui/` · `bin/g05.mjs` · `test/g05.test.mjs` | TESTED | G0.5; `ui/data` is a build product (gitignored, 36 MB), regenerated by the test into a temp dir |
| `projections/pre-trvmp01/` · `projections/pre-v1/` | IMPLEMENTED (receipts) | the certificates each re-mint superseded, preserved, and each refused on exactly its own moved coordinate |
| G1 / evidence.v0 / primitive basis | not started | by ruling (D-063) |

## Open — for the adjudicator

1. Accept **TRVM-P0.1** as closing GAP-T14, including the two judgement calls it contains: the two chosen code names,
   and **enlarging** `spec_agreement` with a minted id-prefix comparison rather than only adding the codes.
2. Accept the **B2 finding** that the blind-run ledger already held the TRVM-P0 supersession, and that the direction of
   the link (abort names what it ended; a pin starts a chain) is the protocol's — 0/17 vs 14/18, measured.
3. Rule on the **v1 surface as corrected**: 3 roles / 1 kind / 10 pairs, and specifically (a) INSTRUMENT being required
   rather than deferred, (b) the 34 `consumption_rule` and 3 `claim_evidence` targets deferred *with the endpoint
   resolving* — the second is deferred because the source says it means something else, not because it does not
   resolve, and (c) `DISCHARGED_BY` at 2 records gated on status.
4. Rule on the **schema-set coupling** named above: leave it, or open `GRAPHONOMOUS-PROJECTION-v1` with a
   profile-scoped `schema_set_id`.
5. Whether the shared rulepack id (`graphonomous.semantic.rules.v0` on both rows) is right. It is what makes the
   1,574/1,574 `rev-` equality measurable; a `…rules.v1` would break that and is a one-line change if wanted.

## Next smallest step (after acceptance)

Nothing in this lane without a ruling. Candidates: a third source family; the deferred items the audit named (the
`occupancy.json` rules are the weakest deferral and the first to promote); `graphonomous.evidence.v0` only if a
concrete consumer appears; or the first *write* surface, which is a much larger ruling than G0.5 was.
