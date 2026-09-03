# Graphonomous — D-034 repair → WRL-P0 → final G0-C: return for GPT adjudication

**Date:** 2026-09-03 · **Input rulings:** `GRAPHONOMOUS_G0B1E_GPT_ADJUDICATION_v3.md` (recorded as D-037…D-046) ·
**Bundle:** `graphonomous-g0c-wrlp0-v1.zip` (+ `.sha256`), layout `graphonomous/v2/**` + `WRL/**` + `TRVM/governance/**`
copies under `REPRO_DEPENDENCIES/` (D-033). Every number below is copied from a command output; the generated sources are
`graphonomous/v2/projections/EVIDENCE.md`, `handoff/STATUS.md`, `handoff/G0C_IDENTITY_MATRIX.md`,
`handoff/STACK_FIX_RECEIPTS/WRL-P0.md` and its `WRL-P0/` evidence files.

## 0. Requested ruling

1. Accept **D-037** (D-034 repaired) and the rebuilt B.1/E state as TESTED — checkpoint commit made.
2. Accept **WRL-P0** as the first owning-layer stack repair (receipt, failing-first, non-regression) — WRL commit made.
3. Accept **final G0-C** as TESTED and rule whether its identities are now **FROZEN** (D-042), including **D-048**: the
   measured fact that the spike's bytes equal WRL's canonical bytes (sem hex == gsem hex). Recorded as a measurement,
   never a rename; the sem- was minted by WRL from bytes WRL canonicalized and validated.
4. Rule the three open items in STATUS.md §Open (D-048 recording; WRL spec-text follow-ups; whether
   `graphonomous.evidence.v0` is wanted before G0-D/G0-F).

Nothing was pushed. G0-D/F/UI were not started (D-046). TRVM untouched. WRL kernel (`relation-identity.js`) and spine
(`wrl.js`) untouched — blob OIDs equal before and after.

## 1. Execution order actually run (D-046)

| step | result | commit |
|---|---|---|
| D-034 repair (D-037) + `has_exec_receipt(Subject)` (D-044) + `grelpre-` relabel (D-038) | both projections, both evaluations, both spike worlds rebuilt; pre-D-034 roots preserved under `projections/pre-d034/`; 81/81 | Graphonomous **`3db893a48964bd5eab5ec0e02ee1b5073e912d2e`** (G0-E checkpoint; first commit of `v2/`) |
| WRL-P0 Static Profile + Seal Closure (D-039, D-047) | WRL conformance 890 → **900/0**; failing-first `891 passed, 9 failed` at `1f4c5fd`; `NO BYTE OR ID MOVED` | WRL **`b072db0a983a33108b9a0c4429b978cb07e54148`** (`1f4c5fd` → `b072db0`) |
| Graphonomous WRL pin → `b072db0`; final G0-C through `canonicalizeV2Artifact` / `v2WorldIdOfArtifact` / `deriveV2Relations` (D-048) | real `sem-` at both pins; 588/588 + 566/566 kernel-minted `rel-`/`rev-`; identity matrix measured; 85/85 | Graphonomous **`0da094ad59a45c7d037ec9490fdd7d06f702d51d`** |

## 2. D-034 → D-037: before / after

- Adapter: `TRANSITION --SUPERSEDES--> CLAIM` (2 emission sites) → `TRANSITION --STATE_TRANSITION_OF--> CLAIM`, relation
  attrs unchanged; no SUPERSEDES inferred along the chain. `SUPERSEDES` frozen to same-kind pairs and refused otherwise
  at the lid (`LidError ENDPOINT_REFUSED`), at projection (`G0Error ENDPOINT_REFUSED`) and by WRL (`WRL_UNDECLARED_ENDPOINT_PAIR`).
  `current`/`superseded` rules untouched.
- Roots (baseline / historical): projection `root-0eea954b…` → **`root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85`**;
  `root-2424d836…` → **`root-c7f9c7595c3005b402f263bfe394d767a69adc8e338f7ed2640bfa015375bc87`**. Evaluation `root-cc38ce3b…` →
  **`root-c5d650b0a20902dfa7bc1206be1a2c3257b9699b8734bf825227305fab89715b`** (404 facts / 408 derivations, checker 408/408);
  `root-2afc57ea…` → **`root-edcd9f6f62ab76e876f00ab9401c038dea5dfeb9d2e52ac791185268ed2e9c48`** (393 / 397, 397/397). Ruleset
  `g0rule-0291a139…` → **`g0rule-279caadc7dec1b030ba3657bfa7845504b84da8d387786e670804320d433eef9`** (the `C`→`Subject` rename).
  Manifest entries unchanged (3,005 / 2,893); 64 faults unchanged; `STATE_TRANSITION_OF` 14 · `SUPERSEDES` 0 at both pins.
- `current`: 289 (= every node) / 278; `superseded`: 0; includes E-12, E-13a, E-13b, E-13c, E-14, E-15, E-48, E-51.
- A6 unchanged at both pins: EXEC_RECEIPT_OBSERVED 4 (E-13b, E-14, E-15, E-48) · NO_EXEC_RECEIPT_OBSERVED 0 · UNDECIDABLE 18.
  `has_exec_receipt` subjects: CLAIM 5, EVIDENCE_STATE_TRANSITION 5 (per pin) — the generic rule, the claim partition via `tested_claim`.
- `g0 verify` 3,005/3,005 · 2,893/2,893; Python twin equal at both pins; four-order A8 equal; pre-d034 receipts re-verify.

### A1–A7 (+ continuation tests) after D-037 — `node --test test/query.test.mjs`, over the shipped projections
```
✔ as_of: two snapshots, two roots, never mixed — every record and derived fact carries its own snapshot
✔ A1 — why isn't S6 a primitive? a DERIVED not_primitive whose explanation bottoms out in the crosswalk's resolved_candidates pointer
✔ A2 — what opens R0.8? snapshot-relative: F36/F37 cut at the baseline, F35 (+4 unnamed) at the historical pin; one OPENS relation carries both registries
✔ A3 — what supports S5? E-48 IMPLEMENTS it with an executed, hash-verified receipt (derived has_exec_receipt explains through the assertion's executed flag); E-50a/b, E-51 serve it
✔ A4 — how did E-13b's witness provenance change? the R0.8.5 handback witnesses E-13b+E-14 at v2.6 and E-14 alone at v2.7; roles stay on the assertions
✔ A5 — which mechanisms are represented, on what evidence? two MECHANISM nodes from symbols; mechanism_of derives only from the eight `relation: mechanism` records
✔ A6 — the three-way execution-receipt partition as DERIVED facts (D-022 names), absence only where decidable, no authority inflation
✔ A7 — every answer explains down to exact source assertions and locations: all relations, all derived facts
✔ E-1/E-2 — two source citations of one relation: one relation, two assertions; explain returns both occurrences
✔ E-4 — a tampered derivation is rejected by the independent checker, in memory and from the stored artifact
✔ E-3/E-5 — the shipped evaluation is reproducible (same digest and root from a fresh run); the unnamed finding's identity is container-bound
✔ E-6 — an unqualified unique factory id is resolved AND faulted; the raw token and resolution basis are on the assertion
✔ D-037 (the D-034 ruling): transition → claim is STATE_TRANSITION_OF (14 at both pins), no SUPERSEDES is inferred from the chain (0 at both pins), so the frozen `superseded` rule derives nothing and `current` keeps every claim with a recorded transition
✔ D-037 regression: has_exec_receipt is GENERIC over its subject (rule variable `Subject`): at least one CLAIM and one EVIDENCE_STATE_TRANSITION satisfy it on the shipped baseline, while the A6 partition is unchanged
```

## 3. WRL-P0 — design, alternatives, evidence (D-047; receipt `STACK_FIX_RECEIPTS/WRL-P0.md`)

- **Chosen basis:** `V2_PROFILES` in `relation-v2.js`, frozen data keyed by `profile_id`, rows tagged `derivation:
  "lowered" | "static"`. `forge.world.core.v1` = lowered (declares nothing; V1 lowering as before; rulepack read from
  `V2_RELATION_SOURCE_FAMILIES["2.0"]`, domain from the kernel). `graphonomous.semantic.v0` = static: 21 roles × ports
  `["node"]`, domain `semantic`, signature directed/solid/arity 2, 31 kinds → 92 explicit (source role, target role) pairs,
  policies `["graphonomous.semantic.rules.v0"]`. `v2WorldOfStaticProfile` reads the row and never asks which row. A static
  profile derives `semantic_policies = {rulepack_id}` only (no `schemas`/`state_schema_ref`/runtime policies — D-017);
  downgrade / runtime projection / text surface refuse a static world (a seal is not a run).
- **GAP-W9 closed at the world gate:** `revision.policy ∈ profile.policies` else `WRL_UNDECLARED_POLICY`; validation only.
- **Alternatives rejected:** keying by `ir_version`; a `deriveWorld` function per row; deriving runtime fields from
  defaults; widening `validateAllocation` to `gsem-` (D-038); a separate served data module. Prior art:
  `research/R11_STATIC_PROFILE_PRIOR_ART.md`.
- **Evidence:** `WRL-P0/baseline.txt` 890/0 → `failing-before.txt` `891 passed, 9 failed` (graphonomous seal
  `WRL_UNSUPPORTED_PROFILE`; forge world with `policy: "anything.at.all"` **sealed** to `sem-b9b0c089…`) → `after.txt`
  **`900 passed, 0 failed (70 annotated doc blocks of 115 swept, 26/26 capabilities cited)`**; `bytediff.txt`: DEMO/STARTER
  ids, migration bytes + full `rel-`/`rev-` lists, the forge named specimen, all 5 projection vectors — SAME; verdict `NO
  BYTE OR ID MOVED`; codes 18 → 24 (old ⊂ new), exports 47 → 52, none removed. `reconcile.txt`: WRL row vs the submitted
  declaration, 8/8 facets agree. Minimized reproducer `WRL-P0/graphonomous_seal_reproducer.mjs` → `sem-282c71b6…`,
  `rel-b1180b9b…` / `rev-8da1d819…`, `kernel_agrees: true`.
- **Blobs:** `relation-v2.js` `b5e9ff81…` → `fd1babc5459206c4de1ac1c994b880d24e18ef81`; `test/conformance.mjs` `06c92016…`
  → `ab8e90f9…`; `relation-identity.js` `880cfe04…` and `wrl.js` `19e94ad9…` unchanged.
- **Dispositions:** GAP-W9 CLOSED · GAP-W11 RULED, not widened (D-038) · GAP-W12 RULED, adapter encoding accepted (D-040) ·
  GAP-W13 CLOSED by WRL-P0 (D-041/D-047).

## 4. Final G0-C (D-048)

| | baseline | historical |
|---|---|---|
| WRL pin | `b072db0a983a33108b9a0c4429b978cb07e54148` (3 blobs checked by `assertWrlPinned`) | same |
| **`sem-`** | **`sem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be`** | **`sem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23`** |
| objects / relations / canonical bytes | 1,080 / 588 / 960,827 | 1,052 / 566 / 920,425 |
| kernel-minted `rel-` · `rev-` | 588/588 · 588/588 (588 distinct) | 566/566 · 566/566 |
| example | `rel:g0:ADJUDICATED_BY:claim:crosswalk:E-13b:adjudication:gpt:exec-v4:s1` → `rel-fd541d41d2c31ab95c9f6bb3e22a1fde2c0f49059f35b0cd217fe7171535570e` / `rev-60b8332e2f9e5f8bcc46ae68a09c30b1d4a02f3c1ee27e94bd13861e17ffaede` | `rel:g0:ADJUDICATED_BY:claim:crosswalk:E-14:adjudication:gpt:exec-v3:s3` → `rel-405dc54dde5567528ccc16543da0929b78ee631d0b89bde368968b9ccd1939f3` / `rev-4bd7316b9ae250959f5e66f75ac2300a7e1f77136bc19421a750e7c9b54abcc6` (same `rev-` as baseline; different world → different `rel-`) |
| historical spike (`world-spike/`, mapped in `identities.json`) | `gsem-0f952f03…` — hex equal to the `sem-` (measured) | `gsem-3ae051cf…` (same) |
| projection / evaluation roots | unchanged by the seal | unchanged |

**Identity matrix (D-043; `handoff/G0C_IDENTITY_MATRIX.md`, baseline):** none · shuffle → `sem-` stable, 0/588 `rev-`,
0/588 `rel-`; assertion-only → `sem-` stable, 0/0, **projection root moves**; one relation attribute → `sem-` moves
(`sem-0cdc2992…`), 1/588 `rev-`, 588/588 `rel-`; one node attribute → `sem-` moves (`sem-93aa505e…`), 0/588 `rev-`,
588/588 `rel-`; statement lids stable in every row.

**Refusals measured through WRL:** transition→claim `SUPERSEDES` `WRL_UNDECLARED_ENDPOINT_PAIR` · undeclared kind
`WRL_UNDECLARED_KIND` · unknown profile `WRL_UNSUPPORTED_PROFILE` · undeclared policy `WRL_UNDECLARED_POLICY` · stated
`schemas`/`ports` `WRL_V2_WORLD_MISMATCH` · duplicate seed `WRL_DUPLICATE_RELATION_SEED` · dangling terminal
`WRL_UNKNOWN_ENDPOINT` · undeclared role `WRL_UNDECLARED_ROLE` · duplicate object `WRL_DUPLICATE_ID`.

**The measurement to rule on (D-048).** The spike (D-036) had mirrored WRL's canonicalization exactly and WRL-P0's static
derivation adds nothing to the envelope, so WRL's canonical bytes equal the spike's bytes and the hex halves of `sem-`
and `gsem-` coincide. D-041 said the equality was not required; it did not forbid it. The test asserts it per pin as a
measurement and names the spike "not a seal, whatever its bytes"; every `grelpre-` still differs from its kernel `rel-`
(the allocation scope string differs). Options: keep as a per-pin measurement (as now); promote to a stated profile
property ("a conforming submitter's bytes are WRL's bytes"); or ask for the mapping to be retired to `world-spike/`.

### The 10 required final tests + reconcile/encoding — `node --test test/wrl_world.test.mjs`
```
✔ the WRL pin is b072db0 with three blobs (relation-v2.js is now a live import); every object_id is \w+, decodes back to its lid, and the encoding is injective; a colliding object id is refused by G0 naming WRL_DUPLICATE_ID and by WRL with that code
✔ (1) same semantic input ⇒ same sem-: two seals of the shipped baseline agree with each other, with world/SEM and byte-for-byte with world/artifact.json (WRL canonical bytes)
✔ (2) shuffled records ⇒ same sem- and the same bytes (object and seed order are WRL's, not the submission's)
✔ (3) an assertion-only (provenance) edit ⇒ same sem-, same every rel-/rev- — while the projection root WOULD move (the edited assertion record's canonical bytes and manifest entry change; WRL D8.3, D-041 §8)
✔ (4) one relation semantic edit (attribute) ⇒ that rev- moves, every other rev- holds, sem- moves, EVERY rel- moves (WRL D8.5 / D-043), the statement-lid set is identical
✔ (5) a node semantic edit ⇒ sem- moves, every rev- holds, every rel- moves
✔ (6) the kernel mints: for 5 sampled relations and then the whole set, rel- === relationIdFromAllocation(namedInitialAllocation(sem, relation_name)) and rev- === relationRevisionId(revision), through relation-identity.js directly
✔ (7) no gsem-/grelpre- masquerades at either pin: identities.json carries a historical gsem- ONLY under supersedes.historical_spike_gsem; artifact.json carries no id of any family; sem matches ^sem-[0-9a-f]{64}$; every rel-/rev- is kernel-shaped and labelled wrl-kernel@b072db0
✔ (8) the admitted row's endpoint pairs cover every (kind, source role, target role) triple measured at both pins, and both pins seal (the shipped SEM is what WRL mints today)
✔ (9) WRL refuses, with the codes conformance 21j registers: transition→claim SUPERSEDES WRL_UNDECLARED_ENDPOINT_PAIR · undeclared kind WRL_UNDECLARED_KIND · undeclared profile_id WRL_UNSUPPORTED_PROFILE · undeclared policy WRL_UNDECLARED_POLICY · a stated schemas key WRL_V2_WORLD_MISMATCH (+ duplicate seed, dangling terminal, undeclared role, stated ports); G0's pre-check names the same code where it has one
✔ (10) supersession at both pins: supersedes.historical_spike_gsem equals world-spike/GSEM and what the spike code reproduces from the same projection; the spike receipt's bytes are untouched; MEASURED at b072db0: the spike's bytes EQUAL WRL's canonical bytes, so the sem- hex equals the gsem- hex — an equivalence measured per pin, not a rule (D-041: not required, not forbidden); the spike is not a seal, and no grelpre- equals any kernel rel- (the allocation scope differs: gsem- vs sem-)
✔ declaration reconcile: every facet of V2_PROFILES['graphonomous.semantic.v0'] (the ADMITTED declaration) agrees with handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json (the SUBMITTED one): rulepack, policies, domain, signature, roles, ports, kinds, endpoint pairs
✔ D-037 in the admitted profile: SUPERSEDES is same-kind only, STATE_TRANSITION_OF is transition → claim, the shipped baseline carries 14 / 0, claim → claim SUPERSEDES and a `*` CITES seal
```

## 5. Totals

`npm test` **85 / 85 / 0**; WRL `node test/conformance.mjs` **900 / 0**; `g0 verify` 3,005 + 2,893 clean; `verify-eval`
408 + 397 derivations replayed; Python twin equal at both pins. Re-run from the ZIP (no git needed):
`cd graphonomous-g0c-wrlp0-v1/graphonomous/v2 && node --test test/canon.test.mjs test/lid.test.mjs test/schema.test.mjs
test/rules.test.mjs test/eval.test.mjs test/b1.test.mjs test/query.test.mjs test/wrl_world.test.mjs` (the three WRL
files ride along under `WRL/` as byte copies at `b072db0`). The WRL conformance suite itself is not in the ZIP (the
bundler carries only imported files); run it in a WRL checkout at `b072db0`: `cd WRL && node test/conformance.mjs`.
