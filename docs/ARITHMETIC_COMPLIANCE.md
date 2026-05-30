# Graphonomous × box-and-box — Arithmetic Compliance Review

**Status:** review (no behavior change) · **Kernel:** `box-and-box` v0.8.0 (8 rungs, 97 laws)
**Scope:** how closely the Graphonomous memory engine (OS-001) already conforms to the [&]
governance kernel, rung by rung, and the small set of *additive* naming/wiring changes that
would make it explicitly compliant.

## TL;DR

Graphonomous is **already structurally isomorphic** to the kernel's load-bearing rungs — it
just doesn't *name* them. Its coverage→decision policy is the bridge
(`feasible ▸ permitted ▸ best`); its coverage score is the axiological semiring; its Wilson
intervals are the epistemic rung; its cost cap is the resource rung's affine ledger. The
gap is **vocabulary + two small guarantees**, not architecture. Nothing here requires a core
refactor; every recommendation is additive.

## Compliance scorecard

| Kernel rung | Graphonomous implementation | Compliance |
|---|---|---|
| 1. alethic (`value`) | `Topology.compute_kappa/2`, SCC analysis; node confidence | ✅ ~90% — κ is a first-class Value |
| 2. axiological (`score`) | `Coverage.weighted_sum/2`, `Reranker` | ◻ ~60% — weighted sum, not a *named* semiring |
| 3. deontic (norm/govern) | `Coverage.pick_decision/4` floor gates (act/learn/escalate) | ◻ ~70% — floor present, `0̲` veto implicit |
| 4. temporal (LTL ▸ supervise) | consolidation cadence; freshness/staleness decay | ◻ ~40% — time-aware, no LTL obligations |
| 5. reflexive (entrenched ring-0) | — (no self-amendment surface) | ✕ out of scope |
| 6. epistemic (knows ▸ believes) | `Uncertainty.interval/1` (Wilson), `BeliefRevision` (AGM) | ✅ ~95% — strongest rung |
| 7. strategic (coalition power) | — (single-agent; delegated to Deliberatic) | ✕ out of scope |
| 8. resource (affine ledger) | `CostTracker.budget_exceeded?/0` ($10/day), `Forgetter` LRU+decay | ◻ ~85% — ledger present |

## Rung-by-rung detail (grounded in the code)

### Rung 1 — alethic (`value`) ✅

`lib/graphonomous/topology.ex` `compute_kappa/2` (line 134) computes the **κ cyclicity
invariant** — the same Value-family invariant the kernel's `value.mjs` carries (alethic
"what can happen"). Node confidence scores are the truth-degrees over which Value laws
`L1–L14` range. **Already compliant**; recommend citing the rung-1 correspondence in the
`Topology` moduledoc so κ is understood as the alethic Value, not a bespoke metric.

### Rung 2 — axiological (`score`) ◻ → name the semiring

`lib/graphonomous/coverage.ex` `weighted_sum/2` (line 604) computes `Σ value × weight` and
clamps to `[0,1]`. That is the kernel's **probability semiring** (`⊕ = +`, `⊗ = ×`) from
`box-and-box/score.mjs`. **Additive recommendation:** document that the coverage score *is*
the axiological rung in the probability semiring, and (optionally) expose a tropical
(`⊕ = min`) "weakest-component" view alongside the weighted mean — so the engine can answer
"is any coverage component failing?" the way the kernel's safety floor does, not just
"how good on average?".

### Rung 3 — deontic (norm/govern) ◻ → make the `0̲` veto explicit

`Coverage.pick_decision/4` (line 392) is **the bridge, already implemented**:

```
:act  when coverage ≥ floor  AND uncertainty ≤ ceiling  AND risk ≤ ceiling   # feasible ▸ permitted
:learn when (looser floor)                                                    # permitted, not yet best
:escalate otherwise                                                           # floor not met
```

This is exactly `feasible ▸ permitted ▸ best`: the conjunctive thresholds are the
**un-weakenable safety floor**, and `decision_confidence/3` (line 409) is the **gradient**
that the bridge's `best` step optimizes. The one missing guarantee is **`0̲` annihilation**:
in the kernel, a floor violation *annihilates* the verdict (no amount of gradient can
rescue it). Graphonomous approximates this — `:escalate` is terminal — but the relationship
is implicit. **Additive recommendation:** state in the `Coverage` moduledoc that a
sub-floor signal annihilates to `:escalate` (the deontic `0̲`), and add a property test
mirroring the kernel's `DB2` annihilation law so the guarantee can't silently regress.

### Rung 4 — temporal (LTL ▸ supervise) ◻

Freshness/staleness decay (`coverage.ex` line 383) and consolidation cadence are
time-aware, but there are no explicit LTL obligations (e.g. "every stored contradiction is
*eventually* resolved"). **Out of scope to add now**; flagged as the natural next rung if
temporal guarantees become first-class. Maps to `box-and-box/temporal.mjs` (`X`, `◇`).

### Rung 6 — epistemic (knows ▸ believes) ✅ strongest

`lib/graphonomous/uncertainty.ex` `interval/1` (line 28) computes **Wilson confidence
intervals** over evidence counts, with an explicit `:no_evidence` bottom — this is the
kernel's epistemic rung (S5/KD45 "knows ▸ believes") in statistical form. `BeliefRevision`
implements **AGM** expansion/contraction with `contradicts` edges. **Already compliant** at
~95%; recommend naming the `:no_evidence` case as the epistemic bottom and citing the
rung-6 correspondence. This is the rung Graphonomous could claim conformance on today.

### Rung 8 — resource (affine ledger) ◻

`lib/graphonomous/cost_tracker.ex` `budget_exceeded?/0` (line 167) enforces a `$10/day`
cap — an **affine ledger**: spend is consumed and cannot go negative past the cap. The
`Forgetter` (LRU + priority decay) is resource reclamation. This is the kernel's resource
rung (`resource.mjs`, laws `C1–C8`). **Additive recommendation:** emit the daily-budget
remaining as a resource signal and name it with the resource-rung vocabulary (`consume`,
overspend → `0̲`), so unattended autonomy degrades gracefully via the same algebra the
kernel uses.

## Recommended changes (all additive, no behavior change)

| Change | File | Risk | Value |
|---|---|---|---|
| Cite κ = alethic Value | `topology.ex` moduledoc | none | shared vocabulary |
| Name coverage score = probability semiring; optional tropical view | `coverage.ex` | low | bottleneck visibility |
| State the `0̲` annihilation on sub-floor; add `DB2`-style property test | `coverage.ex` + test | low | regression guard |
| Name Wilson `:no_evidence` as epistemic bottom | `uncertainty.ex` moduledoc | none | claim rung-6 conformance |
| Emit resource-ledger remaining with kernel vocabulary | `cost_tracker.ex` | low | graceful autonomy |

## What this review deliberately does NOT do

- It does **not** change any decision thresholds, coverage weights, or confidence formulas.
- It does **not** make Graphonomous call the JS kernel at runtime — Graphonomous stays
  self-contained Elixir; the kernel is the *specification* its algebra conforms to.
- It does **not** add the reflexive (rung 5) or strategic (rung 7) rungs — those are
  single-agent-out-of-scope and delegated to Delegatic/Deliberatic respectively.

## Reference

- `AmpersandBoxDesign/box-and-box/` — the kernel (`node test/laws.mjs` → 97 laws)
- `AmpersandBoxDesign/box-and-box/{score,bridge,epistemic,resource}.mjs` — the rungs cited
- `lib/graphonomous/coverage.ex` — the bridge + axiological semiring (§ rungs 2–3)
- `lib/graphonomous/uncertainty.ex` — Wilson epistemic intervals (§ rung 6)
- `lib/graphonomous/cost_tracker.ex` — affine resource ledger (§ rung 8)
