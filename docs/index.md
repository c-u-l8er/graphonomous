# Graphonomous Documentation

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
```

```{toctree}
:maxdepth: 1
:caption: Root Docs

[&] Protocol Docs <https://docs.ampersandboxdesign.com>
Graphonomous Docs <https://docs.graphonomous.com>
BendScript Docs <https://docs.bendscript.com>
WebHost.System Docs <https://docs.webhost.systems>
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
skills/AGENT_BOOTSTRAP_PROMPT
skills/01_RETRIEVE_AND_REMEMBER
skills/02_LEARNING_LOOP
skills/03_GRAPH_INSPECTION
skills/04_GOAL_MANAGEMENT
skills/05_COVERAGE_AND_REVIEW
skills/06_TOPOLOGY_AND_DELIBERATION
skills/07_CONSOLIDATION
skills/08_ATTENTION
skills/09_WORKFLOWS
skills/10_ANTI_PATTERNS
:::

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
