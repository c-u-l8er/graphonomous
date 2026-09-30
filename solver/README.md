# Graphonomous Solver — SEO · GEO · agent optimization

A **solver**, not a linter. It builds a site's claim graph, derives findings in the same
four classes v2's registry rulepack uses, and then — for each finding — enumerates
candidate remedies and runs them through the box-and-box bridge:
**`feasible ▸ permitted ▸ best`** over a floor that a high score cannot buy off.

Every verdict ships the thing no other tool in this market emits: **what was refused,
why, and whether the refusal overrode the ranking.**

```
node bin/solve.mjs /path/to/site --origin example.com --json out.json
npm run app          # http://127.0.0.1:8941 — the whole solver, client-side
npm test             # 26 tests
```

## Why it sits beside `v2/`, not inside it

`graphonomous/v2/` is the frozen G0/G1 lane: a derived projection over *authoritative
registries*, under a contract that says no LLM output is evidence and Graphonomous is
not itself a registry. A web crawl is not an authoritative registry. Rather than argue
that boundary open, this lane keeps its own namespace and imports what it needs.

Nothing here modifies `v2/` or `box-and-box/`.

## Layout

| path | what |
|---|---|
| `lib/hash.mjs` | synchronous SHA-256, pure JS — **proven byte-identical to `node:crypto`** (`test/hash.test.mjs`) |
| `lib/lid.mjs` | content-bound ids: a finding's id is a hash of its own premises |
| `lib/ingest.mjs` | HTML → page records + claims. No DOM, no dependencies |
| `lib/graph.mjs` | records → the claim graph: links, canonicals, inbound, sitemap, robots |
| `lib/rules_web.mjs` | **`graphonomous.consistency.rules.web.v0`** — 12 rules in 4 classes |
| `lib/remedies.mjs` | the candidate-remedy catalogue — one entry per rule |
| `lib/solve.mjs` | finding → options → `bridge.select` → certificate |
| `lib/report.mjs` | one run, serialised; shared by the CLI and the app |
| `vendor/box-and-box/` | 4 kernel modules, synced by script, **drift-tested** |
| `app/` | the prototype; imports `lib/` directly, no build step |

**The whole solver is browser-clean** — zero `node:` imports in `lib/` and `vendor/`.
The dev server exists only to read local fixtures and fetch third-party origins, which
a page cannot do (same-origin policy). In production that is a Worker, ~40 lines, and
it is the only server-side component.

## The rulepack

The class is a claim about certainty, not a severity label.

| class | rules |
|---|---|
| **contradiction** — the site asserts X and ¬X | `CLAIM_VALUE_DISAGREEMENT`, `CANONICAL_DISAGREEMENT`, `SCHEMA_PROSE_DISAGREEMENT` |
| **drift** — surfaces that should agree have diverged | `TITLE_H1_DRIFT`, `DESCRIPTION_DRIFT`, `ENTITY_NAME_DRIFT` |
| **stale** — a surface fell behind the graph | `SITEMAP_GRAPH_DIVERGENCE`, `ORPHANED_PAGE` |
| **unresolved** — something load-bearing is absent or undecided | `AMBIGUOUS_QUANTITY`, `NO_MACHINE_READABLE_CLAIM`, `AGENT_ACCESS_UNDECLARED`, `MISSING_CANONICAL` |

### The guard, and why it exists

`CLAIM_VALUE_DISAGREEMENT` fires **only** when a dominant value (≥2 occurrences) meets a
minority value *whose surrounding prose resembles it*. On the first real run, dominance
alone proposed replacing **"the two laws a refusing join must keep"** with **"109 laws"**.
A shared unit noun is not a shared subject. Minority values in unrelated prose are filed
`AMBIGUOUS_QUANTITY` — reported, never actioned.

Similarity ignores stopwords **and the unit noun that grouped the two claims**, since a
shared grouping key is evidence of nothing.

## The floor

```js
{ sigma_empty: true,          // a remedy may not leave its own finding standing
  beta_min: 0.6,              // material sufficiency — the site must be able to ground it
  deny_default: 'must_allow', // an edit needs a warrant
  acyclic: true }             // no circular grounding
```

Weaken it in the app and watch the decision change. Measured on `opensentience.org`:

| floor | decision on the same finding |
|---|---|
| β ≥ 0.60 | `correct-the-minority` — the grounded fix |
| β ≥ 0.25 | `add-a-canonical-number-page` — **content generation wins once grounding is cheap** |
| σ off | `leave-a-note-explaining` — **papering over wins once resolution is optional** |

## What is measured and what is not

- **Findings** are derived from the page bytes.
- **β** is *measured* from a finding's own premises where evidence supports it, *declared*
  otherwise. Every option states which, in the CLI and in the UI.
- **Utility is declared everywhere, without exception.**

So the **veto half is defensible today; the gradient half is an opinion wearing a number.**
Both surfaces say so out loud rather than letting it be discovered later. Making utility
measured — from re-probe outcomes over time — is the obvious next lane and is not done.

## Known limits

- The extractor has **no subject resolution**. It deliberately extracts only quantity and
  definition claims rather than pretending to open-domain extraction.
- `TRACKED_UNITS` is a fixed list. An open unit list turns every incidental number into a
  false contradiction.
- `TITLE_H1_DRIFT` / `DESCRIPTION_DRIFT` thresholds (0.2) are **uncalibrated** — they are
  the noisiest rules in the pack and their counts should not be quoted as fact yet.
- No engine probing. Citation measurement is deliberately out of scope: it is
  non-deterministic, costs money per run, and is not what this engine is good at.
