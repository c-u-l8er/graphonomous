defmodule Graphonomous.MCP.Machines.Consolidate do
  @moduledoc """
  Loop Phase 5: CONSOLIDATE — "Clean up"

  Unified maintenance machine for the Graphonomous memory loop.
  The agent calls this to maintain graph quality, typically at session boundaries
  or after heavy storage bursts.

  Actions:
  - `run`      — trigger a consolidation cycle
  - `stats`    — aggregate counts, distributions, confidence stats, orphans
  - `query`    — operation-based graph inspection
  - `traverse` — BFS walk with depth/relationship filters

  Replaces: run_consolidation, graph_stats, query_graph, graph_traverse
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(run stats query traverse)

  schema do
    field(:action, :string,
      required: true,
      description: "Maintenance action: run | stats | query | traverse"
    )

    # -- run (consolidation) --
    field(:consolidation_action, :string,
      description:
        "Consolidation sub-action: run | status | run_and_status (run, default: run_and_status)"
    )

    field(:wait_ms, :number, description: "Delay before returning status in ms, 0-30000 (run)")

    # -- query --
    field(:operation, :string,
      description: "Graph query operation (query) — see query_graph for operations"
    )

    field(:node_id, :string, description: "Node ID for query/traverse operations")

    # -- traverse --
    field(:start_id, :string, description: "Start node ID for BFS walk (traverse)")
    field(:depth, :number, description: "Max traversal depth (traverse, default: 2)")

    field(:relationship, :string, description: "Filter by relationship type (traverse)")

    field(:direction, :string,
      description: "Traversal direction: outgoing | incoming | both (traverse, default: both)"
    )

    field(:limit, :number, description: "Max nodes to return (traverse, stats)")
  end

  @impl true
  def execute(params, frame) do
    action = params |> p(:action) |> normalize_action()

    if action in @valid_actions do
      dispatch(action, params, frame)
    else
      {:reply,
       error_response(
         "Invalid action '#{inspect(p(params, :action))}'. Must be one of: #{Enum.join(@valid_actions, ", ")}"
       ), frame}
    end
  end

  defp dispatch("run", params, frame) do
    # Map consolidation_action → action for the existing tool
    params =
      if is_binary(p(params, :consolidation_action)),
        do: Map.put(params, :action, p(params, :consolidation_action)),
        else: Map.put(params, :action, "run_and_status")

    Graphonomous.MCP.RunConsolidation.execute(params, frame)
  end

  defp dispatch("stats", params, frame) do
    Graphonomous.MCP.GraphStats.execute(params, frame)
  end

  defp dispatch("query", params, frame) do
    Graphonomous.MCP.QueryGraph.execute(params, frame)
  end

  defp dispatch("traverse", params, frame) do
    Graphonomous.MCP.GraphTraverse.execute(params, frame)
  end

  # -- Helpers --

  defp normalize_action(nil), do: nil
  defp normalize_action(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_action(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_action(_), do: nil

  defp error_response(message) do
    Response.tool()
    |> Response.structured(%{status: "error", error: message})
    |> Map.put(:isError, true)
  end

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
