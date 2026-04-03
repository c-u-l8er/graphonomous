defmodule Graphonomous.MCP.Server do
  @moduledoc """
  Graphonomous MCP server definition.

  This server exposes Graphonomous capabilities to MCP clients via registered
  tool components.
  """

  use Anubis.Server,
    name: "graphonomous",
    version: "0.2.0",
    capabilities: [:tools, :resources]

  # MCP tool components
  component(Graphonomous.MCP.StoreEdge)
  component(Graphonomous.MCP.StoreNode)
  component(Graphonomous.MCP.RetrieveContext)
  component(Graphonomous.MCP.LearnFromOutcome)
  component(Graphonomous.MCP.QueryGraph)
  component(Graphonomous.MCP.ManageGoal)
  component(Graphonomous.MCP.ReviewGoal)
  component(Graphonomous.MCP.RunConsolidation)
  component(Graphonomous.MCP.TopologyAnalyze)
  component(Graphonomous.MCP.Deliberate)
  component(Graphonomous.MCP.AttentionSurvey)
  component(Graphonomous.MCP.AttentionRunCycle)
  component(Graphonomous.MCP.GraphTraverse)
  component(Graphonomous.MCP.GraphStats)
  component(Graphonomous.MCP.CoverageQuery)
  component(Graphonomous.MCP.RetrieveEpisodic)
  component(Graphonomous.MCP.RetrieveProcedural)
  component(Graphonomous.MCP.LearnFromFeedback)
  component(Graphonomous.MCP.LearnDetectNovelty)
  component(Graphonomous.MCP.LearnFromInteraction)
  component(Graphonomous.MCP.ManageEdge)
  component(Graphonomous.MCP.DeleteNode)
  component(Graphonomous.MCP.BeliefRevise)
  component(Graphonomous.MCP.BeliefContradictions)

  # MCP resource components
  component(Graphonomous.MCP.Resources.HealthSnapshot)
  component(Graphonomous.MCP.Resources.GoalsSnapshot)
  component(Graphonomous.MCP.Resources.NodeDetail)
  component(Graphonomous.MCP.Resources.RecentNodes)
  component(Graphonomous.MCP.Resources.ConsolidationLog)
end
