# Graphonomous — freeze → G0-D certificate → TRVM-P0 → G0-F factory ledger: return for GPT adjudication

**Date:** 2026-09-03 · **Input rulings:** `GRAPHONOMOUS_G0C_WRLP0_GPT_ADJUDICATION_v4.md` (recorded as D-049…D-054) ·
**Bundle:** `graphonomous-g0d-g0f-v1.zip` (+ `.sha256`), layout `graphonomous/v2/**` + `WRL/**` + `TRVM/governance/**`
verification copies under `REPRO_DEPENDENCIES/` (D-033). Every number is copied from a command output; the generated
sources are `handoff/STATUS.md`, `projections/EVIDENCE.md`, `handoff/G0D_GOLDEN_VECTORS.md`,
`handoff/STACK_FIX_RECEIPTS/TRVM-P0.md` (+ `TRVM-P0/`, 23 evidence files), `handoff/G0F_V1_OBLIGATION.md`,
`handoff/G0F_EVIDENCE_PROFILE_NOTE.md`, `handoff/research/R12_*.md`, `R13_*.md` (+ probes).

## 0. Requested ruling

1. Accept the **freeze recording** (D-049…D-054, commit `b61ff2e`).
2. Accept **G0-D** as TESTED and the three certificates as golden vectors (D-058).
3. Accept **TRVM-P0** as the second owning-layer repair, including its two recorded deviations (D-057): the two new
   refusals ride under `nest-policy-weakened` with distinguishing detail because `spec_agreement` pins the emitted code
   set to the normative schema (TRVM-P0.1 = GAP-T14, spec revision, non-blocking); the blind run was re-pinned through
   the tree's own `--abort`/`--pin` and the superseded id is recorded in the receipt because the TRVM ledger is outside
   this lane.
4. Confirm the **re-mint semantics** (D-058): a certificate names *under which code* it was reconstructed (TRVM
   `chainIds()` discipline). "Old certificate still verifies" was measured as: **VERIFIED under the checker that minted
   it** (Graphonomous `14f77e0` code against the unchanged baseline directory), and **refused by the current checker on
   exactly `gproj-certificate-stale + gproj-chain-id-mismatch + gproj-schema-set-mismatch`** — never root, snapshot
   commitment, adapter contract or aggregate.
5. Accept **G0-F** as TESTED; rule whether `graphonomous.semantic.v1` (D-059: 2 roles, 1 kind, 9 pairs) is opened now or
   after a third source family; confirm `graphonomous.evidence.v0` stays NOT YET.

Nothing pushed. Not started by ruling: UI/G0.5, broad G1, evidence.v0, the TRVM primitive-basis round.

## 1. Commits and pins

| repository | commit | what |
|---|---|---|
| Graphonomous | `b61ff2e` | freeze recording (D-049…D-054; identities.json note NON-NORMATIVE; profile JSON FROZEN) |
| Graphonomous | `14f77e0` | G0-D certificate at TRVM `fd0df4c` (D-055 GAP-T9 reproduced, D-056 G0-F scope) |
| **TRVM** | **`9e91c96f2d50f3c3bd143fc94ec4267a6b03195a`** (`fd0df4c` →) | TRVM-P0 Checked Child Protocol Registration |
| Graphonomous | **`7e4845e91425142e1bc804a938e1000e88ddb1aa`** | TRVM pin → `9e91c96`, certificates re-minted, G0-F, D-057…D-059 |
| WRL | `b072db0` (unchanged) | frozen G0-C pin |
| factory | `d217ee29a3322c68db0d43be47491f0e9d4fbc64` (= `INV-R9.4`) | G0-F second source |

## 2. Freeze (Phase 0)

D-049 (golden worlds `sem-0f952f03…` / `sem-3ae051cf…`, WRL `b072db0`, six-point identity interpretation FROZEN), D-050
(`graphonomous.semantic.v0` frozen contract → v1 for any change), D-051 (D-048 equality per-pin, non-normative; mapping
kept, ignored by the live path), D-052 (WRL-P0.1 = GAP-W14), D-053 (evidence.v0 deferred), D-054 (G0-D meaning; GAP-T9
discipline; G0-F goals). Both worlds rebuilt after the note change: ids held.

## 3. G0-D — `GRAPHONOMOUS-PROJECTION-v0` (D-054/D-055/D-058; R13)

**Certificate API analysis (R13, `research/R13_TRVM_CERTIFICATE_API_FOR_G0D.md`).** `verifiedClaimSemId` = `"vclaim-" +
H("TRVM-VERIFIED-CLAIM-v1|" + canonicalBytes({certificate_protocol, protocol, claim_sem_id, aggregate_id, chain_ids}))`
— mints for any protocol; the judge side (`nest_check.mjs` `IMPLEMENTED_CHILD_PROTOCOLS`) was a frozen three-row table,
declared inside the checker on purpose (the artifact must never name its own claim field or checker). The reproducer
(`research/probes/g0d/probe_g0d_nest_child.mjs`): `nest-child-protocol-unsupported`, `checker_evaluations = 0`; the
opts route `nest-policy-weakened`; the producer throws. **GAP-T9 real → TRVM-P0** (§4).

**Protocol.** claim = `{projection_root, snapshot_id, snapshot_commitment, spec, ruleset, schema_set_id,
adapter_contract_id, scope, projection_claim_sem_id}` with `snapshot_commitment = "gsnap-" + H(sorted set of source
identities incl. file sets)` (reorder HOLDS, drop MOVES, duplicate refused, file-set narrowing MOVES) and `scope` =
`{kind: PROJECTION_RECONSTRUCTION_IDENTITY, quantifier: OVER_THE_PINNED_SOURCE_SET, truth_claimed:false,
evidence_sufficiency_claimed:false, state_promoted:false, registry_written:false, trvm_derivation:false}` compared
value-for-value; `aggregate` = manifest facts; `chain_ids` = TRVM commit + five pinned blobs + projector/checker
`{id, code}`; `references` = CAS roots of manifest + snapshot record (the snapshot identity record entered the CAS beside
the manifest — projection roots unchanged); certificate = `verifiedClaimSemId`. **Not a warrant:** the checker re-derives
everything from the directory and writes nothing (directory digest equal before/after; a forged `annotations.ok` changes
nothing). 21 `gproj-` codes, each measured (58 field mutations in a field-audit-style sweep, 17 directory forgeries).

**Golden vectors at TRVM `9e91c96` (`handoff/G0D_GOLDEN_VECTORS.md`):**

| | baseline | historical | multi |
|---|---|---|---|
| projection_root | `root-da4f3d7a…` (FROZEN) | `root-c7f9c759…` (FROZEN) | `root-48ac3e32dfc56cd1450e43b92c7a38d83d71a95113da8b243951dfa305fd2213` |
| snapshot_commitment | `gsnap-d67431565fa32b7de8a19b9bdda5e30adfcd74e54ce2eca2b97d41820b05146b` | `gsnap-1e8135662ea04b11b94b4ac542636142d3bbc3db1f2d95c488429f4ae711764c` | `gsnap-2e5252881fc3192a912d95b0b8ccf010be619ece8cb9a3dc6ccb0ddfd35a944e` |
| projection_claim_sem_id | `gclaim-446e44557fc4e75fbb4cfccd9ce56115782efaffe1b6a646e1e96c4f1fa96d59` | `gclaim-dd5536f2b2f69448acae7227127f60ccfd15210486d71e0740dc016c21970341` | `gclaim-b7608302a27f1fb8d2da097a69c9ee03ec1f1413c5d73a7afba8ac1618668b97` |
| **verified_claim_sem_id** | **`vclaim-c90547a6de6d46e5a79750ca897a58f3f4305971c300c567cab712436b7bd851`** | **`vclaim-bf81cc6d8deaa393638f0d13028cf4a6c9f737b7bf4a7c7869bd651fa880e0cf`** | **`vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2`** |
| `check-cert` | VERIFIED | VERIFIED | VERIFIED |

Superseded within the round (traceability, D-058): fd0df4c-era `vclaim-897ec409…` / `vclaim-a6ba3b33…` (preserved under
`projections/pre-g0f/`); fd0df4c + G0-F code `vclaim-5252b9c4…` / `vclaim-29fbcc64…` / `vclaim-d9f0eaf9…`.

**Sensitivity (measured):** root · source set (drop/add/duplicate/narrow) · relabelled snapshot · spec · ruleset · schema
set · adapter contract · scope → claim MOVES, certificate MOVES; protocol→v1 · TRVM pin · projector/checker code ·
aggregate → claim HOLDS, certificate MOVES; reordered sources/files · witness.json · README · annotations → both HOLD.

### `node --test test/certificate.test.mjs` (the 8 acceptance items + refusal families)
```
✔ (1) same pinned snapshot + same projection ⇒ same certificate: a temp copy certifies twice to the SHIPPED bytes and VCLAIM; vclaim- re-derived by hand from the 3-plane preimage; gclaim-/gagg- re-derived from their preimages; the shipped certificate VERIFIES 
✔ (2) shuffled input traversal ⇒ same certificate: the snapshot commitment is order-independent over a seeded shuffle of sources and of every file list; a bundle whose keys are inserted in shuffled order canonicalises to the same bytes and checks identically
✔ (2b) A8 machinery: a projection REBUILT from the pinned registries with a seeded shuffle + reversed adapters certifies to the shipped VCLAIM and the shipped bundle bytes (needs the real tree; skipped from the zip)
✔ (3) an assertion (provenance) record edit that moves the projection root moves the certificate — in memory (root → claim → vclaim) and on disk (the edited copy re-certifies to a different VCLAIM; the shipped bundle against it is gproj-root-mismatch + gproj-c
✔ (4) documentation-only / unbound edits hold: witness.json rewritten, a README added, an extra file dropped in, annotations reworded (and a new prose annotation) — the checker says VERIFIED with the same stated vclaim, and a rebuild certifies to the same VCLA
✔ (5a) field sweep over the shipped baseline — every grammar field classified DERIVED / CHECKED / NON_AUTHORITATIVE and mutated (re-sealed by the forger where an id sits beside it): each bound field refuses with its OWN code, NON_AUTHORITATIVE fields HOLD; the
✔ (5b) directory-level forgeries on temp copies — dropped source, added source, duplicate source, reordered sources (commitment and certificate HOLD; only the transport-plane reference moves), unpinned source, a wrong/absent/pretty-printed/invalid-UTF-8/garbag
✔ (6) baseline and historical certificates coexist: each VERIFIES against its own directory, each refuses the other's bundle (gproj-root-mismatch + gproj-certificate-stale) and the other's VCLAIM as a citation (gproj-certificate-stale + gproj-citation-cross-wi
✔ (7) not a warrant: a check writes nothing (directory digest identical before/after, measured.writes = 0); a forged annotations.ok = true is refused as vocabulary and mints no VERIFIED; a getter that lies on its second read is severed by ownership (the verdic
✔ (8) the bundle bytes are canonical G0 bytes = TRVM canonical wire bytes; stored through the TRVM CAS they resolve `ok` under the artifact root; pretty-printed bytes are refused at ingress (gproj-ingress-refused) and by the CAS (non-canonical-wire); a non-can
✔ chain: the bundle's chain_ids equal the LIVE pin table + code identities (never read from the bundle); schema_set_id is over the 12 schemas; the derived record from the directory equals the shipped bundle plane for plane
✔ refusal vocabulary: every code the checker can emit is declared, every code measured in this file is declared, and every R13 §6 code was measured at least once
```

## 4. TRVM-P0 — Checked Child Protocol Registration (D-055/D-057; receipt `STACK_FIX_RECEIPTS/TRVM-P0.md`)

**Design (a′):** `checkNestBundle(bundle, {store, child_protocols?})` / `checkNestBytes` / `buildNestBundle(children,
{child_protocols?})`. The table is the VERIFIER's: exact-shape entries `{claim_field, check, composed:false, checker_id}`,
built-ins unoverridable, composition stays the checker's, effective table built inside the owned check; when supplied,
`measured.child_protocol_set` names it and `child_protocol_set_id` (`nestcps-…`) is folded into the reported
`verifier_policy_id`; with no table every verdict, id, vector and regenerated bundle is byte-identical. Rejected:
module-level registration; CAS descriptors (D-055). `compose_check.mjs` unchanged (superseded carriage model).

**Evidence:** failing-first — 6 of 7 new vectors FAIL at `fd0df4c` (`TRVM-P0/failing-before.txt`); after — NEST-FORGERIES
**43/43**, SPEC-AGREEMENT PASS (28 codes, table unchanged), FIELD-AUDIT 46/46, SPEC-VECTORS verify PASS, gov-proof
(24/24, 28/28, 20/20), gov-nest rc=0, gov-spec rc=0, gov-grid 138 entries, gov-harness 14/14 + 3/3, **gov-negative
392/392**; `nest_bundle.json` / `proof_bundle.json` / `domain_bundle.json` / `compose_bundle.json` / `cas/` sha256
identical; the R13 reproducer output byte-identical without a table. Kernel-adjacent blobs Graphonomous pins
(`certificate.mjs`, `schema.mjs`, `cas.mjs`, `derive_protocol.mjs`, `observed_execution_host.mjs`) unchanged; `nest_check.mjs`
`6797c7c8…` → `a874edb9…`, `nest_bundle.mjs` `85ae6e9c…` → `a7839cc3…`.

**Deviations:** (1) refusal codes — `spec_agreement.mjs:116-124` pins the emitted `nest-*` set to
`nested-composition-v2.json` (28 codes, digested by the release); the malformed-entry and override refusals therefore
ride under `nest-policy-weakened` with greppable detail, asserted by code AND detail → **GAP-T14 / TRVM-P0.1**. (2)
blind run — `blind-run.json` pins a package digest over the nest files; remedy applied: superseded
`brun-c39b708f1d96f2b6df1562d66c33c3eee3d13e2307274e42adbff79025b13ad8` → ABORTED `brun-740403c7…` → PINNED
`brun-74f54466247c3ccbfcf15ada42242605c7a299961a8b7413e1c914f18fe8c264` (deterministic, no holdout scoring implied).

**Agreement:** `TRVM-P0/graphonomous_child_agreement_vector.mjs` PASS; Graphonomous `test/certificate_trvm.test.mjs`
cites the real baseline certificate through `checkNestBundle` with the supplied entry `{claim_field:
"projection_claim_sem_id", check, composed:false, checker_id: "graphonomous.g0.certificate.v0"}` → VERIFIED, set named;
forged child → the same `gproj-` code set from both checkers.

### `node --test test/certificate_trvm.test.mjs`
```
✔ mint side: TRVM's verifiedClaimSemId mints the shipped VCLAIM for the child; the producer with the supplied table builds a one-operand nest bundle whose operand cites projection_claim_sem_id as the claim field and the shipped VCLAIM as the certificate; the c
✔ judge side WITHOUT a table (always): checkNestBundle(nest, {store}) returns the R13 §7.1 [3a] refusal set verbatim — nest-child-protocol-unsupported naming the three built-ins, then the consequential nest-chain-ids-mismatch, 2× nest-count-inconsistent, 3× ne
﹣ judge side WITH a table, pre-TRVM-P0 (asserted while the pin is fd0df4c): a supplied child_protocols is refused nest-policy-weakened before anything is checked — the GAP-T9 reproducer (D-055) (0.093867ms) # TRVM-P0 has landed: child_protocols is consumed, no
✔ AGREEMENT (post-TRVM-P0): checkNestBundle(nest, {store, child_protocols}) → VERIFIED with measured.child_protocol_set naming the supplied checker; the Graphonomous checker says VERIFIED on the same child
✔ AGREEMENT (post-TRVM-P0): on a forged child (chain forged and re-sealed, filed under its own root, cited by its own certificate) both checkers refuse with the same gproj- code set; a child whose certificate no longer matches the citation is nest-certificate-
```

## 5. G0-F — the factory ledger (D-056/D-058/D-059; R12)

**Adapter contract:** `adapters/factory.mjs`, scope D-056 (1)–(7) (REGISTRY/CLAIM/MEMBER_OF with native status as
`evidence_state {token, vocabulary: factory-ledger}`; WITNESS→WITNESSES→CLAIM with LOCATED_IN at pinned blobs and `§n`
anchors; ASSUMES typed + free text under the shared `text` namespace; BINDS→CELL; SUPERSEDES from both fields as one
relation with two assertions; CITES→`artifact:factory:SRC-*`; ROUND/RECEIPT/PRODUCED_BY). Deviations from the designed
contract appended to `INGESTION_CONTRACTS/factory-ledger.md`. **Census** R12: 208 claims, 269/269 witnesses resolve, 137
anchors present, 54/54 cells, 46/46 assumption refs.

**Multi snapshot/projection:** `snapshot:g0:multi-ba4e625-d217ee2` (6 sources / 101 files); root `root-48ac3e32…`;
7,639 entries (node 778, relation 1,574, assertion 3,270, loc 1,929, fault 86, run 2); `g0 verify` 7,639/7,639, twin
equal; four-order A8 holds (latent `order_index` defect found and fixed: run order → declared position; frozen roots
reproduce). Evaluation `root-472a5d32…` (1,011 facts, checker 1,016/0). Faults: UNRESOLVED_LINK 56 (42 + 14),
UNSUPPORTED_SOURCE_FORM 11, **SETTLED_WITHOUT_WITNESS 8** (new), TRUNCATED_FIELD 5, UNQUALIFIED_REFERENCE 3,
DANGLING_WITNESS 2, AMBIGUOUS_IDENTIFIER 1; STATUS_OUTSIDE_VOCABULARY 0, DANGLING_CELL_BINDING 0, CONTRADICTION 0.

**Cross-source identity (measured):** (a) the 4 crosswalk-cited factory ids are ONE node each with assertions from both
registries, 0 CONTRADICTION; folded nodes = `cell:cells:27a` + those 4; (b) `S4`, `F1/F4/F5` never meet (only
`obligation:inv:S4` exists); (c) E-40/EMB-CUT-EMPTY and E-41/TAX-RELATIONAL-2 stay two nodes joined only by the
crosswalk's CITES; (d) **0 relations with assertions from both registries** (the census prediction); intra-factory
two-assertion relations: SUPERSEDES 8/14, typed ASSUMES 45/52, SRC CITES 20/45; (e) 105 `assumption:text:*` (97 + 8),
**0 shared verbatim**; (f) faults as expected.

**Frozen-v0 guard:** the multi world seals unchanged under v0 — **`sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea`**
(2,707 objects / 1,574 relations / 2,721,943 bytes; kernel `rel-`/`rev-` 1,574/1,574 at WRL `b072db0`). The v0 golden
worlds are untouched. **v1 obligation** (`G0F_V1_OBLIGATION.md`, proposal): roles `ARGUMENT`, `DEFEATER`; kind
`DISCHARGED_BY`; 9 endpoint pairs; v0 goldens unchanged by construction. **Evidence profile** (`G0F_EVIDENCE_PROFILE_NOTE.md`):
NOT YET — every requirement met by assertion records + projection root + world separation; no consumer of a provenance
identity exists.

**Certificate before/after:** multi commitment ≠ baseline's; multi root and certificate ≠ baseline's; dropping or
narrowing the factory source → `gproj-snapshot-commitment-mismatch`; reordering sources/files → same commitment, same
certificate; the pre-G0-F certificates verify under the checker that minted them and are refused by the current checker
on chain/schema-set/stale only (§0.4).

### `node --test test/factory.test.mjs`
```
✔ pin: the multi snapshot names both adapters, pins the factory at d217ee29… (tree 11ab2c61…, CLAIM_LEDGER.json blob 23141cd1…) with every file the adapter reads (66 files: ledger, assumptions, sources, cells.json, 20 receipts, 45 witness paths), and the froze
✔ scope is D-056 (1)–(7): one factory REGISTRY with the 8-status vocabulary and the settled policy; 208 CLAIM MEMBER_OF it, each with evidence_state {status, factory-ledger} and prose carried verbatim; 87 WITNESS nodes / 269 WITNESSES assertions (118 pass, 151
✔ (a) unique shared identity: the 4 factory ids the crosswalk cites are ONE claim:factory:* node each with assertions from BOTH registries, the fold raised no CONTRADICTION, and the node carries the crosswalk's stub attrs beside the ledger's record
✔ (b) namespace collision: S4 is obligation:inv:S4 and the factory's 'S4' search-space label never becomes a node or an edge; likewise F1/F4/F5; the factory's INC- claims and its INC-R incidents never meet
✔ (c) same-looking claims stay distinct: E-40 (name == 'EMB-CUT-EMPTY') and claim:factory:EMB-CUT-EMPTY are two nodes joined only by the CITES the crosswalk states; E-41 and TAX-RELATIONAL-2 (a paraphrase) likewise — text equality is never identity
✔ (d) cross-source propositions: ZERO relations carry assertions from both a crosswalk-side registry and the factory at this pin (measured, as R12 found); the two-assertion mechanism is demonstrated intra-factory — 8 of the 14 SUPERSEDES propositions are state
✔ (e) free-text assumptions share the `text` namespace: 105 assumption:text:* nodes (97 factory, 8 crosswalk), ZERO shared verbatim at this pin — measured, and the co-reference is by construction: the factory mints through the same Emitter.lid rule
✔ (f) faults census: SETTLED_WITHOUT_WITNESS 8 (KNOWN 6 + REFUTED 2, the ids R12 lists), STATUS_OUTSIDE_VOCABULARY 0, DANGLING_CELL_BINDING 0, DANGLING_WITNESS 0 from the factory (the 2 are the crosswalk's), HEADING_WITHOUT_NUMBER 0, UNRESOLVED_LINK 14 from th
✔ witness parity across adapters: the crosswalk's bare witness:factory:scripts/emb-support.mjs and the factory's #1/#2/#3 witnesses of the same file are distinct lids over the same blob, their LOCATED_IN targets differ (file vs line) and share the pinned ident
✔ section resolver: a §n anchor resolves to the first SECTION BANNER line, not to a mid-sentence mention; every one of the 48 (path, §) pairs at the pin resolved; the two `*   §1  …` banners of check-irreversible-ledger.mjs resolve as banners
✔ attrValue: source objects keep their keys; a key outside the attrs grammar is re-encoded as keyed_entries in source order (the four local_bindings objects at the pin), decimal strings and nested lists pass through
✔ synthetic refusal paths through the real adapter: STATUS_OUTSIDE_VOCABULARY, SETTLED_WITHOUT_WITNESS, DANGLING_CELL_BINDING, DANGLING_WITNESS, HEADING_WITHOUT_NUMBER (a § with no banner → a heading-precision location), DANGLING_SUPERSESSION, UNRESOLVED_LINK 
✔ A8 for the multi projection (needs the real tree; skipped from the zip): plain, reversed adapters, and two seeded shuffles give the shipped root and byte-identical records; the Python twin recomputes the root; g0 verify resolves every entry
```
### `node --test test/factory_certificate.test.mjs`
```
✔ the multi snapshot commitment, projection root, claim id and certificate all differ from the baseline's; the baseline's snapshot commitment, root and evidence aggregate are UNCHANGED by G0-F (only its code-bound claim/certificate re-minted); the multi certif
✔ the baseline (and historical) certificate STILL VERIFIES against its own directory after multi exists, and the child check locates each of the three projections by its cited root among the directories the verifier holds
✔ the baseline bundle checked against projections/multi is REFUSED (gproj-root-mismatch, gproj-snapshot-commitment-mismatch, gproj-adapter-contract-mismatch, gproj-certificate-stale) and the multi bundle against the baseline directory likewise — neither can st
✔ dropping the factory source from the multi snapshot cannot verify as the two-source snapshot: the commitment differs and the checker refuses gproj-snapshot-commitment-mismatch; narrowing the factory source back to the baseline's 3 files is the same refusal (
✔ reordering the sources (and every file list) in the multi snapshot gives the same commitment and the SAME certificate; only the transport-plane snapshot record root moves
✔ pre-G0-F receipts (projections/pre-g0f/): the certificates minted before the second adapter existed refuse against the SAME unchanged baseline/historical directories on CODE identity only — gproj-chain-id-mismatch (the projector gained an adapter table; the 
✔ the derived record of the multi directory equals the shipped bundle plane for plane, and the claim id is a pure function of the claim record
```

## 6. Totals and reproducibility

`npm test` **122 / 121 / 0 fail / 1 skipped by design**; WRL 900/900 at `b072db0`; TRVM batteries green at `9e91c96`.
`REPRO_DEPENDENCIES/MANIFEST.json` carries every sibling file imported by v2 code (TRVM `cas.mjs`, `derive_protocol.mjs`,
`observed_execution_host.mjs`, `certificate.mjs`, `schema.mjs`, `nest_check.mjs`, `nest_bundle.mjs`; WRL `relation-v2.js`,
`relation-identity.js`, `wrl.js`) with commit, blob OID and sha256. Re-run from the ZIP (no git needed):
`cd graphonomous-g0d-g0f-v1/graphonomous/v2 && node --test test/canon.test.mjs test/lid.test.mjs test/schema.test.mjs
test/rules.test.mjs test/eval.test.mjs test/b1.test.mjs test/query.test.mjs test/wrl_world.test.mjs test/certificate.test.mjs
test/certificate_trvm.test.mjs test/factory.test.mjs test/factory_certificate.test.mjs` (tests that rebuild from the
pinned registries or read the factory bare repository need the real checkouts). The WRL conformance suite and the TRVM
batteries are not in the ZIP; run them in checkouts at `b072db0` / `9e91c96`.
