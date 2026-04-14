defmodule Graphonomous.MCP.Machines.Route do
  @moduledoc """
  Loop Phase 2: ROUTE — "What should I do?"

  Unified routing machine for the Graphonomous memory loop.
  The agent calls this to decide whether to act, learn, deliberate, or escalate.

  Actions:
  - `topology`         — SCC/κ analysis with routing recommendation
  - `deliberate`       — κ-driven deliberation over cyclic regions
  - `attention_survey` — priority survey across active goals
  - `attention_cycle`  — full triage → dispatch attention cycle
  - `review_goal`      — coverage-driven act/learn/escalate gate

  Replaces: topology_analyze, deliberate, attention_survey,
            attention_run_cycle, review_goal
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(topology deliberate attention_survey attention_cycle review_goal)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Routing action: topology | deliberate | attention_survey | attention_cycle | review_goal"
    )

    # -- topology action --
    field(:node_ids, :array, description: "Node IDs to analyze (topology, deliberate)")

    field(:query, :string,
      description:
        "Query to retrieve relevant nodes for analysis (topology, deliberate, review_goal)"
    )

    # -- deliberate action --
    field(:write_back, :boolean,
      description:
        "Whether to crystallize deliberation results back to graph (deliberate, default: false)"
    )

    # -- review_goal action --
    field(:goal_id, :string, description: "Goal ID to review coverage for (review_goal)")

    field(:signal, :any,
      description:
        "Coverage signal as a JSON object for review_goal. Example: {\"retrieved_nodes\": [...], \"outcomes\": [...]}"
    )

    field(:apply_decision, :any,
      description:
        "Whether to apply decision -> status transition policy (review_goal, default: true)"
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

  defp dispatch("topology", params, frame) do
    Graphonomous.MCP.TopologyAnalyze.execute(params, frame)
  end

  defp dispatch("deliberate", params, frame) do
    Graphonomous.MCP.Deliberate.execute(params, frame)
  end

  defp dispatch("attention_survey", params, frame) do
    Graphonomous.MCP.AttentionSurvey.execute(params, frame)
  end

  defp dispatch("attention_cycle", params, frame) do
    Graphonomous.MCP.AttentionRunCycle.execute(params, frame)
  end

  defp dispatch("review_goal", params, frame) do
    Graphonomous.MCP.ReviewGoal.execute(params, frame)
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
