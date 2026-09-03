# Delta census — package-v2.6 @ `699fbc2` → package-v2.7 @ `ba4e625` (2026-09-02)

Read via `git show <pin>:<path>` only; the working tree was never consulted. Basis for D-025.

## Files

| file | v2.6 blob | bytes | sha256[:16] | v2.7 blob | bytes | sha256[:16] |
|---|---|---|---|---|---|---|
| `CROSS_REGISTRY_CLAIM_MAP.json` | `4639a28d888a54abe5c2a804f4bcfc4278566139` | 85064 | `910cf6eaaf8e4f72` | `c7dba29f2035b84386ac66037693f2ef7c4e05f6` | 108870 | `5d5582e5147377f7` |
| `evidence_state.json` | `8737c78c044543237c3fbfcd4d42ba8f46a6e00d` | 29797 | `1edb46d353b47dd3` | `f1e9b1532f1bb3a96a3bd4cb25203969d0720e26` | 35878 | `cc55f5183ada7fb3` |
| `10_MACHINE_READABLE_LEDGER.json` | `b1cdc96bb55271318e6b97f3d5d34d21fcc36067` | 32374 | `262d2ed08c25ea56` | `53a5cae8c2b45295a3a34a447f080bfdb683a80c` | 36667 | `f7022520f1f96695` |

## Crosswalk

- crosswalk_version: `r10-pre-v2.6-2026-09-02-v3-adjudication-applied` → `r10-pre-v2.7-2026-09-02-v4-adjudication-applied`
- records: 56 → 56; ids added: []; removed: []
- class tokens moved: []
- record fields added (count of records carrying them): `{"evidence_class_token_v2_6": 56, "evidence_class_v2_6": 1, "subject_identity": 5, "adjudication_ref": 6, "adjudicator": 6, "adjudicated_at": 6, "history_note": 1}`; fields removed: none
- top-level keys added: ['adjudication_v2_7', 'execution_summary_v5', 'projection']; removed: []
- promotions: 5 → 5; promotion fields added: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'cross_lane', 'from_detail', 'from_token', 'history', 'subject_identity', 'to_detail', 'to_token']
- promotion tokens (record, from_token, to_token, adjudication_ref): [('E-13b', 'TESTED-CONDITIONAL', 'TESTED-CONDITIONAL', 'inputs/R10PRE_EXECUTION_V4_GPT56_ADJUDICATION.md §1–§2'), ('E-14', 'TESTED-CONDITIONAL', 'TESTED-CONDITIONAL', 'inputs/R10PRE_EXECUTION_V3_GPT56_ADJUDICATION.md §3–§5'), ('E-15', 'live_local', 'TESTED', 'inputs/R10PRE_EXECUTION_V2_GPT56_ADJUDICATION.md §4'), ('E-48', None, 'TESTED', 'inputs/R10PRE_EXECUTION_V3_GPT56_ADJUDICATION.md §12'), ('E-51', None, 'EXHAUSTIVE-IN-MODEL', None)]
- subject_identity on promotions: [('E-13b', {'repo': 'computedriven', 'commit': '747f0256190a1b0a802f37ab90654331ceb45e66', 'tree': '403162623de682f6efa631fc376cc5588125140d', 'artifact_sha256': 'cffc0218fc450884ad2bf4d1630468c675b262e8260ef72b8c90dbf061016303', 'artifact': 'px13/COMPUTEDRIVEN_R086_FOR_GPT.tar.gz'}), ('E-14', {'repo': 'computedriven', 'commit': 'af1cbc2758baeadfbaaa7e2b034347896f9db754', 'tree': 'ef9fcb466da8976d17ecfe15ee87eb092ba14773', 'artifact_sha256': '6ba8544cbf7c91ef526ddde97943d54845e1f352814173b8fa9a64f86867a913', 'artifact': 'px13/COMPUTEDRIVEN_R085_FOR_GPT.tar.gz'}), ('E-15', {'repo': 'computedriven', 'commit': '0b87256', 'artifact_sha256': '525211840abb0b9d381f42537acc896a85e7fceeb49a5238ef90c075bdebf658', 'artifact': 'px13/COMPUTEDRIVEN_R084_FOR_GPT.tar.gz'}), ('E-48', {'repo': 'super', 'commit': '76516978bfa84057d179c0dbdc8a323f512a828b', 'artifact': 'experiments/s5_effect_adapter/vendor_ampd.SHA256SUMS', 'artifact_sha256': '1de5f1600b90dff97e3d0a55765754f99c7ebed2ef276e6dfbd3d48584047698'}), ('E-51', {'repo': 'invariant-r10', 'artifact': 'experiments/s5_effect_adapter/effect_identity_model.py', 'artifact_sha256': '79da87806d8ebc4b3e8dac04e2fa4e6ca58fb9f3d4afc546351bd8b4d8b6a709'})]
- `projection.sha256` in the crosswalk equals sha256 of the pinned `evidence_state.json` bytes: **True**
- promotion sensitivity-witness receipts (record, path, matches at ba4e625, matches at 699fbc2): [('E-13b', 'px13/COMPUTEDRIVEN_R086_FOR_GPT.tar.gz', True, True), ('E-14', 'px13/COMPUTEDRIVEN_R085_FOR_GPT.tar.gz', True, True), ('E-15', 'px13/COMPUTEDRIVEN_R084_FOR_GPT.tar.gz', True, True), ('E-48', 'experiments/s5_effect_adapter/receipts/phase_crash_naive_after.json', True, True), ('E-51', 'experiments/s5_effect_adapter/effect_identity_model.output.txt', True, False)]

### Records that gained fields

- E-01: ['evidence_class_token_v2_6']
- E-02: ['evidence_class_token_v2_6']
- E-03: ['evidence_class_token_v2_6']
- E-04: ['evidence_class_token_v2_6']
- E-05: ['evidence_class_token_v2_6']
- E-06: ['evidence_class_token_v2_6']
- E-07: ['evidence_class_token_v2_6']
- E-08: ['evidence_class_token_v2_6']
- E-09: ['evidence_class_token_v2_6']
- E-10: ['evidence_class_token_v2_6']
- E-11: ['evidence_class_token_v2_6']
- E-12: ['evidence_class_token_v2_6']
- E-13a: ['evidence_class_token_v2_6']
- E-13b: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'evidence_class_token_v2_6', 'evidence_class_v2_6', 'subject_identity']
- E-13c: ['evidence_class_token_v2_6']
- E-14: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'evidence_class_token_v2_6', 'subject_identity']
- E-15: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'evidence_class_token_v2_6', 'subject_identity']
- E-16: ['evidence_class_token_v2_6']
- E-17: ['evidence_class_token_v2_6']
- E-18: ['evidence_class_token_v2_6']
- E-19: ['evidence_class_token_v2_6']
- E-20: ['evidence_class_token_v2_6']
- E-21: ['evidence_class_token_v2_6']
- E-22: ['evidence_class_token_v2_6']
- E-23: ['evidence_class_token_v2_6']
- E-24: ['evidence_class_token_v2_6']
- E-25: ['evidence_class_token_v2_6']
- E-26: ['evidence_class_token_v2_6']
- E-27: ['evidence_class_token_v2_6']
- E-28: ['evidence_class_token_v2_6']
- E-29: ['evidence_class_token_v2_6']
- E-30: ['evidence_class_token_v2_6']
- E-31: ['evidence_class_token_v2_6']
- E-32: ['evidence_class_token_v2_6']
- E-33: ['evidence_class_token_v2_6']
- E-34: ['evidence_class_token_v2_6']
- E-35: ['evidence_class_token_v2_6']
- E-36: ['evidence_class_token_v2_6']
- E-37: ['evidence_class_token_v2_6']
- E-38: ['evidence_class_token_v2_6']
- E-39: ['evidence_class_token_v2_6']
- E-40: ['evidence_class_token_v2_6']
- E-41: ['evidence_class_token_v2_6']
- E-42: ['evidence_class_token_v2_6']
- E-43: ['evidence_class_token_v2_6']
- E-44: ['evidence_class_token_v2_6']
- E-45: ['evidence_class_token_v2_6']
- E-46a: ['evidence_class_token_v2_6']
- E-46b: ['evidence_class_token_v2_6']
- E-46c: ['evidence_class_token_v2_6']
- E-47: ['evidence_class_token_v2_6']
- E-48: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'evidence_class_token_v2_6', 'subject_identity']
- E-49: ['evidence_class_token_v2_6']
- E-50a: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'evidence_class_token_v2_6']
- E-50b: ['adjudicated_at', 'adjudication_ref', 'adjudicator', 'evidence_class_token_v2_6']
- E-51: ['evidence_class_token_v2_6', 'history_note', 'subject_identity']

## evidence_state.json

- top-level: ['schema', 'source', 'records', 'promotions', 'statuses', 'artifacts', 'derived_counts'] → ['schema', 'source', 'generated_by', 'records', 'promotions', 'statuses', 'artifacts', 'derived_counts']
- records 56 → 56; promotions 5 → 5; statuses 1 → 1; artifacts 3 → 3
- executed true: 8 → 8; null: 48 → 48
- receipts remain bare strings (typed receipts: 0)
- statuses[0] keys: ['id', 'status', 'open_findings'] → ['id', 'status', 'open_findings', 'profile', 'out_of_scope']; open_findings count 5 → 1

## 10_MACHINE_READABLE_LEDGER.json

- research_version: `fable51-invariant-discovery-2026-09-02-v2.6-v3-adjudication-applied` → `fable51-invariant-discovery-2026-09-02-v2.7-v4-adjudication-applied`
- claims 19 → 19; changed: []; top-level added: ['adjudication_v4', 'projection']; removed: []

## Verdict

Additive: no record, id or class token moved; new fields and blocks only. One adapter reads both pins with the v2.7 fields optional (D-025).
