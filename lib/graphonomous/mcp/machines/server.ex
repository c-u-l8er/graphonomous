defmodule Graphonomous.MCP.Machines.Server do
  @moduledoc """
  Graphonomous MCP v2 server — loop-phase machines.

  Exposes 5 tools instead of 29, organized around the closed memory loop:

      retrieve → route → act → learn → consolidate

  Each tool is a "machine" that dispatches to the existing tool implementations
  via an `action` parameter. This reduces tool selection ambiguity by ~85% and
  cuts context token overhead proportionally.

  ## Migration

  This server can run alongside the v1 server during migration:
  - Phase 1: Register both servers, test machine selection accuracy
  - Phase 2: Update skill prompts to use machine verbs
  - Phase 3: Deprecate v1 tool names
  - Phase 4: Remove v1 server

  The individual tool modules in `lib/graphonomous/mcp/` are preserved as the
  implementation layer — machines delegate to them, they are not deleted.
  """

  use Anubis.Server,
    name: "graphonomous",
    version: "0.4.0",
    capabilities: [:tools, :resources]

  # The 5 loop-phase machines
  component(Graphonomous.MCP.Machines.Retrieve)
  component(Graphonomous.MCP.Machines.Route)
  component(Graphonomous.MCP.Machines.Act)
  component(Graphonomous.MCP.Machines.Learn)
  component(Graphonomous.MCP.Machines.Consolidate)

  # Resources remain unchanged
  component(Graphonomous.MCP.Resources.HealthSnapshot)
  component(Graphonomous.MCP.Resources.GoalsSnapshot)
  component(Graphonomous.MCP.Resources.NodeDetail)
  component(Graphonomous.MCP.Resources.RecentNodes)
  component(Graphonomous.MCP.Resources.ConsolidationLog)
end
