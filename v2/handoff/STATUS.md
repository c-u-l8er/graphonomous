# STATUS — Graphonomous G0/G1

Vocabulary (from the brief, used exactly): `DESIGNED` · `IMPLEMENTED` · `TESTED` · `FROZEN` · `BLOCKED` · `PROPOSED`.
Nothing is called TESTED because code exists. Every count below is copied from a command output named beside it
(`npm test`, `node bin/g0.mjs verify|census|eval|verify-eval|world`, `python3 test/canon_twin.py --manifest`,
`python3 tools/evidence.py`, `node tools/identity_matrix.mjs`, WRL `node test/conformance.mjs`).

**Stage (2026-09-03, GPT Adjudication v4 — D-049…D-054): G0-C and `graphonomous.semantic.v0` are FROZEN** (golden
worlds `sem-0f952f03…` / `sem-3ae051cf…` at WRL `b072db0`; D-048 equality measured, non-normative; `evidence.v0`
deferred; WRL-P0.1 spec text = GAP-W14, non-blocking). **Next: G0-D `GRAPHONOMOUS-PROJECTION-v0` certificate, then G0-F
factory ledger** (D-054). The milestone below was reached under v3 and accepted by v4: D-034 repaired (D-037) → G0-E checkpoint commit `3db893a` → **WRL-P0 `Static Profile + Seal
Closure` landed in WRL (`1f4c5fd` → `b072db0`, receipt `STACK_FIX_RECEIPTS/WRL-P0.md`)** → Graphonomous WRL pin updated →
**final G0-C: both worlds SEALED by WRL to a real `sem-`, every `rel-`/`rev-` kernel-minted (D-048)**. Nothing pushed.
G0-D/F/UI not started (D-046).

## Verdict

- **G0-B.1 `TESTED`, G0-E `TESTED`** (accepted by GPT v3). After D-037: `superseded` derives nothing, `current` holds
  every node incl. E-12, E-13a, E-13b, E-13c, E-14, E-15, E-48, E-51; A6 partition unchanged; `has_exec_receipt(Subject)`
  is generic (5 claims + 5 transitions per pin).
- **WRL-P0 `TESTED` in its owning layer** — WRL conformance 890 → **900 passed, 0 failed**; the 10 new checks failed at
  `1f4c5fd` for the expected reasons (`891 passed, 9 failed`; the GAP-W9 case *sealed*); `NO BYTE OR ID MOVED` for every
  pinned forge vector; kernel/spine/TRVM untouched. GAP-W9, GAP-W13 **CLOSED**; GAP-W11 ruled (no widening); GAP-W12 ruled
  (adapter encoding accepted).
- **G0-C `TESTED`, identities `SEALED` (not yet `FROZEN` — D-042: freeze on GPT acceptance).** WRL canonicalizes,
  validates the profile, seals `sem-`, mints `rel-`/`rev-`. The D-037 spike is preserved under `world-spike/` and mapped
  from `identities.json`; measured: its bytes equal WRL's canonical bytes (D-048 — a measurement, not a rename).
- **Stack repair discipline held:** one receipt, failing-first, non-regression vectors, kernel `validateAllocation` not
  widened, no `if (profile_id === …)` in WRL.

`npm test`: **85 tests, 85 pass, 0 fail** (2026-09-03; 77 → 81 after D-037 → 85 after G0-C).

## The two projections (`projections/EVIDENCE.md` is the generated source)

| | baseline / current-at-freeze | historical |
|---|---|---|
| snapshot | `invariant-r10@ba4e625`, `package-v2.7` | `invariant-r10@699fbc2`, `package-v2.6` |
| other pins (both) | `computedriven@efa8881` · `super@7651697` · `TRVM@fd0df4c` · factory ref `invariant-canonical@d217ee2` · **WRL `b072db0a983a33108b9a0c4429b978cb07e54148`** (relation-v2.js `fd1babc5…`, relation-identity.js `880cfe04…`, wrl.js `19e94ad9…`) | same |
| pre-B.1 root (preserved, `projections/pre-b1/`) | `root-d1dd7756…` (3,200) | `root-5051394e…` (3,065) |
| pre-D-034 (preserved, `projections/pre-d034/`) | `root-0eea954b…` · eval `root-cc38ce3b…` · `gsem-baf82858…` | `root-2424d836…` · eval `root-2afc57ea…` · `gsem-18664d57…` |
| **projection root (D-037; unchanged by the seal)** | `root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85` | `root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87` |
| manifest entries | 3,005 | 2,893 |
| ruleset (both) | `g0rule-279caadc7dec1b030ba3657bfa7845504b84da8d387786e670804320d433eef9` | same |
| `g0 verify` · Python twin | 3,005 / 3,005, no problems · equal | 2,893 / 2,893 · equal |
| relations · assertions · `STATE_TRANSITION_OF` · `SUPERSEDES` | 588 · 1,272 · 14 · 0 | 566 · 1,210 · 14 · 0 |
| faults | 64 | 64 |
| **G0-E evaluation root** | `root-c5d650b0a20902dfa7bc1206be1a2c3257b9699b8734bf825227305fab89715b` — 404 / 408, checker 408/408; `current` 289 | `root-edcd9f6f62ab76e876f00ab9401c038dea5dfeb9d2e52ac791185268ed2e9c48` — 393 / 397, 397/397; `current` 278 |
| A6 (D-022 names) | EXEC_RECEIPT_OBSERVED 4 (E-13b, E-14, E-15, E-48) · NO 0 · UNDECIDABLE 18 | same |
| **WRL `sem-` (SEALED, D-048)** | `sem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be` — 1,080 objects / 588 relations / 960,827 bytes; `rel-` 588/588 and `rev-` 588/588 kernel-minted | `sem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23` — 1,052 / 566 / 920,425; 566/566 |
| historical spike `gsem-` (`world-spike/`, mapped) | `gsem-0f952f03…` (hex equal to the `sem-`, measured) | `gsem-3ae051cf…` (same) |
| example (statement lid → `rel-` / `rev-`) | `rel:g0:ADJUDICATED_BY:claim:crosswalk:E-14:adjudication:gpt:exec-v3:s3` → `rel-49b3a747…` / `rev-4bd7316b…` | same lid → `rel-405dc54d…` / `rev-4bd7316b…` (same revision bytes, different world → different `rel-`) |

## Identity laws measured (`handoff/G0C_IDENTITY_MATRIX.md`, baseline)

| edit | `sem-` | `rev-` moved | `rel-` moved | lids | projection root |
|---|---|---|---|---|---|
| none · shuffle | stable | 0/588 | 0/588 | stable | stable (A8) |
| assertion-only | stable | 0/588 | 0/588 | stable | **moves** |
| one relation attribute | moves | 1/588 | 588/588 | stable | moves |
| one node attribute | moves | 0/588 | 588/588 | stable | moves |

## Items

| Item | State | Evidence / note |
|---|---|---|
| `G0_G1_SPEC.md` | FROZEN | amendments by pointer only; v3 pointer block → D-037…D-046 |
| `DECISION_LOG.md` | IMPLEMENTED (document) | D-001…D-048 |
| `STACK_GAP_REGISTER.md` · `STACK_FIX_RECEIPTS/WRL-P0.md` | IMPLEMENTED (document) | first receipt; W9/W13 closed, W11/W12 ruled |
| `lib/lid.mjs` · `lib/emit.mjs` · `lib/project.mjs` · `adapters/crosswalk.mjs` (D-037) | TESTED | `STATE_TRANSITION_OF`; kind-mixed `SUPERSEDES` refused at the lid and at projection |
| `rules/g0.rules.json` v2 (D-032, D-044) · evaluator / checker / query | TESTED | A1–A7 + E-1…E-6; `as_of` never mixes roots |
| `lib/wrl_world.mjs` (D-048) · `WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json` | TESTED; identities SEALED | 14 tests in `test/wrl_world.test.mjs`: the 10 GPT-required final tests + reconcile + encoding |
| `lib/wrl_world_spike.mjs` · `projections/*/world-spike/` | historical | reproduces the D-037 spike for the mapping test only |
| `tools/identity_matrix.mjs` → `handoff/G0C_IDENTITY_MATRIX.md` | IMPLEMENTED | generated table above |
| `research/R11_STATIC_PROFILE_PRIOR_ART.md` | IMPLEMENTED (research) | prior art behind D-047 |
| G0-D TRVM contract | partly TESTED | canonical bytes + CAS on every record; certificate still PROPOSED |
| G0-F / G0.5 / G1 | PROPOSED | out of scope this round (D-046) |

## Open — for the adjudicator

1. **D-048** — accept the sealed identities as FROZEN, and rule how the measured `sem`/`gsem` hex equality is recorded
   (per-pin measurement, as now, or a stated profile property) and whether `identities.json` keeps the spike mapping.
2. **WRL-P0 follow-ups for the WRL owner** (not gaps in this lane): `OBJECT_ID_RE` restates the kernel's private
   `IDENT_RE`; no `spec.html` D8 rule number exists for static profiles, so no pending-register row could be added.
3. Whether `graphonomous.evidence.v0` (provenance as a WRL-native world, D-041) is wanted before G0-D/G0-F.

## Next smallest step (after acceptance)

G0-D's certificate through the TRVM authority, then G0-F's second source (the factory ledger) — both PROPOSED, neither
started.
