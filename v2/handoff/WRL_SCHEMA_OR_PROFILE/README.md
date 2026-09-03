# WRL SCHEMA / PROFILE — `graphonomous.semantic.v0`

**State: SEALED by WRL-P0 (WRL `b072db0`, receipt `../STACK_FIX_RECEIPTS/WRL-P0.md`); FROZEN only when GPT accepts this
round.** The profile is *data in the §D6.1 shape*. Two copies exist and a test holds them equal facet-for-facet
(`test/wrl_world.test.mjs`, "declaration reconcile"):

- **the admitted declaration** — `V2_PROFILES["graphonomous.semantic.v0"]` in `WRL/relation-v2.js` (blob `fd1babc5…`), a
  `static` row: rulepack, policies, domain, signature, 21 roles × ports, 31 kinds → 92 explicit endpoint pairs. WRL reads
  it to validate, canonicalize and seal; it is the authority;
- **the submitted declaration** — `graphonomous.semantic.v0.json` here, what Graphonomous asked WRL to admit, plus the
  parts WRL does not carry (the object-id encoding, the type/enumeration notes, the historical spike rule).

Mapping to §D6.1's eight items (R5 §5.1):

| D6.1 item | G0 content | required |
|---|---|---|
| role declarations (not in D6.1's list — the spec-text hole R5 found) | one role per spec §3.1 kind; one nominal port `node`; per-role config keys = the kind's attributes | yes |
| 1 primitive & enumerated types | `lid`, `sha256`, `decimal-string`; one enum per registry evidence vocabulary (crosswalk 11 tokens, factory 8, TRVM 8, research ledger 15, cells 6) — never merged | yes |
| 2 units | none | no |
| 3 relation signatures | domain `semantic`; kinds = spec §3.2 + `STATE_TRANSITION_OF` (D-037); all `directed`, `solid`, arity 2, roles `source`/`target` | yes |
| 4 endpoint-role constraints | per kind, explicit `[source kind, target kind]` pairs (D-037 pairs form; `*` = any); `SUPERSEDES` same-kind only; `STATE_TRANSITION_OF: [[EVIDENCE_STATE_TRANSITION, CLAIM]]` — enforced by WRL (`WRL_UNDECLARED_ENDPOINT_PAIR`) | yes |
| 5 bounded resources | none | no |
| 6 finite resolution tables | none at G0 (folding many WITNESSES into one status is a G1 rule, not a table) | no |
| 7 built-in validators | seed uniqueness (`WRL_DUPLICATE_RELATION_SEED`), terminals (`WRL_UNKNOWN_ENDPOINT`), policy vocabulary (`WRL_UNDECLARED_POLICY`, GAP-W9 closed); lid grammar and the forbidden-key rule stay G0's | partly |
| 8 canonical defaults | omitted attributes stay omitted (never `"open"`); `texture: solid`; `policy: graphonomous.semantic.rules.v0` | yes |

**World identity:** `sem-` = WRL `v2WorldIdOfArtifact` over `canonicalizeV2Artifact` bytes — minted by WRL only. Baseline
`sem-0f952f03…` (1,080 objects / 588 relations), historical `sem-3ae051cf…` (1,052 / 566), at WRL `b072db0`.
**Relation identities:** `rev-` = kernel `relationRevisionId`; `rel-` = kernel `relationIdFromAllocation` over
`expandSeed(sem, seed)` — both through `deriveV2Relations`, labelled `wrl-kernel@b072db0`. World-scoped (D8.5, D-043):
every `rel-` moves with the `sem-`; the statement lid is the cross-world name.
**The spike (historical, D-038/D-041):** the D-036/D-037 `gsem-`/`grelpre-` canonicalizer is `lib/wrl_world_spike.mjs`,
its receipts are `<projection>/world-spike/`, and `world/identities.json` records the mapping under
`supersedes.historical_spike_gsem`. Measured at `b072db0`: the spike's bytes equal WRL's canonical bytes at both pins, so
the hexes agree — measured per pin, never a rule; the spike was never a seal. Every `grelpre-` differs from the kernel
`rel-` (its allocation scope was the `gsem-`).
