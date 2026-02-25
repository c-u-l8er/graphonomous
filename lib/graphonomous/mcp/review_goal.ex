defmodule Graphonomous.MCP.ReviewGoal do
  @moduledoc """
  MCP tool for epistemic goal review and coverage decisions.

  This tool:
  1. Accepts a coverage signal payload for a goal.
  2. Runs Graphonomous coverage evaluation + persisted review.
  3. Optionally applies a status transition policy from the decision:
     - `:act` -> `:active`
     - `:learn` -> `:proposed`
     - `:escalate` -> `:blocked`
  """

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response

  @default_apply_decision true

  schema do
    field(:goal_id, :string,
      required: true,
      description: "Goal ID to review"
    )

    field(:signal, :string,
      required: true,
      description:
        "Coverage signal as a JSON object. Example: {\"retrieved_nodes\": [...], \"outcomes\": [...], \"contradictions\": 1}"
    )

    field(:options, :string,
      description:
        "Optional JSON object for coverage options (top_k, min_context_nodes, freshness_half_life_hours, graph_support_target, weights, thresholds)"
    )

    field(:apply_decision, :string,
      description:
        "Optional boolean-like flag (true/false). If true, applies decision -> status transition policy"
    )

    field(:transition_metadata, :string,
      description:
        "Optional JSON object merged into transition metadata when apply_decision is enabled"
    )
  end

  @impl true
  def execute(params, frame) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         {:ok, signal} <- read_required_json_object(params, :signal),
         {:ok, options_map} <- read_optional_json_object(params, :options),
         {:ok, transition_meta} <- read_optional_json_object(params, :transition_metadata) do
      review_opts = build_review_opts(options_map)
      apply_decision? = read_bool(params, :apply_decision, @default_apply_decision)

      case Graphonomous.review_goal(goal_id, signal, review_opts) do
        {:ok, goal, evaluation} when is_map(goal) and is_map(evaluation) ->
          transition_result =
            maybe_apply_decision_transition(goal, evaluation, apply_decision?, transition_meta)

          payload =
            %{
              status: "ok",
              goal_id: goal_id,
              applied_review: true,
              apply_decision: apply_decision?,
              decision: decision_string(evaluation),
              decision_confidence: Map.get(evaluation, :decision_confidence),
              coverage_score: Map.get(evaluation, :coverage_score),
              uncertainty_score: Map.get(evaluation, :uncertainty_score),
              risk_score: Map.get(evaluation, :risk_score),
              rationale: Map.get(evaluation, :rationale, []),
              transition: transition_result,
              goal: serialize_term(goal),
              evaluation: serialize_term(evaluation)
            }

          {:reply, tool_response(payload), frame}

        {:error, reason} ->
          error = %{
            status: "error",
            error: "review_goal_failed",
            reason: inspect(reason)
          }

          {:reply, tool_response(error), frame}

        other ->
          fallback = %{
            status: "error",
            error: "unexpected_review_result",
            result: inspect(other)
          }

          {:reply, tool_response(fallback), frame}
      end
    else
      {:error, reason} ->
        {:reply, tool_response(%{status: "error", error: format_reason(reason)}), frame}
    end
  end

  defp maybe_apply_decision_transition(_goal, _evaluation, false, _transition_meta) do
    %{
      attempted: false,
      applied: false,
      reason: "apply_decision disabled"
    }
  end

  defp maybe_apply_decision_transition(goal, evaluation, true, transition_meta)
       when is_map(goal) and is_map(evaluation) do
    decision = Map.get(evaluation, :decision)
    target_status = status_for_decision(decision)
    current_status = normalize_status(Map.get(goal, :status))
    goal_id = get_val(goal, :id)

    cond do
      not is_binary(goal_id) or String.trim(goal_id) == "" ->
        %{attempted: false, applied: false, reason: "goal missing id"}

      is_nil(target_status) ->
        %{attempted: false, applied: false, reason: "no transition policy for decision"}

      current_status == target_status ->
        %{
          attempted: true,
          applied: false,
          reason: "already_in_target_status",
          from_status: atom_to_string(current_status),
          to_status: atom_to_string(target_status)
        }

      true ->
        transition_payload =
          transition_meta
          |> normalize_map()
          |> Map.put_new("source", "mcp.review_goal")
          |> Map.put_new("policy", "coverage_decision")
          |> Map.put_new("decision", atom_to_string(decision))
          |> Map.put_new("decision_confidence", Map.get(evaluation, :decision_confidence))
          |> Map.put_new("coverage_score", Map.get(evaluation, :coverage_score))
          |> Map.put_new("uncertainty_score", Map.get(evaluation, :uncertainty_score))
          |> Map.put_new("risk_score", Map.get(evaluation, :risk_score))

        case Graphonomous.transition_goal(goal_id, target_status, transition_payload) do
          %{} = transitioned_goal ->
            %{
              attempted: true,
              applied: true,
              from_status: atom_to_string(current_status),
              to_status: atom_to_string(target_status),
              goal: serialize_term(transitioned_goal)
            }

          {:error, reason} ->
            %{
              attempted: true,
              applied: false,
              from_status: atom_to_string(current_status),
              to_status: atom_to_string(target_status),
              reason: inspect(reason)
            }

          other ->
            %{
              attempted: true,
              applied: false,
              from_status: atom_to_string(current_status),
              to_status: atom_to_string(target_status),
              reason: "unexpected_transition_result",
              result: inspect(other)
            }
        end
    end
  end

  defp status_for_decision(:act), do: :active
  defp status_for_decision(:learn), do: :proposed
  defp status_for_decision(:escalate), do: :blocked
  defp status_for_decision("act"), do: :active
  defp status_for_decision("learn"), do: :proposed
  defp status_for_decision("escalate"), do: :blocked
  defp status_for_decision(_), do: nil

  defp decision_string(evaluation) do
    evaluation
    |> Map.get(:decision)
    |> atom_to_string()
  end

  defp build_review_opts(options_map) when is_map(options_map) do
    []
    |> maybe_put_opt(:top_k, get_num(options_map, "top_k", nil))
    |> maybe_put_opt(:min_context_nodes, get_num(options_map, "min_context_nodes", nil))
    |> maybe_put_opt(
      :freshness_half_life_hours,
      get_num(options_map, "freshness_half_life_hours", nil)
    )
    |> maybe_put_opt(:graph_support_target, get_num(options_map, "graph_support_target", nil))
    |> maybe_put_opt(:weights, get_map(options_map, "weights", nil))
    |> maybe_put_opt(:thresholds, get_map(options_map, "thresholds", nil))
  end

  defp build_review_opts(_), do: []

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp tool_response(payload) when is_map(payload) do
    Response.tool()
    |> Response.text(Jason.encode!(payload))
  end

  defp read_required_string(params, key) do
    case fetch(params, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error, {:missing_or_invalid, key}}
        else
          {:ok, trimmed}
        end

      _ ->
        {:error, {:missing_or_invalid, key}}
    end
  end

  defp read_required_json_object(params, key) do
    case fetch(params, key) do
      value when is_map(value) ->
        {:ok, value}

      value when is_binary(value) ->
        decode_json_object(value, key)

      _ ->
        {:error, {:missing_or_invalid_json_object, key}}
    end
  end

  defp read_optional_json_object(params, key) do
    case fetch(params, key) do
      nil ->
        {:ok, %{}}

      value when is_map(value) ->
        {:ok, value}

      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:ok, %{}}
        else
          decode_json_object(trimmed, key)
        end

      _ ->
        {:error, {:invalid_json_object, key}}
    end
  end

  defp decode_json_object(raw, key) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _other} -> {:error, {:invalid_json_object, key}}
      {:error, _} -> {:error, {:invalid_json_object, key}}
    end
  end

  defp read_bool(params, key, default) do
    case fetch(params, key) do
      nil ->
        default

      value when is_boolean(value) ->
        value

      value when is_integer(value) ->
        value != 0

      value when is_binary(value) ->
        String.downcase(String.trim(value)) in ["1", "true", "yes", "y"]

      _ ->
        default
    end
  end

  defp fetch(params, key) when is_map(params) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp get_val(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp get_num(map, key, default) when is_map(map) and is_binary(key) do
    value = Map.get(map, key, default)

    cond do
      is_integer(value) ->
        value

      is_float(value) ->
        value

      is_binary(value) ->
        case Float.parse(String.trim(value)) do
          {f, _} -> f
          :error -> default
        end

      true ->
        default
    end
  end

  defp get_map(map, key, default) when is_map(map) and is_binary(key) do
    case Map.get(map, key, default) do
      v when is_map(v) -> v
      _ -> default
    end
  end

  defp normalize_status(value) when is_atom(value), do: value

  defp normalize_status(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "proposed" -> :proposed
      "active" -> :active
      "blocked" -> :blocked
      "completed" -> :completed
      "abandoned" -> :abandoned
      _ -> nil
    end
  end

  defp normalize_status(_), do: nil

  defp atom_to_string(nil), do: nil
  defp atom_to_string(v) when is_atom(v), do: Atom.to_string(v)
  defp atom_to_string(v) when is_binary(v), do: v
  defp atom_to_string(v), do: to_string(v)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp serialize_term(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp serialize_term(value) when is_list(value) do
    Enum.map(value, &serialize_term/1)
  end

  defp serialize_term(value) when is_map(value) do
    map =
      if Map.has_key?(value, :__struct__) do
        Map.from_struct(value)
      else
        value
      end

    Enum.into(map, %{}, fn {k, v} ->
      {k, serialize_term(v)}
    end)
  end

  defp serialize_term(value), do: value

  defp format_reason({:missing_or_invalid, key}),
    do: "#{key} is required and must be a non-empty string"

  defp format_reason({:missing_or_invalid_json_object, key}),
    do: "#{key} is required and must be a JSON object"

  defp format_reason({:invalid_json_object, key}),
    do: "#{key} must be a valid JSON object"

  defp format_reason(other), do: inspect(other)
end
