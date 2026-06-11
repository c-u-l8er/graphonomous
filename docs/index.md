# Graphonomous Documentation

> **Part of the [&] Protocol stack** · [Ecosystem overview](../../ECOSYSTEM.md) · [Three-protocol stack](../../PULSE/docs/THREE_PROTOCOL_STACK.md) · [Stack status](../../STACK_COMPLETION.md)

Welcome to the documentation hub for **Graphonomous**.

Graphonomous is a continual-learning memory engine for AI agents, implemented in Elixir/OTP and exposed via MCP tools/resources. It combines graph-based memory, outcome-driven confidence updates, goal orchestration, topology-aware routing, and consolidation cycles.

## Start Here

If you're new to the project, begin with:

1. **Quickstart** — run Graphonomous locally and verify the memory loop.
2. **Architecture** — understand runtime components and data flow.
3. **Runtime Walkthrough** — follow retrieve → act → store → learn in practice.
4. **MCP Tools** — reference all tools and resources.
5. **Operations** — runbook for maintenance and troubleshooting.

## Documentation


```{toctree}
:maxdepth: 1
:caption: Homepages

[&] Ampersand Box <https://ampersandboxdesign.com>
Graphonomous <https://graphonomous.com>
BendScript <https://bendscript.com>
WebHost.Systems <https://webhost.systems>
Agentelic <https://agentelic.com>
AgenTroMatic <https://agentromatic.com>
Delegatic <https://delegatic.com>
Deliberatic <https://deliberatic.com>
FleetPrompt <https://fleetprompt.com>
GeoFleetic <https://geofleetic.com>
OpenSentience <https://opensentience.org>
SpecPrompt <https://specprompt.com>
TickTickClock <https://ticktickclock.com>
```

```{toctree}
:maxdepth: 1
:caption: Root Docs

[&] Protocol Docs <https://docs.ampersandboxdesign.com>
Graphonomous Docs <https://docs.graphonomous.com>
BendScript Docs <https://docs.bendscript.com>
WebHost.Systems Docs <https://docs.webhost.systems>
Agentelic Docs <https://docs.agentelic.com>
AgenTroMatic Docs <https://docs.agentromatic.com>
Delegatic Docs <https://docs.delegatic.com>
Deliberatic Docs <https://docs.deliberatic.com>
FleetPrompt Docs <https://docs.fleetprompt.com>
GeoFleetic Docs <https://docs.geofleetic.com>
OpenSentience Docs <https://docs.opensentience.org>
SpecPrompt Docs <https://docs.specprompt.com>
TickTickClock Docs <https://docs.ticktickclock.com>
```

:::{toctree}
:maxdepth: 2
:caption: Graphonomous Docs

quickstart
architecture
runtime-walkthrough
mcp-tools
operations
faq
spec/README
:::

## Integration & Build Guides

:::{toctree}
:maxdepth: 1
:caption: Setup & Distribution

BOOTSTRAP
ZED
NPM_PUBLISH
:::

## Agent Skills Pack

:::{toctree}
:maxdepth: 1
:caption: Skills

skills/SKILLS
skills/bootstrap
skills/retrieve
skills/store
skills/learn
skills/deliberate
skills/consolidate
skills/goals
skills/belief
skills/forgetting
skills/epistemic-frontier
skills/trace-evidence-path
skills/attention
skills/review
skills/inspect
skills/graph-health
skills/workflows
skills/sync
skills/watch
:::

## Documentation index

Linked index of every page in this set (renders on GitHub and in the docs atlas; the toctrees above drive the Sphinx build):

**Guides**

- [Architecture](architecture.md)
- [Quickstart](quickstart.md)
- [Runtime Walkthrough](runtime-walkthrough.md)
- [MCP Tools Reference](mcp-tools.md)
- [Operations & Maintenance](operations.md)
- [FAQ](faq.md)
- [Technical Documentation](TECHNICAL_DOCUMENTATION.md)
- [Arithmetic Compliance Review (box-and-box)](ARITHMETIC_COMPLIANCE.md)
- [Agent Skills](skills/SKILLS.md)

**Setup & distribution**

- [Local Bootstrap & Verification Guide](BOOTSTRAP.md)
- [Zed MCP Setup Guide](ZED.md)
- [NPM Package Specification](NPM_PACKAGE.md)
- [npm Publishing + Maintenance Runbook](NPM_PUBLISH.md)

**Specification**

- [κ Integration Spec — Product-Level Specification](spec/kappa_integration_spec.md)
- [κ × Product Crosswalk](spec/kappa_product_crosswalk.md)
- [κ-Aware Graph Intelligence — Theoretical Foundation](spec/kappa_theory_applied.md)

**UX**

- [User Stories](ux/user-stories.md)

**Build prompts**

- [Benchmark Expansion Prompt](../prompts/BENCHMARK_EXPANSION_PROMPT.md)
- [Continual Learning v0.3 — Implementation Prompt](../prompts/CONTINUAL_LEARNING_V03_PROMPT.md)
- [Continual Learning v0.3 — P1 (Week 3-4)](../prompts/CONTINUAL_LEARNING_P1_PROMPT.md)
- [Continual Learning v0.3 — P2 (Week 5+)](../prompts/CONTINUAL_LEARNING_P2_PROMPT.md)
- [Continual Learning v0.3 — P3 (Week 6+)](../prompts/CONTINUAL_LEARNING_P3_PROMPT.md)
- [κ-Topology QA & SHR Optimization — Session Prompt](../prompts/KAPPA_QA_OPTIMIZATION_PROMPT.md)

## Recommended Reading Path

- **Operators/Maintainers:** `quickstart` → `operations` → `NPM_PUBLISH`
- **Agent Integrators:** `mcp-tools` → `runtime-walkthrough` → `skills/SKILLS`

## Core Operating Loop

For non-trivial work, use this cycle consistently:

1. Retrieve context.
2. Reason and act.
3. Store durable knowledge.
4. Learn from outcomes.
5. Consolidate periodically.

This loop keeps Graphonomous memory accurate, adaptive, and useful across sessions.
