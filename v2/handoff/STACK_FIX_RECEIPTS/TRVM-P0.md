# STACK FIX RECEIPT — TRVM-P0 "Checked Child Protocol Registration" (2026-09-03)

The second change made to a stack layer under the repair protocol, authorized by GPT Adjudication v4 §8 (D-054) after
the G0-D reproducer classified GAP-T9 (D-055). Owning layer: **TRVM certificate authority — the nest checker**
(`governance/nest_check.mjs`, producer `nest_bundle.mjs`). Kernel-adjacent files Graphonomous pins (`certificate.mjs`,
`schema.mjs`, `cas.mjs`, `derive_protocol.mjs`, `observed_execution_host.mjs`): **untouched** (blob OIDs equal).
No derivation-language / `prim` work. No graph primitive.

| | |
|---|---|
| Exposing Graphonomous case | G0-D: `verifiedClaimSemId` mints a `GRAPHONOMOUS-PROJECTION-v0` certificate, but no TRVM judge can check or cite the child — `IMPLEMENTED_CHILD_PROTOCOLS` is frozen, an opts registry is `nest-policy-weakened`, the producer throws `nest-bundle-unknown-child-protocol`, `checkNestBundle` → `nest-child-protocol-unsupported` with `checker_evaluations = 0` |
| Minimal reproducer | `research/probes/g0d/probe_g0d_nest_child.mjs` (+ `.out`), read-only at `fd0df4c`; re-run after the repair without a table: **byte-identical output** (`TRVM-P0/baseline-probe.out` = `after-probe.out`) |
| TRVM commit before → after | `fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873` → **`9e91c96f2d50f3c3bd143fc94ec4267a6b03195a`** (local, not pushed) |
| `nest_check.mjs` blob | `6797c7c828f9…` → `a874edb97783…` |
| `nest_bundle.mjs` blob | `85ae6e9c3967…` → `a7839cc3f728…` |
| `nest_forgeries.mjs` | +7 vectors (36 → 43) |
| `blind-run.json` + 2 receipts | superseded PINNED `brun-c39b708f1d96f2b6df1562d66c33c3eee3d13e2307274e42adbff79025b13ad8` → ABORTED `brun-740403c760e4cadb8131ad208795258eacd3e8af095ba8b5c516b0542d586a1a` → PINNED **`brun-74f54466247c3ccbfcf15ada42242605c7a299961a8b7413e1c914f18fe8c264`**; JS package digest `063c7c63…` → `142e8a88…`; release/package/instrument digests unchanged |
| untouched | `certificate.mjs` `2ee73489…`, `schema.mjs` `4b821c28…`, `cas.mjs` `4b84dff4…`, `derive_protocol.mjs` `8ec73d9b…`, `observed_execution_host.mjs` `29df27f7…`; `compose_check.mjs` (superseded carriage model; not symmetric — no opts, no policy id) |

## The change (design a′ of D-055)

`checkNestBundle(bundle, {store, child_protocols?, …policy})`, `checkNestBytes(raw, {store, child_protocols?, …})`,
`buildNestBundle(children, {protocols?, child_protocols?})`. `child_protocols` is destructured beside `store` and never
reaches `effectivePolicy` (no policy field added). Each entry must be exactly `{claim_field: non-empty string, check:
function, composed: false, checker_id: non-empty string}` under a non-empty, whitespace-free protocol id; extra/missing
keys, `composed: true`, a built-in key, a non-record → refused **before anything is resolved**. The effective table
`Object.freeze({...IMPLEMENTED_CHILD_PROTOCOLS, ...supplied})` is built inside the owned check (own-property lookup at
the dispatch); the built-in table object is byte-identical and frozen. A leaf result is read by shape (a non-record →
verdict `MALFORMED`). When a non-empty table is supplied the measured record carries `child_protocol_set = {builtin,
supplied: [{protocol, checker_id}], child_protocol_set_id}` with `child_protocol_set_id = "nestcps-" +
sha256(NEST_PROTOCOL + "|" + keySortedJSON(sorted [{protocol, checker_id, claim_field}]))`, folded into the reported
`verifier_policy_id` (`nestpol-2701be21…` vs shipped `nestpol-d36eb7e4…`) — a verdict names which checker set produced
it. With no table every verdict, id, measured record, vector and regenerated bundle is byte-identical. The parent still
recomputes every child certificate: a lying supplied checker over a cross-wired citation is refused
(`nest-citation-cross-wired`, `nest-structure-mismatch`).

Required `check(child)` result (documented in the `nest_check.mjs` header): `{ok: boolean, verdict: "VERIFIED"|"REFUSED",
refusals: [{code, detail}], measured: {films_replayed_on_two_classes?, derived_cases?}}`; `child` is the resolved,
canonical, verifier-owned artifact; the checker must write, keep and issue nothing. Graphonomous conforms
(`lib/certificate.mjs` `childProtocolEntry`, `checker_id: graphonomous.g0.certificate.v0`).

**Deviation 1 — no new refusal codes.** `spec_agreement.mjs:116-124` derives the emitted code set by regex over the
checker source and requires equality with the normative schema's 28 `refusal_codes`, digested by `SPEC-RELEASE.json`.
Minting `nest-child-protocol-malformed` / `nest-child-protocol-override-refused` would need a normative schema revision
and a release reissue outside `governance/` and outside this lane. Both refusals therefore ride under the existing
**`nest-policy-weakened`** ("part of the caller's request this verifier will not hold" — the code an unknown policy
field already gets) with greppable details (`… is malformed: …`, `… would OVERRIDE the checker this verifier ships …`);
the vectors assert code AND detail. Filed as **TRVM-P0.1 spec revision** debt (register row GAP-T14), non-blocking.

**Deviation 2 — the blind run was re-pinned.** `blind-run.json` pinned a package digest over `JS_PACKAGE` (which
includes `nest_check.mjs`, `nest_bundle.mjs`), so any byte change turned `gov-nest`/`gov-spec` red on one line, by
design. The tree's remedy was applied: `blind_run.mjs --abort --reason "TRVM-P0 Checked Child Protocol Registration:
nest_check.mjs/nest_bundle.mjs gained a verifier-supplied child_protocols registry (D-055); built-in table and grammar
unchanged"` then `--pin` — deterministic, timestamp-free, no writes under `cas/`, no holdout scoring implied (the pinned
evaluation is `holdout_score.mjs` inside `gov-nest`, which re-ran green). The CLI calls this a human act and asks that
the superseded id be recorded in the ledger; the TRVM ledger is outside this lane, so it is recorded **here**:
superseded `brun-c39b708f1d96f2b6df1562d66c33c3eee3d13e2307274e42adbff79025b13ad8`.

Alternatives rejected (D-055): module-level `registerChildProtocol` (global authority channel; registrants collide);
a CAS descriptor (JSON cannot carry a checker; the citation naming the claim field is the P3 defect).

## Owning-layer test run

- **Before** (`TRVM-P0/failing-before.txt`, vectors added, code at `fd0df4c`): 6 of the 7 new vectors FAIL —
  `registry-alien-leaf-verifies-under-a-supplied-checker` (threw `nest-bundle-unknown-child-protocol`),
  `registry-cannot-override-a-built-in` (`nest-policy-weakened [child_protocols is not a field of this verifier's
  policy]`), `registry-entry-malformed-is-refused-by-name`, `registry-cannot-mint-trust-operand-cross-wired`,
  `registry-cannot-mint-trust-child-moved-under-citation`, `registry-names-its-checker-in-the-verdict`;
  `registry-absent-the-r13-refusal-set-is-verbatim` passes by design (unchanged behaviour). `NEST-FORGERIES: FAIL`.
- **After** (`TRVM-P0/after-*.txt`): gov-proof PASS (PROOF-FORGERIES 24/24, DOMAIN 28/28, COMPOSE 20/20) · gov-nest
  rc=0 — JCS, NEST-CHECK, SPEC-RELEASE, SPEC-VECTORS, **SPEC-AGREEMENT PASS (28 codes, table unchanged)**, FIELD-AUDIT
  46/46, LIVE-DAG, BLIND-PACKAGE, BLIND-RUN (new pin), HOLDOUT 25/25, EXPERIMENT-FALSIFIERS 59/59, **NEST-FORGERIES
  43/43** · gov-spec rc=0 · gov-grid PASS (138 entries, 488 citations) · gov-harness 14/14 + 3/3 · gov-negative
  **392/392** (5m48s). Re-run by the Graphonomous session at `9e91c96`: NEST-FORGERIES 43/43, SPEC-AGREEMENT PASS.
- **Non-regression:** `nest_bundle.json`, `nest_bundle.presentation.json`, `proof_bundle.json`, `domain_bundle.json`,
  `compose_bundle.json` sha256 identical after every battery; `cas/` listing + per-file sha256 identical; SPEC-VECTORS
  verify mode PASS; the R13 probe output byte-identical; 28 distinct `nest-` literals before and after.

## Re-run of the exposing case

`TRVM-P0/graphonomous_child_agreement_vector.mjs` (+ `.out`): AGREEMENT-VECTOR PASS — with the table, VERIFIED on both
boundaries (1 evaluation, set named); without, REFUSED with the verbatim R13 set (0 evaluations, shipped policy id); a
lying checker over a cross-wired citation REFUSED. Graphonomous `test/certificate_trvm.test.mjs` runs the same
agreement against the real baseline child (see STATUS.md for the pin at which the golden vectors are minted).

## Not closed by this receipt

TRVM-P0.1: the two refusal codes deserve their own names in the normative schema (`nested-composition-v2.json`
`refusal_codes`) with a release reissue — a TRVM-owner spec revision. An `Object.prototype` name as a child `protocol`
(`"constructor"`) is now "unsupported" where it was a latent `THREW`; no vector covers it. The (a′) trade-off is
visible by design: a liar's VERIFIED is accepted under a distinct, named policy id — reviewers must read
`child_protocol_set`.
