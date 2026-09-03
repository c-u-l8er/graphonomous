# Graphonomous G0-D + TRVM-P0 + G0-F — GPT adjudication v5

**Date:** 2026-09-03  
**Input:** `GRAPHONOMOUS_G0D_G0F_FOR_GPT.md` + `graphonomous-g0d-g0f-v1.zip`  
**Verdict:** **ACCEPT freeze recording. ACCEPT G0-D as TESTED. ACCEPT TRVM-P0 as the second owning-layer repair, with TRVM-P0.1 required spec/ledger closure. ACCEPT G0-F as TESTED. Freeze the current G0-D certificates and G0-F v0 multi-world as golden vectors. Open `graphonomous.semantic.v1` now as a measured successor obligation. Keep `graphonomous.evidence.v0` deferred.**

## 0. Independent verification performed by GPT

Uploaded ZIP SHA-256:

`80c4af992975fd1a461093352c3f14558b532e72d0a60588668ad9b8aafce16f`

Internal `SHA256SUMS`:

- 28,630 entries
- 0 missing
- 0 mismatches

GPT independently reran the self-contained tests file-by-file from the ZIP. Combined result:

- **101 PASS**
- **0 FAIL**
- **3 SKIP**

The skips are the explicitly repository-backed cases that require the real pinned source repositories rather than the verification copies in the ZIP.

Independently exercised here:

- canonicalization / Python twin vectors;
- LID and context-bound identities;
- schemas / rules / evaluator;
- statement/assertion model;
- A1–A7 queries and explanations;
- WRL v0 sealing and identity laws;
- G0-D certificate positive/refusal behavior;
- TRVM-P0 child-protocol agreement;
- factory adapter synthetic + shipped-record behavior;
- G0-F certificate sensitivity and old/new snapshot separation.

The full-tree receipts report Graphonomous 121 pass / 0 fail / 1 intentional skip, WRL 900/900, and the listed TRVM governance batteries green. Those repository-wide runs are accepted as submitted receipt evidence, not claimed as independently rerun from this ZIP.

---

# 1. Freeze recording

## RULING: ACCEPT.

D-049…D-054 correctly record the previous adjudication:

- `graphonomous.semantic.v0` remains FROZEN;
- baseline/historical G0-C worlds remain golden;
- D-048 `gsem`/`sem` equality is non-normative;
- WRL-P0.1 spec text remains non-blocking debt;
- `graphonomous.evidence.v0` was deferred;
- G0-D is reconstruction certification, never a truth warrant.

Accept Graphonomous freeze commit:

`b61ff2e`

as a historical checkpoint.

---

# 2. G0-D — `GRAPHONOMOUS-PROJECTION-v0`

## RULING: ACCEPT / TESTED / PROTOCOL SEMANTICS FROZEN.

The certificate model has the right separation.

Freeze the semantic meaning of `GRAPHONOMOUS-PROJECTION-v0`:

> Under the certificate's exact pinned source/snapshot commitment and bound Graphonomous reconstruction protocol coordinates, the verifier reconstructs the exact projection root and structural aggregate claimed by the certificate.

It does **not** certify:

- truth of the graph's claims;
- evidence sufficiency;
- promotion of evidence state;
- authority to mutate any registry;
- TRVM derivation of G0-E facts;
- correctness of an LLM adjudication.

The explicit `scope` fields expressing `truth_claimed:false`, `evidence_sufficiency_claimed:false`, `state_promoted:false`, `registry_written:false`, and `trvm_derivation:false` are accepted.

### Freeze current golden certificate vectors at TRVM `9e91c96`

Baseline:

`vclaim-c90547a6de6d46e5a79750ca897a58f3f4305971c300c567cab712436b7bd851`

Historical:

`vclaim-bf81cc6d8deaa393638f0d13028cf4a6c9f737b7bf4a7c7869bd651fa880e0cf`

Multi-source:

`vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2`

These are golden vectors **at the exact certificate/verifier coordinates recorded in the bundle**.

The corresponding `gclaim-`, `gsnap-`, projection roots, aggregate identities and chain identities are part of each vector and should remain reproducible.

Do not silently change the semantics of `GRAPHONOMOUS-PROJECTION-v0`; a semantic protocol change requires a new protocol version.

---

# 3. Re-mint semantics

## RULING: ACCEPT D-058, with precise terminology.

A Graphonomous `vclaim-` is a **code-/verifier-coordinate-bound certificate receipt**.

Therefore:

- an old certificate remains valid evidence of the reconstruction performed under the verifier/checker coordinates that minted it;
- a newer checker is allowed to refuse that old certificate when the live chain/schema/checker coordinates no longer match;
- such a refusal does **not** mean the old projection root, source commitment or aggregate has retroactively become false;
- re-minting under new checker coordinates creates a **new certificate**, not a mutation, renewal or rename of the old certificate;
- old and new certificate receipts must coexist for historical reproducibility.

For the measured pre-G0-F certificates, the current checker refusing only:

- `gproj-certificate-stale`
- `gproj-chain-id-mismatch`
- `gproj-schema-set-mismatch`

while **not** reporting root/snapshot/aggregate mismatch is exactly the expected diagnostic.

### Vocabulary rule

Use:

> "verifies under its pinned verifier coordinates"

rather than the unqualified:

> "still verifies"

when discussing a historical code-bound certificate.

A future archival verifier resolver could automatically locate/run the pinned checker by chain id, but do not build that unless a concrete consumer needs it.

Never make the current checker accept historical certificates by ignoring chain ids.

---

# 4. TRVM-P0 — Checked Child Protocol Registration

## RULING: ACCEPT as the second Graphonomous-driven owning-layer stack repair.

Accept TRVM commit:

`9e91c96f2d50f3c3bd143fc94ec4267a6b03195a`

for the current G0-D golden vectors.

The design is acceptable because the extension point belongs to the **verifier**, not the child artifact:

- artifacts cannot name/inject executable checker code;
- built-ins cannot be overridden;
- supplied child checkers are explicit verifier configuration;
- the effective checker set is measured;
- `child_protocol_set_id` contributes to the verifier policy identity;
- absent the extension table, the prior behavior and vectors remain byte-identical.

### Critical interpretation

A supplied checker that says `VERIFIED` does **not** create universal TRVM truth.

Its result is scoped to the exact:

- `verifier_policy_id`;
- `child_protocol_set_id`;
- checker id;
- certificate chain.

Downstream code must never consume only the bare string `VERIFIED` while discarding the verifier-policy coordinate.

This is a concrete instance of the broader rule:

> **verification without verifier identity is incomplete evidence.**

Keep that explicit in docs/tests.

---

# 5. TRVM-P0 deviations

## Deviation 1 — overloaded `nest-policy-weakened`

### RULING: ACCEPT FOR P0; REQUIRED FOLLOW-UP `TRVM-P0.1`.

The implementation correctly refused malformed supplied child-protocol entries and attempts to override built-ins, but reused `nest-policy-weakened` because the normative refusal-code set is release-pinned.

That is acceptable for the implementation milestone because:

- refusal occurred;
- tests assert both code and distinguishing detail;
- no false verification is possible from the naming debt.

But this is now real normative spec debt, not an optional cleanup.

### TRVM-P0.1 must add dedicated refusal semantics

At minimum distinguish:

- malformed child-protocol registration;
- attempted built-in child-protocol override.

Perform the proper normative schema/release revision so `spec_agreement` remains a real gate rather than weakening it.

Do not merely loosen `spec_agreement`.

All old valid vectors and old refusal meanings must remain stable.

## Deviation 2 — blind-run re-pin

### RULING: ACCEPT, with ledger closure required.

The re-pin followed TRVM's own abort/pin mechanism and the superseded/aborted/new IDs are preserved in the stack-fix receipt.

That is sufficient for accepting TRVM-P0.

However the next TRVM-owner pass must also record the supersession in whatever authoritative TRVM ledger the blind-run protocol requires.

Do not leave the Graphonomous stack-fix receipt as the only long-term record if TRVM has a canonical owning ledger for the coordinate.

Add this to TRVM-P0.1.

---

# 6. G0-F — factory ledger second source

## RULING: ACCEPT / TESTED.

The factory adapter achieved the intended second-source pressure test:

- factory remains authoritative for its own records;
- crosswalk remains authoritative for its own records;
- deterministic shared identities fold only where explicit identity evidence supports it;
- text/name equality alone does not co-refer;
- ambiguous/unresolved cases remain faults;
- projection/evaluation/certificate all rebuild deterministically;
- source ordering is not semantic;
- removing/narrowing the factory source invalidates the two-source commitment;
- old single-source projections/certificates remain historical receipts.

Accept factory pin:

`d217ee29a3322c68db0d43be47491f0e9d4fbc64`

for this G0-F vector.

### Freeze G0-F v0 multi-source golden vector

Snapshot:

`snapshot:g0:multi-ba4e625-d217ee2`

Projection root:

`root-48ac3e32dfc56cd1450e43b92c7a38d83d71a95113da8b243951dfa305fd2213`

G0-D certificate:

`vclaim-cf3b25705404e1a3d62bf09d26565db0c3362ff8a74b7d7ee25aa6e20d6929b2`

WRL semantic-v0 world:

`sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea`

The exact shipped v0 `rel-`/`rev-` set for the multi world is also a golden G0-F v0 vector.

The old baseline/historical v0 worlds remain unchanged.

---

# 7. `graphonomous.semantic.v1`

## RULING: OPEN IT NOW. DO NOT WAIT FOR A THIRD SOURCE FAMILY.

This is exactly the condition the frozen-v0 guard was designed to expose.

G0-F measured authoritative factory structures that **could not be represented under v0 and were intentionally omitted instead of forcing the profile**:

- 27 ARGUMENT records;
- 68 DEFEATER records;
- argument-premise/evidence/assumption structure;
- defeaters targeting claims, arguments, assumptions, witnesses, receipts and consumption-rule/code targets;
- assumption discharge relations;
- incident semantics;
- additional instrument/process vocabularies.

The fact that the v0-safe subset seals successfully does **not** prove v0 is semantically sufficient. It proves the adapter respected the frozen contract by leaving non-conforming authoritative semantics out.

Therefore open:

`graphonomous.semantic.v1`

as the measured successor profile.

### Accept now, as design direction

Accept:

- `ARGUMENT` as a distinct role, not a CLAIM sub-kind;
- `DEFEATER` as a distinct role, not a FALSIFIER synonym;
- `DISCHARGED_BY` as a distinct relation kind for the measured assumption→claim relation.

The reasoning is sound:

- ARGUMENT has premises/conclusion/evidence and is not merely another asserted claim;
- DEFEATER frequently attacks things other than claims, while FALSIFIER in v0 means a construction/finding that falsifies claim/law semantics;
- overloading `SUPPORTS` in the opposite direction would weaken its existing meaning more than a specific discharge relation does.

### Do NOT freeze the submitted "2 roles / 1 kind / 9 pairs" surface yet.

Before v1 is frozen, perform a **v1 target-completeness audit** over the refused factory layer, especially:

- 34 `consumption_rule` defeater targets;
- the argument-target dictionaries carrying file/revision/digest/section/symbol;
- the exact semantic status of incident FINDING records.

Every authoritative refused structure must receive one explicit disposition:

1. REPRESENTED in v1;
2. DEFERRED because no current semantic consumer requires it, with raw/source evidence preserved;
3. SOURCE-REPAIR because the source form cannot support a semantic identity honestly;
4. OUT-OF-SCOPE process metadata, with a stated reason.

Do not invent a `CONSUMPTION_RULE` role, abuse `SOURCE_LOCATION`, or widen `MECHANISM` merely to make the counts fit.

If the audit shows a tenth endpoint pair or another role is actually the smallest honest representation, change the v1 proposal **before** freezing it.

### v0 non-regression remains absolute

Never edit `graphonomous.semantic.v0`.

v1 must be a new WRL profile row/id.

All v0 baseline/historical/multi golden identities must remain byte-identical.

Statement LIDs shared by v0/v1 remain cross-world semantic names.

---

# 8. `graphonomous.evidence.v0`

## RULING: KEEP `NOT YET`.

G0-F is now the second-source measurement we asked for, and it still does not demonstrate a concrete requirement for provenance/assertion occurrence to participate in WRL world identity.

The present separation remains sufficient:

- projection root = complete observed evidence/provenance;
- G0-E root = derived understanding;
- WRL semantic world = statement/object semantics;
- G0-D certificate = reconstruction receipt over the projection.

Do not create an evidence WRL profile merely for symmetry.

Re-open `graphonomous.evidence.v0` only when a concrete consumer requires at least one of:

- provenance relation allocation that must be world-addressable through WRL;
- evidence-world identity independent of the projection/CAS root;
- cross-world composition of assertion/provenance objects;
- a query/authority/certificate operation impossible to state correctly with the current projection-root separation.

G0.5 UI does not automatically count: it may display projection assertions directly.

---

# 9. Next development order

Proceed:

`record v5 adjudication`
→ `TRVM-P0.1 spec/ledger closure`
→ `semantic.v1 target-completeness audit`
→ `semantic.v1 profile + factory argument/defeater ingestion`
→ rebuild projection/evaluation/certificate
→ seal v1 world through WRL
→ `G0.5 minimal read-only Graphonomous UI`
→ stop for GPT adjudication.

TRVM-P0.1 and the v1 pre-freeze research may run in parallel, but their commits/receipts remain separate owning-layer work.

Do not start broad G1/autonomous mutation/primitive-basis work in this round.

---

# 10. G0.5 demo objective

The backend has now earned a visible vertical-slice demo.

G0.5 should prove that a human can inspect the actual ComputeDriven understanding graph without losing the identity/evidence boundaries already proven.

Minimum read-only surfaces:

1. snapshot selector: baseline / historical / multi / v1 multi if built;
2. semantic graph view over statement LIDs;
3. node inspector: role, semantic attrs, evidence state, source-family assertions;
4. relation inspector: statement LID, WRL `rev-`, world-scoped `rel-`, assertion occurrences;
5. explanation panel backed by G0-E `explain`, clearly distinguishing `observed` vs `derived` and showing `trvm_derivation:false`;
6. provenance/source-location drill-down;
7. fault panel;
8. identity panel showing projection root, evaluation root, G0-D certificate, WRL `sem-`, and snapshot commitment;
9. executable examples for A1–A7;
10. if v1 is built, ARGUMENT/DEFEATER exploration.

No Graphonomous truth writeback, registry mutation, evidence promotion or autonomous repair UI yet.

Layout coordinates, open panels, filters and viewport state remain non-semantic UI state and must not move projection/WRL identities.

The UI implementation language/framework is host machinery; it does not need to be WRL. The **semantic data/world it renders is the WRL-sealed Graphonomous world**.

---

# 11. Acceptance state after this adjudication

- G0-C / `graphonomous.semantic.v0`: FROZEN
- Freeze recording D-049…D-054: ACCEPTED
- G0-D: **TESTED / current golden vectors frozen**
- `GRAPHONOMOUS-PROJECTION-v0`: **semantic protocol frozen**
- TRVM-P0: **ACCEPTED**
- TRVM `9e91c96`: accepted current G0-D pin
- TRVM-P0.1: **REQUIRED NEXT / non-blocking to existing vectors**
- G0-F: **TESTED**
- G0-F multi v0 world/certificate: **golden**
- `graphonomous.semantic.v1`: **OPEN / PROPOSED, build next after target audit**
- `graphonomous.evidence.v0`: **NOT YET**
- G0.5 minimal read-only UI: **AUTHORIZED after v1**
- broad G1 / autonomous mutation / primitive-basis round: not this round
