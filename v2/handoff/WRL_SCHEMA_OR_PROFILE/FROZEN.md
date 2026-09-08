# Freeze state of the submitted WRL profile declarations

This file is the pointer a reader should follow when a profile JSON's own `state` string disagrees with the lane's
current ruling. **The JSON files in this directory are not rewritten when a ruling lands after they were sealed.**
Their `state` strings are receipts of the sealing moment; the ruling is recorded here and in `../DECISION_LOG.md`.

| profile | state | ruled | WRL pin | roles · kinds · pairs | rulepack |
|---|---|---|---|---|---|
| `graphonomous.semantic.v0` | **FROZEN** | GPT v4 (D-054), reaffirmed GPT v6 §3 | `b072db0` (admitted), reproduces at `53e5e89` | 21 · 31 · 92 | `graphonomous.semantic.rules.v0` |
| `graphonomous.semantic.v1` | **FROZEN** | GPT Adjudication v6 §3 → **D-066** | `53e5e8995913995189f7017d2a94351ff69d5b31` | **24 · 32 · 102** | `graphonomous.semantic.rules.v0` (shared — **D-067**) |

Counts above are measured from the files in this directory, not transcribed:

```
node -e 'const p=JSON.parse(require("fs").readFileSync("handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v1.json","utf8"));
const k=Object.keys(p.endpoint_constraints).filter(x=>x!=="note");
console.log(p.roles.kinds.length, k.length, k.reduce((n,x)=>n+p.endpoint_constraints[x].length,0))'
→ 24 32 102
```

## What each file's own `state` string still says, and why that is left alone

- `graphonomous.semantic.v1.json` reads `state: "PROPOSED (GPT Adjudication v5 §7, 2026-09-03; D-062/D-064) …"`.
  It was proposed then. GPT v6 §3 froze it afterwards. Editing the string would change bytes that were submitted for
  adjudication in order to make them agree with the adjudication's answer.
- Every `projections/*/world/identities.json` reads `"SEALED by WRL (WRL-P0); FROZEN only when GPT accepts this
  round"`. GPT accepted this round; the seals are not re-written to say so.

## The v1 delta, as frozen (D-066)

New roles `ARGUMENT` · `DEFEATER` · `INSTRUMENT`. New kind `DISCHARGED_BY`. Ten new endpoint pairs:

```
SUPPORTS      [ARGUMENT,   CLAIM]        ATTACKS       [DEFEATER,   ARGUMENT]
WITNESSES     [WITNESS,    ARGUMENT]     ATTACKS       [DEFEATER,   ASSUMPTION]
ASSUMES       [ARGUMENT,   ASSUMPTION]   ATTACKS       [DEFEATER,   INSTRUMENT]
ASSUMES       [INSTRUMENT, ASSUMPTION]   ATTACKS       [DEFEATER,   RECEIPT]
ATTACKS       [DEFEATER,   CLAIM]        DISCHARGED_BY [ASSUMPTION, CLAIM]
```

Golden world: `sem-e186186ea55e9e9a9d10a7676dd31180e248837db54fb66e388d594ff5406e66`.

**Never widen a frozen row.** A new requirement is `graphonomous.semantic.v2`, and the guard that stops a seal rather
than widening v1 is D-071's semantic-profile guard.
