defmodule Graphonomous.MCP.Server do
  @moduledoc """
  Graphonomous MCP server definition.

  This server exposes Graphonomous capabilities to MCP clients via registered
  tool components.
  """

  use Anubis.Server,
    name: "graphonomous",
    version: "0.1.0",
    capabilities: [:tools, :resources]

  # MCP tool components
  component(Graphonomous.MCP.StoreNode)
  component(Graphonomous.MCP.RetrieveContext)
  component(Graphonomous.MCP.LearnFromOutcome)
  component(Graphonomous.MCP.QueryGraph)
  component(Graphonomous.MCP.ManageGoal)
  component(Graphonomous.MCP.ReviewGoal)
  component(Graphonomous.MCP.RunConsolidation)

  # MCP resource components
  component(Graphonomous.MCP.Resources.HealthSnapshot)
  component(Graphonomous.MCP.Resources.GoalsSnapshot)
end
