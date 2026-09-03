# STATUS — Graphonomous G0/G1

Vocabulary (from the brief, used exactly): `DESIGNED` · `IMPLEMENTED` · `TESTED` · `FROZEN` · `BLOCKED` · `PROPOSED`.
Nothing is called TESTED because code exists. Every count below is copied from a command output named beside it
(`npm test`, `node bin/g0.mjs verify|census|eval|verify-eval|world|certify|check-cert`, `python3 test/canon_twin.py
--manifest`, `python3 tools/evidence.py`, `node tools/g0d_vectors.mjs`, WRL `node test/conformance.mjs`, TRVM batteries).

**Stage (2026-09-03, after GPT Adjudication v4 — D-049…D-059): the G0-D → G0-F milestone is reached and stops here for
review.** Freeze recorded (`b61ff2e`) → **G0-D certificate** (`14f77e0`) → **TRVM-P0** in TRVM (`fd0df4c` → `9e91c96`,
receipt `STACK_FIX_RECEIPTS/TRVM-P0.md`) → Graphonomous TRVM pin moved, certificates re-minted → **G0-F factory ledger**
as the second authoritative source, sealed under frozen v0. Nothing pushed. Not started: UI/G0.5, broad G1,
`graphonomous.evidence.v0` (ruled NOT YET, D-059), the TRVM primitive-basis round.

## Verdict

- **G0-C, `graphonomous.semantic.v0`: FROZEN** (GPT v4, D-049/D-050). Golden worlds `sem-0f952f03…` / `sem-3ae051cf…` at
  WRL `b072db0` reproduce unchanged; the multi world is a *new* v0 world, not a v0 change.
- **G0-D `TESTED`** — `GRAPHONOMOUS-PROJECTION-v0` certifies reconstruction identity, not truth (D-054): claim = projection
  root + order-independent, dropped-source-sensitive snapshot commitment + spec + ruleset + schema set + adapter contract
  + a checker-owned scope that makes the "must not mean" list refusable; certificate = TRVM `verifiedClaimSemId`; the
  checker re-derives everything and writes nothing; 21 `gproj-` codes each measured (58 field mutations, 17 directory
  forgeries). The eight D-054 acceptance items are `test/certificate.test.mjs`; the TRVM agreement vector is
  `test/certificate_trvm.test.mjs` (VERIFIED through the real `checkNestBundle` with a supplied table).
- **TRVM-P0 `TESTED` in its owning layer** — a verifier-supplied `child_protocols` registry; failing-first (6/7 new vectors
  fail at `fd0df4c`), NEST-FORGERIES 43/43, SPEC-AGREEMENT 28 codes unchanged, all six batteries green (gov-negative
  392/392), every regenerated bundle byte-identical; the blind run re-pinned through the tree's own remedy. **GAP-T9
  CLOSED**; GAP-T14 (named refusal codes need a spec revision, TRVM-P0.1) OPEN, non-blocking.
- **G0-F `TESTED`** — the factory ledger at `d217ee2` ingested in the D-056 scope; 4 cross-registry ids are one node each
  with assertions from both sides; 0 cross-registry relations co-refer (measured); the core seals under frozen v0; the
  argument/defeater layer is `graphonomous.semantic.v1` **PROPOSED** (D-059); `graphonomous.evidence.v0` **NOT YET**.
- **Stack repair discipline held twice** (WRL-P0, TRVM-P0): reproducer → failing test → generic repair → non-regression →
  receipt → return to the exposing case.

`npm test`: **122 tests, 121 pass, 0 fail, 1 skipped by design** (the pre-TRVM-P0 reproducer branch, superseded by the
landed repair). WRL 900/900. TRVM batteries green at `9e91c96`.

## The three projections (`projections/EVIDENCE.md` is the generated source)

| | baseline | historical | **multi (G0-F)** |
|---|---|---|---|
| snapshot | `invariant-r10@ba4e625` + 5 pins | `invariant-r10@699fbc2` + 5 pins | baseline's 6 sources with the factory widened to 66 files at `d217ee2` |
| snapshot commitment (`gsnap-`) | `gsnap-d6743156…` | `gsnap-1e813566…` | `gsnap-2e5252881fc3192a912d95b0b8ccf010be619ece8cb9a3dc6ccb0ddfd35a944e` |
| projection root (FROZEN / new) | `root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85` | `root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87` | `root-48ac3e32dfc56cd1450e43b92c7a38d83d71a95113da8b243951dfa305fd2213` |
| manifest entries · `g0 verify` · twin | 3,005 · clean · equal | 2,893 · clean · equal | 7,639 · clean · equal |
| relations · assertions · faults | 588 · 1,272 · 64 | 566 · 1,210 · 64 | 1,574 · 3,270 · 86 (SETTLED_WITHOUT_WITNESS 8, UNRESOLVED_LINK 56) |
| evaluation root | `root-c5d650b0…` (404 / 408) | `root-edcd9f6f…` (393 / 397) | `root-472a5d32…` (1,011 / 1,016) |
| WRL `sem-` (v0, WRL `b072db0`) | `sem-0f952f03…` FROZEN | `sem-3ae051cf…` FROZEN | `sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea` (2,707 / 1,574; kernel `rel-`/`rev-` 1,574/1,574) |
| **G0-D certificate (`vclaim-`, TRVM `9e91c96`)** | `vclaim-c90547a6de6d46e5a79750ca897a58f3f4305971c300c567cab712436b7bd851` | `vclaim-bf81cc6d8deaa393638f0d13028cf4a6c9f737b7bf4a7c7869bd651fa880e0cf` | `vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2` |
| claim id (`gclaim-`) | `gclaim-446e4455…` | `gclaim-dd5536f2…` | `gclaim-b7608302…` |
| pre-G0-F certificate (preserved, `projections/pre-g0f/`) | `vclaim-897ec409…` — VERIFIED under the `14f77e0` checker; refused by the current one on chain/schema-set/stale only | `vclaim-a6ba3b33…` (same) | — |

Pins: TRVM **`9e91c96f2d50f3c3bd143fc94ec4267a6b03195a`** (TRVM-P0; five pinned blobs unchanged from `fd0df4c`) · WRL
`b072db0a983a33108b9a0c4429b978cb07e54148` · factory `d217ee29a3322c68db0d43be47491f0e9d4fbc64` (`INV-R9.4`).

## Certificate sensitivity (measured: `G0D_GOLDEN_VECTORS.md`, `test/certificate.test.mjs`, `test/factory_certificate.test.mjs`)

| change | claim | certificate |
|---|---|---|
| projection root · dropped/added/duplicated source · narrowed source file set · relabelled snapshot · spec · ruleset · schema set · adapter contract · scope | moves | moves |
| protocol → v1 · TRVM pin · projector or checker code · aggregate | holds | moves |
| reordered sources and file lists · witness.json · README · annotations | holds | holds |
| a later snapshot exists (multi) | — | old certificate unchanged; refused against the other directory (`gproj-root-mismatch`/`-certificate-stale`) |

## Items

| Item | State | Evidence / note |
|---|---|---|
| `G0_G1_SPEC.md` | FROZEN | pointer blocks → D-037…D-054 |
| `DECISION_LOG.md` | IMPLEMENTED (document) | D-001…D-059 |
| `STACK_GAP_REGISTER.md` · `STACK_FIX_RECEIPTS/{WRL-P0,TRVM-P0}.md` | IMPLEMENTED | two receipts; GAP-W9/W13/T9 CLOSED; GAP-W14/T14 spec debt OPEN, non-blocking |
| `lib/certificate.mjs` · `tools/g0d_vectors.mjs` · `handoff/G0D_GOLDEN_VECTORS.md` | TESTED | G0-D; `childProtocolEntry` conforms to the TRVM-P0 `check()` contract |
| `adapters/factory.mjs` · `snapshots/multi.json` · `projections/multi/` | TESTED | G0-F (D-056 scope; contract deviations recorded) |
| `handoff/G0F_V1_OBLIGATION.md` · `handoff/G0F_EVIDENCE_PROFILE_NOTE.md` | PROPOSED / measurement | v1: 2 roles, 1 kind, 9 pairs; evidence.v0: not yet |
| `research/R12` (factory census) · `R13` (TRVM certificate API) + probes | IMPLEMENTED (research) | the reproducers behind D-055/D-056 |
| G0.5 / G1 / evidence.v0 / primitive basis | not started | by ruling (D-046, D-053, D-054) |

## Open — for the adjudicator

1. Accept G0-D and G0-F as TESTED and rule whether the three certificates and the multi world are golden vectors.
2. TRVM-P0: accept the two deviations (refusal codes under `nest-policy-weakened` pending TRVM-P0.1; the blind-run
   re-pin recorded here because the TRVM ledger is outside this lane).
3. D-058's re-mint semantics: a certificate names *under which code* it was reconstructed (TRVM `chainIds()`
   discipline) — confirm that "old certificate still verifies" means *under its own checker*, with the newer checker
   naming the moved coordinate.
4. Whether to open `graphonomous.semantic.v1` (D-059) or wait for a third source family.

## Next smallest step (after acceptance)

Nothing in this lane without a ruling: candidates are v1 (the argument/defeater layer), a third source family, or
G0.5's minimal UI over the three projections.
