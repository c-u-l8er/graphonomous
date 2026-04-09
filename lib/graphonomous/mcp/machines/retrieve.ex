defmodule Graphonomous.MCP.Machines.Retrieve do
  @moduledoc """
  Loop Phase 1: RETRIEVE — "What do I know?"

  Unified retrieval machine for the Graphonomous memory loop.
  The agent calls this before reasoning or acting to gather context.

  Actions:
  - `context`        — κ-aware ranked retrieval with topology annotations
  - `episodic`       — time-range filtered episodic nodes
  - `procedural`     — semantic search scoped to procedural nodes
  - `coverage`       — epistemic coverage assessment (act/learn/escalate)
  - `trace_evidence` — weighted Dijkstra evidence path between nodes
  - `frontier`       — Wilson interval uncertainty analysis

  Replaces: retrieve_context, retrieve_episodic, retrieve_procedural,
            coverage_query, trace_evidence_path, epistemic_frontier
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(context episodic procedural coverage trace_evidence frontier)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Retrieval action: context | episodic | procedural | coverage | trace_evidence | frontier"
    )

    # -- context action --
    field(:query, :string,
      description: "Natural-language search query (context, procedural, coverage, frontier)"
    )

    field(:limit, :number, description: "Max results to return (context, episodic, procedural)")

    field(:expansion_hops, :number,
      description: "Graph neighborhood expansion depth (context, default: 1)"
    )

    field(:neighbors_per_node, :number,
      description: "Max neighbors per seed node (context, default: 5)"
    )

    field(:min_score, :number, description: "Minimum score threshold 0.0-1.0 (context)")

    field(:node_type, :string,
      description:
        "Filter by node type: episodic, semantic, procedural, temporal, outcome, goal (context)"
    )

    # -- episodic action --
    field(:since, :string, description: "ISO8601 datetime — episodes after this time (episodic)")

    # -- procedural action --
    field(:task, :string, description: "Task description to find procedures for (procedural)")
    field(:preconditions, :string, description: "JSON array of precondition strings (procedural)")

    # -- coverage action --
    field(:task_description, :string, description: "Task to assess coverage for (coverage)")

    field(:critical_topics, :string,
      description: "JSON array of critical topic strings (coverage)"
    )

    field(:min_confidence, :number,
      description: "Minimum confidence for relevant nodes (coverage, default: 0.3)"
    )

    field(:top_k, :number,
      description: "Max retrieval results to evaluate (coverage, default: 10)"
    )

    # -- trace_evidence action --
    field(:source_id, :string, description: "Start node ID (trace_evidence)")
    field(:target_id, :string, description: "End node ID (trace_evidence)")

    field(:k, :number,
      description: "Number of shortest paths to return (trace_evidence, default: 3)"
    )

    # -- frontier action --
    field(:min_gap, :number,
      description: "Minimum Wilson interval width to include (frontier, default: 0.3)"
    )
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

  # -- Dispatch to existing tool logic --

  defp dispatch("context", params, frame) do
    Graphonomous.MCP.RetrieveContext.execute(params, frame)
  end

  defp dispatch("episodic", params, frame) do
    Graphonomous.MCP.RetrieveEpisodic.execute(params, frame)
  end

  defp dispatch("procedural", params, frame) do
    # Map query → task if task not provided (common caller pattern)
    params =
      if is_nil(p(params, :task)) and is_binary(p(params, :query)),
        do: Map.put(params, :task, p(params, :query)),
        else: params

    Graphonomous.MCP.RetrieveProcedural.execute(params, frame)
  end

  defp dispatch("coverage", params, frame) do
    # Map query → task_description if not provided
    params =
      if is_nil(p(params, :task_description)) and is_binary(p(params, :query)),
        do: Map.put(params, :task_description, p(params, :query)),
        else: params

    Graphonomous.MCP.CoverageQuery.execute(params, frame)
  end

  defp dispatch("trace_evidence", params, frame) do
    Graphonomous.MCP.TraceEvidencePath.execute(params, frame)
  end

  defp dispatch("frontier", params, frame) do
    Graphonomous.MCP.EpistemicFrontier.execute(params, frame)
  end

  # -- Helpers --

  defp normalize_action(nil), do: nil

  defp normalize_action(v) when is_binary(v) do
    v |> String.trim() |> String.downcase()
  end

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
