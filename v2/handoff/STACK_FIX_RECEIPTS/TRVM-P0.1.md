# STACK FIX RECEIPT — TRVM-P0.1 "the refusal vocabulary is a release, not a constant" (2026-09-03)

The **third** change made to a stack layer under the repair protocol (after WRL-P0 and TRVM-P0), required by GPT
Adjudication v5 §5 and recorded as **D-061**. Owning layer: **TRVM's normative proof-wire specification and its nested
composition checker**. This is a *spec/release* closure, not a new capability: TRVM-P0's behaviour is unchanged except
that two refusals now say which of them they are.

| | |
|---|---|
| Exposing case | GPT v5 §5, Deviation 1: TRVM-P0 refused a supplied child-protocol table that would REPLACE a built-in, and one of the wrong shape, and reported **both** as `nest-policy-weakened` — the code for a caller asking to loosen a resource bound. Accepted for P0 (refusal did occur; no false verification is possible from a naming debt) and named as **real normative spec debt**. GAP-T14. |
| Why it mattered | A refusal **SET** is the only thing conformance compares (`TRVM-NESTED-COMPOSITION-v2.md` §7: *"Conformance on negative vectors is compared as a SET"*). Three distinct faults under one code are **one fact** to every reader downstream, and a caller could not tell a table this verifier will not hold from a bound it will not grant. |
| TRVM commit before → after | `9e91c96f2d50f3c3bd143fc94ec4267a6b03195a` → **`8816e59055322fc608c9bc7dae9723c02d8402b7`** (local, not pushed) |
| Spec release before → after | `srel-4844df97e124474e30f100cbe9f8422a99213ac9288f8fcc149086a9a434c952` (revision 1) → **`srel-f5720a3d0ee9dbb95670c9cd66672bf70c7dbe353df0c114a18c8a982f203629`** (revision 2, `spec_digest` `2b4e6cc8…` → `a2337b7f…`); the 16 prior archives are immutable and untouched, the new one is archived beside them |
| Blind run | PINNED `brun-74f54466247c3ccbfcf15ada42242605c7a299961a8b7413e1c914f18fe8c264` → ABORTED **`brun-3925f9521e5cc5bb2ff209cdb610812ad63d36af3b1c37be7e5ac0df34a3c828`** → PINNED **`brun-e553dc1d6cd63e1b9a9ff0aa452e2515bad8888dcf19fdaf5c929f1509cb6cd0`** over `bpkg-9ad5de94…` → **`bpkg-350de8116e9118c2b24e260bc4890fcfce0a7973dbd5a4a168af3cf3df791a04`** |
| `nest_check.mjs` blob | `a874edb97783…` → `aaa8e74304cf…` |
| `spec_agreement.mjs` blob | `461b66664127…` → `79d6f5501421…` |
| `nest_forgeries.mjs` | 43 → **44** vectors |
| **untouched** | all five blobs Graphonomous pins: `certificate.mjs` `2ee73489…`, `schema.mjs` `4b821c28…`, `cas.mjs` `4b84dff4…`, `derive_protocol.mjs` `8ec73d9b…`, `observed_execution_host.mjs` `29df27f7…`. No `prim`. No derivation-language work. `nest_bundle.mjs` untouched (its producer already distinguished the two cases). |

## B1 — dedicated refusal codes

Two codes added, **28 → 30**, alphabetically placed beside `nest-child-protocol-unsupported`:

- **`nest-child-protocol-override-refused`** — a supplied entry would REPLACE a checker this verifier ships.
- **`nest-child-protocol-registration-malformed`** — a supplied table, or one of its entries, is not the shape this
  verifier holds (12 distinct shape failures plus 3 table-level ones).

`childProtocolSet()` now returns a **discriminant** (`{code, refusal}`) instead of `{refusal}` alone; the two emission
sites in `checkNestBytes` and `checkOwned` carry `cps.code`. The two `effectivePolicy` sites **keep**
`nest-policy-weakened` — that is the genuine resource-policy path, and `holdout/H8-policy-weakening.json`
(`max_depth:1000`) and `negative_battery.sh`'s `nest-policy-caller-owned` mutation both still draw it.

**`spec_agreement` was not loosened.** The pin it enforces is mechanical and bidirectional: the normative side is the
`refusal_codes` array in `schema/nested-composition-v2.json`; the implementation side is derived **by regex over
`nest_check.mjs`'s source** for double-quoted `"nest-…"` literals, so a code in one and not the other fails the gate in
whichever direction it is missing. Both declarations were revised, the release was issued, and the gate was re-run.
Falsified deliberately, both directions, before proceeding:

| falsifier | gate |
|---|---|
| rename `"nestcps-"` → `"nestcpsX-"` in the checker | **FAIL** — `id_prefixes.child_protocol_set_id (minted): normative "nestcps-" · implementation "nestcpsX-"` |
| rename `nest-child-protocol-override-refused` in the checker only | **FAIL** — 2 disagreements, one in each direction |
| restore | **PASS** |

## B1a — the gate got BIGGER on the way past (not required; done because the debt's cause was an unchecked declaration)

`constants.id_prefixes` was declared in the normative schema and **compared to nothing**: this checker could have
renamed every prefix it mints and SPEC-AGREEMENT stayed green. TRVM-P0.1 adds `child_protocol_set_id: "nestcps-"` to
that map *and* the comparison that makes declaring it mean something. The implementation side is **not** a table typed
beside the schema's — that would be exactly the tautology `spec_agreement` §1 exists to forbid. It is **the prefix of an
id the tree actually MINTS**, one call per kind:

```
nested_claim_sem_id  ← nestedClaimSemId("CONJUNCTION", IMPLEMENTED_NEST_SCOPE, [])
aggregate_id         ← nestAggregateId({nested_verdict: "VERIFIED"})
structure_sem_id     ← nestStructureSemId({nodes_distinct: 1})
verified_claim_sem_id← verifiedClaimSemId({protocol, claim_sem_id:"c", aggregate_id:"a", chain_ids:{}})
artifact_root        ← rootOfBytes(Buffer.from(""))
verifier_policy_id   ← policyId(SHIPPED_POLICY)
child_protocol_set_id← childProtocolSetId([{protocol:"X-v1", checker_id:"c", claim_field:"f"}])
```

The ids are discarded; only the text before the first `-` is read. What is compared is **the wire**, not a description
of it. New success line: *"…30 refusal codes, **7 id prefixes MEASURED BY MINTING ONE ID OF EACH KIND**, the scope, …"*

## B2 — the blind-run ledger: it EXISTS, and the supersession GPT asked about was already in it

GPT v5 §5 Deviation 2 asked that the supersession be recorded *"in whatever authoritative TRVM ledger the blind-run
protocol requires"*, and forbade inventing one. **Finding: the ledger exists and already held the record.** It is two
parts: `governance/blind-run.json` (the current pointer) and `governance/receipts/brun-<id>.<STATUS>.json` (39 receipts
before this round, 41 after), record type `TRVM-BLIND-RUN-RECEIPT-v2`, walked by `blind_run.mjs` (whose PASS line reads
*"WITNESSED by a receipt chain that reaches PINNED through `previous_run_id`"*).

The TRVM-P0 supersession GPT named is at
`governance/receipts/brun-740403c760e4cadb8131ad208795258eacd3e8af095ba8b5c516b0542d586a1a.ABORTED.json`:
`previous_run_id` = `brun-c39b708f1d96f2b6df1562d66c33c3eee3d13e2307274e42adbff79025b13ad8`, `previous_status` =
`PINNED`, and a `note` naming TRVM-P0 and the files that moved. **Nothing was added; it was verified.**

**The one thing worth reporting** is why it looked like a gap. The new PINNED receipt carries `previous_run_id: null`.
That is not TRVM-P0's irregularity — it is the protocol's direction, and it is measurable:

| status | receipts | carrying `previous_run_id` |
|---|---|---|
| PINNED | 17 | **0** |
| ABORTED | 18 | 14 |
| CANDIDATE_FROZEN | 2 | 0 |
| REVEALED | 2 | 0 |

**An ABORT names what it ended; a PIN starts a chain.** `blind_run.mjs --pin` refuses outright unless the prior status
is `ABORTED` or `COMPLETE` (*"Abort it first with `--abort --reason`"*), so the link is structurally guaranteed to exist
on the abort side. TRVM-P0.1 added its own pair by the same mechanism, because `nest_check.mjs` is in the JS adapter's
`package_files` and its digest moved (`142e8a88…` → `eba6d18a…`).

## B3 — the verification-policy rule, as a measurement rather than a sentence

GPT v5 §4: *"Downstream code must never consume only the bare string `VERIFIED` while discarding the verifier-policy
coordinate… verification without verifier identity is incomplete evidence."* Before this round that rule lived only in
`nest_check.mjs`'s header comment, which no gate executes and which is outside `spec_digest`. It now has three homes:

1. **Normative prose** — `TRVM-NESTED-COMPOSITION-v2.md` gains **§4.3** (the verifier's own coordinates, with both
   preimages, and the statement that `child_protocol_set_id` is folded into `verifier_policy_id` so *one* coordinate
   names both what was bounded and who was allowed to check), **§6.2.1** (the protocol→checker table belongs to the
   verifier and never to the artifact; an artifact MUST NOT be able to name, carry or inject checker code), and a **§8**
   bullet: *"**Not a verdict independent of who checked it.**"*
2. **A law** — `proof.verdict-names-its-verifier` (grid `1.69.0` → `1.70.0`, 138 → 139 entries).
3. **A vector** — `nest_forgeries.mjs` case
   **`a-verdict-token-is-not-a-verdict-VERIFIED-at-two-policies-is-two-facts`**. One artifact, four verifiers:

| verifier | verdict | `child_protocol_set_id` | `verifier_policy_id` |
|---|---|---|---|
| liar table | **VERIFIED** | `nestcps-6ec19dbfdabe…` | `nestpol-d0404435eb7c…` |
| liar table, `checker_id` renamed — *and nothing else* | **VERIFIED** | `nestcps-2f10a7a19a39…` | `nestpol-49b1123300fc…` |
| honest table | REFUSED | — | — |
| no table at all | REFUSED | *(absent)* | shipped |

The first two write the **same token** and are **different verifiers**; the only difference between them is a name. A
consumer that keeps `verdict` alone has kept a string four verifiers would have written differently. The coordinate is
also asserted deterministic across calls — a function of the SET, not of the call.

## B4 — batteries, and what did not move

Run after the change, all from `/home/travis/ProjectAmp2/TRVM`:

| gate | result |
|---|---|
| `make governance` | **32 PASS, 0 FAIL** |
| `make gov-spec` (portable profile, not in `make governance`) | 7 PASS |
| `./negative_battery.sh` | **392/392** — unchanged |
| `node nest_forgeries.mjs` | **44/44** (43 before; the new case is the +1) |
| `node spec_agreement.mjs` | PASS — 10 grammars, 46 fields, **30** refusal codes, **7 minted id prefixes**, 6 policy values |
| `node field_audit.mjs` | 46/46 — unchanged |
| `node grid_check.mjs` | PASS — 139 entries, 488 citations, v1.70.0 |
| `node spec_release.mjs` | PASS — `srel-f5720a3d…`, revision 2 |
| `node blind_run.mjs` | PASS — `brun-e553dc1d…` PINNED |
| holdout | HOLDOUT-COMMITMENT / -AUTHORITY / -HARNESS 25/25 / -SCORE all PASS; `holdout_commitment` `86d437fc…` **unchanged** (no holdout file touched) |

Old refusal meanings: the 28 prior codes are byte-identical in the schema and unchanged in the prose. Existing built-in
child-protocol vectors are byte/identity stable. No application-specific `graphonomous` branch exists anywhere in TRVM.

## The Graphonomous consequence — the sharpest re-mint so far

TRVM-P0.1 moved the **commit** and **not one of the five blobs Graphonomous pins**. `assertTrvmPinned()` reads blobs, so
it would have said nothing; every certificate would have gone on naming a commit that no longer describes the checker's
normative release. **The commit is in the chain precisely for this case.** Re-pinned in `lib/canon.mjs`
(`9e91c96` → `8816e59`) and re-minted; the TRVM-P0 certificates are preserved under `projections/pre-trvmp01/`.

| | baseline | historical | multi |
|---|---|---|---|
| projection root | unchanged | unchanged | unchanged |
| snapshot commitment · `gclaim-` · aggregate · structure · references · adapter contract · schema set | **all unchanged** | **all unchanged** | **all unchanged** |
| TRVM-P0 `vclaim-` (preserved) | `vclaim-c90547a6…` | `vclaim-bf81cc6d…` | `vclaim-cf3b2570…` |
| **TRVM-P0.1 `vclaim-`** | **`vclaim-b4c98a63fdb16d94eaefe88e1b9e9901f4992873b0a88a9817f75f864ffcc113`** | **`vclaim-6bdd6299c2acf277fa7eec67416f585bbe35cfd2eee9f52bd3d6aa775faa15ce`** | **`vclaim-3dd3a476d133a56f02b63a22c9a4770e7278c9a4d5bcb402d085cf5941f747df`** |
| the old receipt under the new checker | REFUSED `[gproj-certificate-stale, gproj-chain-id-mismatch]` | same | same |

**Exactly two codes** — where the G0-F re-mint also carried `gproj-schema-set-mismatch`. The checker still reconstructs
the same root and the same commitment from the same bytes, and writes 0. This is D-060's re-mint semantics with every
other variable held still: *the old certificates verify under their pinned verifier coordinates*, and the current
checker names the one coordinate that moved.

One honest correction found by the test that pins this (`test/factory_certificate.test.mjs`, "pre-TRVM-P0.1 receipts"):
the first draft asserted *"the projector did not move"* and the assertion failed. It was wrong — `lib/canon.mjs` holds
`TRVM_PIN` **and** is a projector module, so re-pinning moves the projector code id as well as the checker's. What does
not move is everything the projector *produced*. The test states the corrected version.
