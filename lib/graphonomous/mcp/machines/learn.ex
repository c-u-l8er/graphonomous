defmodule Graphonomous.MCP.Machines.Learn do
  @moduledoc """
  Loop Phase 4: LEARN — "Did it work?"

  Unified learning machine for the Graphonomous memory loop.
  The agent calls this after acting to close the feedback loop.

  Actions:
  - `from_outcome`    — causal confidence updates from action results
  - `from_feedback`   — positive/negative/correction feedback
  - `detect_novelty`  — similarity-based novelty scoring
  - `from_interaction` — full pipeline: novelty → store → extract → link
  - `contradictions`  — detect belief conflicts in the graph

  Replaces: learn_from_outcome, learn_from_feedback, learn_detect_novelty,
            learn_from_interaction, belief_contradictions
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(from_outcome from_feedback detect_novelty from_interaction contradictions)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Learning action: from_outcome | from_feedback | detect_novelty | from_interaction | contradictions"
    )

    # -- from_outcome --
    field(:action_id, :string, description: "ID of the action that produced this outcome (from_outcome)")

    field(:status, :string,
      description:
        "Outcome status: success | partial_success | failure | timeout (from_outcome)"
    )

    field(:confidence, :number,
      description: "Confidence in this outcome signal 0.0-1.0 (from_outcome)"
    )

    field(:causal_node_ids, :string,
      description: "JSON array of node IDs that informed this action (from_outcome)"
    )

    field(:evidence, :string,
      description: "JSON object with additional evidence (from_outcome, from_feedback)"
    )

    field(:retrieval_trace_id, :string,
      description: "Retrieval trace ID for causal provenance (from_outcome)"
    )

    field(:decision_trace_id, :string,
      description: "Decision trace ID linking planner/executor context (from_outcome)"
    )

    field(:action_linkage, :string,
      description: "JSON object describing action linkage (from_outcome)"
    )

    field(:grounding, :string,
      description: "JSON object for outcome grounding provenance (from_outcome)"
    )

    # -- from_feedback --
    field(:node_id, :string,
      description: "Target node ID (from_feedback, contradictions)"
    )

    field(:feedback_type, :string,
      description: "Feedback type: positive | negative | correction (from_feedback)"
    )

    field(:correction, :string,
      description: "Corrected content when feedback_type is correction (from_feedback)"
    )

    # -- detect_novelty --
    field(:content, :string,
      description: "Content to check for novelty (detect_novelty, from_interaction)"
    )

    field(:threshold, :number,
      description: "Novelty threshold 0.0-1.0 (detect_novelty, default: 0.7)"
    )

    # -- from_interaction --
    field(:source, :string, description: "Source of the interaction (from_interaction)")

    field(:node_type, :string,
      description: "Node type for storage: episodic, semantic, procedural (from_interaction)"
    )

    # -- contradictions --
    field(:query, :string,
      description: "Query to scope contradiction detection (contradictions)"
    )

    field(:limit, :number,
      description: "Max contradictions to return (contradictions, default: 10)"
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

  defp dispatch("from_outcome", params, frame) do
    Graphonomous.MCP.LearnFromOutcome.execute(params, frame)
  end

  defp dispatch("from_feedback", params, frame) do
    Graphonomous.MCP.LearnFromFeedback.execute(params, frame)
  end

  defp dispatch("detect_novelty", params, frame) do
    Graphonomous.MCP.LearnDetectNovelty.execute(params, frame)
  end

  defp dispatch("from_interaction", params, frame) do
    Graphonomous.MCP.LearnFromInteraction.execute(params, frame)
  end

  defp dispatch("contradictions", params, frame) do
    Graphonomous.MCP.BeliefContradictions.execute(params, frame)
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
