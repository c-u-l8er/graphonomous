# WRL SCHEMA / PROFILE — `graphonomous.semantic.v0`

**State: DESIGNED (spec §7.3); authored in G0-C.** The profile is *data in the §D6.1 shape*, validated by G0's own
validator until WRL can load a profile (GAP-W1/W6). Mapping to §D6.1's eight items (R5 §5.1):

| D6.1 item | G0 content | required |
|---|---|---|
| role declarations (not in D6.1's list — the spec-text hole R5 found) | one role per spec §3.1 kind; one nominal port `node`; per-role config keys = the kind's attributes | yes |
| 1 primitive & enumerated types | `lid`, `sha256`, `decimal-string`; one enum per registry evidence vocabulary (crosswalk 11 tokens, factory 8, TRVM 8, research ledger 15, cells 6) — never merged | yes |
| 2 units | none | no |
| 3 relation signatures | domain `semantic`; kinds = spec §3.2; all `directed`, arity 2, roles `source`/`target` | yes |
| 4 endpoint-role constraints | per kind, e.g. `FALSIFIES: source ∈ {FALSIFIER, FINDING, WITNESS, RECEIPT}, target ∈ {CLAIM, LAW}`; `SCOPED_BY: target ∈ {PROFILE, ASSUMPTION}`; `IMPLEMENTS: target ∈ {OBLIGATION, ENFORCEMENT_PROPERTY}` | yes |
| 5 bounded resources | none | no |
| 6 finite resolution tables | none at G0 (folding many WITNESSES into one status is a G1 rule, not a table) | no |
| 7 built-in validators | uniqueness of relation names (seed uniqueness), cardinality (`SUPERSEDES` ≤ 1 successor per record revision), lid grammar | partly |
| 8 canonical defaults | omitted attributes stay omitted (never `"open"`); `texture: solid`; `policy: graphonomous.semantic.rules.v0` | yes |

World identity: `gsem-` + sha256(`serializeArtifact`-rule bytes of the V2-shaped artifact) — never `sem-` (D-009).
Relation identities: WRL kernel `rev-`; the spike's allocation ids are `grelpre-` provisional preimages under the `gsem-` (D-038 — never presented as `rel-`); the real `rel-` is minted by the WRL kernel under the real `sem-` once WRL-P0 seals the profile (D-039).
