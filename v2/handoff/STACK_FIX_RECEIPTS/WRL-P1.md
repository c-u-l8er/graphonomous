# WRL-P1 — a third static profile row, one endpoint pair wide

**Owning layer:** WRL. **Commit:** `6a8304c9a598bb5ae97f920aeae457532cdd99a5`
(`53e5e89` → `6a8304c`), *"A third static profile, and it is one endpoint pair wide"*.
**Ruled by:** GPT Adjudication v7 §6 → **D-077**. **Date:** 2026-09-04.
**Not pushed.** The commit exists so the Graphonomous pin can name a real commit containing the blob it checks.

## The gap

Graphonomous's third source family (TRVM governance) states law→law supersessions that frozen
`graphonomous.semantic.v1` could only carry as **deferred attributes**: `SUPERSEDES` was admitted same-kind at
`[CLAIM,CLAIM]` · `[ROUND,ROUND]` · `[EVIDENCE_STATE_TRANSITION,…]` (D-037), and `LAW` was not among the pairs. The
projection could not contain the edge at all, because `lib/lid.mjs` refuses an undeclared pair **at emission time**.

D-037 already gives `SUPERSEDES` the meaning of *replacement between semantically comparable entities*. LAW → LAW is
therefore **not a new relation meaning — it is a missing admitted endpoint pair.**

## The measurement that sized it, taken before anything was implemented

At TRVM `8816e59`, over `governance/invariant-grid.json`'s 139 law entries:

| | count |
|---|---|
| entries carrying a `supersedes` field | **24** |
| entries carrying a `superseded_by` field | **25** |
| **unique (source, target) supersession propositions** | **25** |
| propositions stated by **both** fields | 24 |
| propositions stated **only** by `superseded_by` | **1** — `kernel.identity@1.superseded_by = "kernel.identity@2"`, where `kernel.identity@2` carries no reciprocal `supersedes` |
| unresolved pointers | 0 |
| cross-id supersessions | 1 — `kappa.internal-edge.monotonicity@4` supersedes `kappa.carrier-preserving.monotonicity@2` |

TRVM's `grid_check` enforces lineage symmetry **only where both sides are populated**, so the asymmetric one is legal
in the owning layer and is a real proposition the source states. **GPT v7 said 24; the measured number is 25, and the
number is the only thing that moves — the obligation is still exactly one endpoint pair.**

## The change

`WRL/relation-v2.js`, +20 lines, one file:

```js
const GRAPHONOMOUS_V2_ENDPOINTS = { SUPERSEDES: [["LAW", "LAW"]] };
const GRAPHONOMOUS_V2_ROW = { ...GRAPHONOMOUS_V1_ROW, endpoints: /* v1 pairs, then the v2 pair, per kind */ };
V2_PROFILES["graphonomous.semantic.v2"] = GRAPHONOMOUS_V2_ROW;
```

Written the same way `GRAPHONOMOUS_V1_ROW` was: the v1 row stays the **only** definition of v1 and the v2 row cannot
contain a private copy of it that could drift. Pairs for a kind v1 already declares are the v1 pairs **followed by**
the v2 one, so a v2 world admits everything a v1 world admits.

**No new role. No new relation kind. No new rulepack. No edit to the v0 or v1 rows.**

## Measured after

```
profile ids: forge.world.core.v1, graphonomous.semantic.v0, graphonomous.semantic.v1, graphonomous.semantic.v2
  graphonomous.semantic.v0   21 roles / 31 kinds /  92 pairs   rules.v0   static
  graphonomous.semantic.v1   24 roles / 32 kinds / 102 pairs   rules.v0   static
  graphonomous.semantic.v2   24 roles / 32 kinds / 103 pairs   rules.v0   static
v2 SUPERSEDES: [CLAIM,CLAIM] [ROUND,ROUND] [EVIDENCE_STATE_TRANSITION,…] [LAW,LAW]
v1 SUPERSEDES: [CLAIM,CLAIM] [ROUND,ROUND] [EVIDENCE_STATE_TRANSITION,…]

WRL conformance: 901 passed, 0 failed   (unchanged from 53e5e89)
```

## v0 / v1 non-regression, at the NEW commit

Every previously golden world reproduces byte-identically after the re-pin:

```
baseline    sem-0f952f03804c73152b762e4a09570ce37adb35039203c5c4c501507bd0ab17be   v0
historical  sem-3ae051cf2a4ab35436eedeb1b15cae759bd3001652d55d67a3f29ae23f5d0e23   v0
multi       sem-b8d828278e9ba411bc375da4b03754e87210b78cb106d25422fd94e8526622ea   v0
multi-v1    sem-e186186ea55e9e9a9d10a7676dd31180e248837db54fb66e388d594ff5406e66   v1
```

## The guard still guards

Sealing the new `tri` projection — which now CONTAINS the 25 law supersessions — under `graphonomous.semantic.v1`
is refused, by name:

```
WORLD_ENDPOINT_KIND / WRL_UNDECLARED_ENDPOINT_PAIR
  rel:g0:SUPERSEDES:law:trvm-gov:derivation.canonical-lowering@2:law:trvm-gov:derivation.canonical-lowering@1
  LAW → LAW is not an allowed pair for SUPERSEDES
  (profile allows CLAIM→CLAIM, ROUND→ROUND, EVIDENCE_STATE_TRANSITION→EVIDENCE_STATE_TRANSITION)
```

**The guard did not move. The admitted row did.** `lib/lid.mjs`'s kernel table gained the pair because a lid carries
no profile — it is the profile that decides whether a world may contain the statement, and v0/v1 still refuse it.

## The identity result, third independent confirmation of D-066

Between the pre-v2 `tri` world (v1) and the new one (v2), keyed on statement lid:

- **2,469 / 2,469 shared statements keep the SAME `rev-`** — a revision identity is world-independent, and admitting
  an endpoint pair changed no existing statement;
- **0 / 2,469 keep the same `rel-`** — allocation is world-scoped;
- **25 statements are new, every one of them `SUPERSEDES`**, and none is old-only.

That is the same shape as the v0→v1 result (1,574/1,574 and 0/1,574) on different data.
