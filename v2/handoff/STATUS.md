# STATUS — Graphonomous G0/G1

Vocabulary (from the brief, used exactly): `DESIGNED` · `IMPLEMENTED` · `TESTED` · `FROZEN` · `BLOCKED` · `PROPOSED`.
Nothing is called TESTED because code exists. Every count below is copied from a command output named beside it
(`npm test`, `node bin/g0.mjs verify|census|eval|verify-eval|world`, `python3 test/canon_twin.py --manifest`,
`python3 tools/evidence.py`).

**Stage (2026-09-03, GPT Adjudication v3 applied — D-037…D-046):** G0-B.1 **ACCEPTED / TESTED**, G0-E **ACCEPTED /
TESTED** (GPT v3 §0). **D-034 is RULED (D-037) and REPAIRED**: transition → claim is `STATE_TRANSITION_OF`; `SUPERSEDES`
is replacement between comparable entities only; both projections, both evaluations and both spike worlds were rebuilt
and the pre-D-034 roots preserved under `projections/pre-d034/`. This file is the state at the **G0-E checkpoint
commit** (D-045). What follows in this round — `WRL-P0` (D-039), the WRL pin update, and final G0-C through real WRL
sealing — is recorded when it lands.

## Verdict

- **G0-B.1 `TESTED`, G0-E `TESTED`** — accepted by GPT v3. After D-037: `superseded` derives nothing on this data, `current`
  holds every node incl. E-12, E-13a, E-13b, E-13c, E-14, E-15, E-48, E-51 (pinned in `test/query.test.mjs`); the A6
  partition is unchanged; `has_exec_receipt(Subject)` is generic (D-044) — 5 claims and 5 transitions satisfy it at each pin.
- **G0-C spike: historical evidence only (D-038).** Its ids are `gsem-` and `grelpre-` (provisional preimage ids), never
  `rel-`/`sem-`. The real world is minted by WRL after WRL-P0 (D-039, D-041); the spike is superseded then, not renamed.
- **No stack repair inside this commit.** WRL-P0 is a separate change in the WRL repository (D-045).

`npm test`: **81 tests, 81 pass, 0 fail** (2026-09-03, after D-037; was 77).

## The two projections after D-037 (`projections/EVIDENCE.md` is the generated source)

| | baseline / current-at-freeze | historical |
|---|---|---|
| snapshot | `invariant-r10@ba4e625`, `package-v2.7` | `invariant-r10@699fbc2`, `package-v2.6` |
| other pins (both) | `computedriven@efa8881` · `super@7651697` · `TRVM@fd0df4c` · `WRL@1f4c5fd` · factory ref `invariant-canonical@d217ee2` | same |
| pre-B.1 root (preserved, `projections/pre-b1/`) | `root-d1dd7756…` (3,200) | `root-5051394e…` (3,065) |
| **pre-D-034 root (preserved, `projections/pre-d034/`)** | `root-0eea954b5fb07e8a29e88f808c0902abe8fce90b9b04b68864297986769579e3` · eval `root-cc38ce3b…` · `gsem-baf82858…` | `root-2424d836f0742f39ff4089d50cd07341deb9ad2c625347a64e2e815e77b84b3c` · eval `root-2afc57ea…` · `gsem-18664d57…` |
| **projection root (D-037)** | `root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85` | `root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87` |
| manifest entries | 3,005 | 2,893 |
| ruleset (both; moved by D-044's `Subject` rename) | `g0rule-279caadc7dec1b030ba3657bfa7845504b84da8d387786e670804320d433eef9` (was `g0rule-0291a139…`) | same |
| `g0 verify` · Python twin | 3,005 / 3,005, no problems · root recomputed, equal | 2,893 / 2,893 · equal |
| relations · assertions | 588 · 1,272 | 566 · 1,210 |
| `STATE_TRANSITION_OF` · `SUPERSEDES` | 14 · 0 (was 0 · 14) | 14 · 0 |
| faults | 64 (unchanged by-code split) | 64 |
| **G0-E evaluation root (D-037)** | `root-c5d650b0a20902dfa7bc1206be1a2c3257b9699b8734bf825227305fab89715b` — 404 facts / 408 derivations, checker 408/408; `current` 289, `superseded` 0 | `root-edcd9f6f62ab76e876f00ab9401c038dea5dfeb9d2e52ac791185268ed2e9c48` — 393 / 397, 397/397; `current` 278 |
| A6 (D-022 names) | EXEC_RECEIPT_OBSERVED 4 (E-13b, E-14, E-15, E-48) · NO 0 · UNDECIDABLE 18 | same |
| **G0-C spike `gsem-` (historical, D-038)** | `gsem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be` (1,080 objects / 588 relations) | `gsem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23` (1,052 / 566) |

## Items

| Item | State | Evidence / note |
|---|---|---|
| `G0_G1_SPEC.md` | FROZEN | amendments by pointer only; v3 pointer block → D-037…D-046 |
| `DECISION_LOG.md` | IMPLEMENTED (document) | D-001…D-046; D-034 closed by D-037 |
| `STACK_GAP_REGISTER.md` | IMPLEMENTED (document) | GAP-W9/W11/W12/W13 rulings recorded with WRL-P0 |
| `lib/lid.mjs` (D-029, D-030, D-037) · `lib/emit.mjs` · `lib/project.mjs` | TESTED | relation lids are propositions; `RELATION_ENDPOINTS` refuses a kind-mixed `SUPERSEDES` at the lid and at projection |
| `adapters/crosswalk.mjs` (D-031, D-037) | TESTED | `STATE_TRANSITION_OF` at both emission sites; no SUPERSEDES inferred from order |
| `rules/g0.rules.json` v2 (D-032, D-044) | TESTED | assertion-aware; `has_exec_receipt(Subject)` generic |
| `lib/facts.mjs` · `lib/eval.mjs` · `lib/check.mjs` · `lib/evaluation.mjs` · `lib/query.mjs` | TESTED | A1–A7 + E-1…E-6 as queries; `as_of` never mixes roots |
| `projections/{baseline,historical}` + `derived` | TESTED (built, replayed) | roots above; `pre-b1/` and `pre-d034/` preserved and re-verified |
| `WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json` · `lib/wrl_world.mjs` | IMPLEMENTED; candidate (D-042) | endpoint constraints in pairs form; ids `gsem-`/`grelpre-` provisional |
| `research/R11_STATIC_PROFILE_PRIOR_ART.md` | IMPLEMENTED (research) | prior art for the WRL-P0 static-profile design |
| G0-D TRVM contract | partly TESTED | canonical bytes + CAS on every record; certificate still PROPOSED |
| G0-F / G0.5 / G1 | PROPOSED | unchanged; out of scope for this round (D-046) |

## Next (D-046)

`WRL-P0` in the WRL repository → conformance + non-regression + stack-fix receipt + WRL commit → update the Graphonomous
WRL pin → final G0-C through real WRL sealing (`sem-`, kernel-minted `rel-`) → identity-law tests → GPT handoff.
