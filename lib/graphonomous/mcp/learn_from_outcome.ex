defmodule Graphonomous.MCP.LearnFromOutcome do
  @moduledoc """
  MCP tool that processes outcome feedback and updates confidence on causal nodes.

  This is the core continual-learning loop:
  - receive action outcome
  - identify causal nodes
  - apply confidence updates through Graphonomous.Learner
  """

  use Anubis.Server.Component, type: :tool

  @allowed_statuses ~w(success partial_success failure timeout)

  schema do
    field(:action_id, :string,
      required: true,
      description: "ID of the action that produced this outcome"
    )

    field(:status, :string,
      required: true,
      description: "success, partial_success, failure, or timeout"
    )

    field(:confidence, :number,
      required: true,
      description: "0.0-1.0 confidence in this outcome signal"
    )

    field(:causal_node_ids, :string,
      required: true,
      description: "JSON array of node IDs that informed this action"
    )

    field(:evidence, :string, description: "Optional JSON object with additional evidence")

    field(:retrieval_trace_id, :string,
      description: "Optional retrieval trace identifier for causal provenance"
    )

    field(:decision_trace_id, :string,
      description: "Optional decision trace identifier linking planner/executor context"
    )

    field(:action_linkage, :string,
      description: "Optional JSON object describing action linkage metadata"
    )

    field(:grounding, :string,
      description: "Optional JSON object for outcome grounding provenance"
    )
  end

  @impl true
  def execute(params, frame) do
    with {:ok, action_id} <- read_required_string(params, :action_id),
         {:ok, status} <- read_status(params),
         {:ok, confidence} <- read_confidence(params),
         {:ok, causal_node_ids} <- read_causal_node_ids(params),
         {:ok, evidence} <- read_evidence(params),
         {:ok, retrieval_trace_id} <- read_optional_string(params, :retrieval_trace_id),
         {:ok, decision_trace_id} <- read_optional_string(params, :decision_trace_id),
         {:ok, action_linkage} <- read_optional_json_map(params, :action_linkage),
         {:ok, grounding} <- read_optional_json_map(params, :grounding),
         {:ok, result} <-
           do_learn(%{
             action_id: action_id,
             status: status,
             confidence: confidence,
             causal_node_ids: causal_node_ids,
             evidence: evidence,
             retrieval_trace_id: retrieval_trace_id,
             decision_trace_id: decision_trace_id,
             action_linkage: action_linkage,
             grounding: grounding
           }) do
      response = %{
        action_id: action_id,
        status: to_string(status),
        retrieval_trace_id: retrieval_trace_id,
        decision_trace_id: decision_trace_id,
        processed: Map.get(result, :processed, length(causal_node_ids)),
        updated: Map.get(result, :updated, 0),
        skipped: Map.get(result, :skipped, 0),
        updates: Map.get(result, :updates, [])
      }

      {:ok, Jason.encode!(response), frame}
    else
      {:error, reason} ->
        {:ok, Jason.encode!(%{error: format_reason(reason)}), frame}
    end
  end

  defp do_learn(payload) do
    case Graphonomous.learn_from_outcome(payload) do
      {:error, _} = err -> err
      %{} = result -> {:ok, result}
      other -> {:error, {:unexpected_result, other}}
    end
  end

  defp read_required_string(params, key) do
    case fetch(params, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          {:ok, trimmed}
        else
          {:error, {:missing_or_invalid, key}}
        end

      _ ->
        {:error, {:missing_or_invalid, key}}
    end
  end

  defp read_status(params) do
    with {:ok, raw} <- read_required_string(params, :status),
         normalized <- String.downcase(raw),
         true <- normalized in @allowed_statuses do
      {:ok, String.to_atom(normalized)}
    else
      false -> {:error, {:invalid_status, fetch(params, :status)}}
      {:error, _} = err -> err
    end
  end

  defp read_confidence(params) do
    value = fetch(params, :confidence)

    cond do
      is_float(value) ->
        {:ok, clamp01(value)}

      is_integer(value) ->
        {:ok, clamp01(value * 1.0)}

      is_binary(value) ->
        case Float.parse(value) do
          {parsed, _} -> {:ok, clamp01(parsed)}
          :error -> {:error, {:invalid_confidence, value}}
        end

      true ->
        {:error, {:invalid_confidence, value}}
    end
  end

  defp read_causal_node_ids(params) do
    raw = fetch(params, :causal_node_ids)

    cond do
      is_binary(raw) ->
        decode_string_ids(raw)

      is_list(raw) ->
        {:ok, Enum.filter(raw, &is_binary/1)}

      true ->
        {:error, {:invalid_causal_node_ids, raw}}
    end
  end

  defp decode_string_ids(raw) do
    trimmed = String.trim(raw)

    cond do
      trimmed == "" ->
        {:ok, []}

      true ->
        case Jason.decode(trimmed) do
          {:ok, list} when is_list(list) ->
            {:ok, Enum.filter(list, &is_binary/1)}

          {:ok, _other} ->
            {:error, {:invalid_causal_node_ids, raw}}

          {:error, _} ->
            {:error, {:invalid_causal_node_ids, raw}}
        end
    end
  end

  defp read_evidence(params) do
    case fetch(params, :evidence) do
      nil ->
        {:ok, %{}}

      value when is_map(value) ->
        {:ok, value}

      value when is_binary(value) ->
        trimmed = String.trim(value)

        cond do
          trimmed == "" ->
            {:ok, %{}}

          true ->
            case Jason.decode(trimmed) do
              {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
              {:ok, _} -> {:error, {:invalid_evidence, value}}
              {:error, _} -> {:error, {:invalid_evidence, value}}
            end
        end

      other ->
        {:error, {:invalid_evidence, other}}
    end
  end

  defp read_optional_string(params, key) do
    case fetch(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        trimmed = String.trim(value)
        {:ok, if(trimmed == "", do: nil, else: trimmed)}

      other ->
        {:error, {:invalid_optional_string, key, other}}
    end
  end

  defp read_optional_json_map(params, key) do
    case fetch(params, key) do
      nil ->
        {:ok, %{}}

      value when is_map(value) ->
        {:ok, value}

      value when is_binary(value) ->
        trimmed = String.trim(value)

        cond do
          trimmed == "" ->
            {:ok, %{}}

          true ->
            case Jason.decode(trimmed) do
              {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
              {:ok, _} -> {:error, {:invalid_optional_json_map, key, value}}
              {:error, _} -> {:error, {:invalid_optional_json_map, key, value}}
            end
        end

      other ->
        {:error, {:invalid_optional_json_map, key, other}}
    end
  end

  defp fetch(params, key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp clamp01(v) when v < 0.0, do: 0.0
  defp clamp01(v) when v > 1.0, do: 1.0
  defp clamp01(v), do: v

  defp format_reason({:missing_or_invalid, key}), do: "#{key} is required"

  defp format_reason({:invalid_status, _}),
    do: "status must be one of: success, partial_success, failure, timeout"

  defp format_reason({:invalid_confidence, _}),
    do: "confidence must be a number in the range 0.0..1.0"

  defp format_reason({:invalid_causal_node_ids, _}),
    do: "causal_node_ids must be a JSON array of node ID strings"

  defp format_reason({:invalid_evidence, _}), do: "evidence must be a JSON object string"

  defp format_reason({:invalid_optional_string, :retrieval_trace_id, _}),
    do: "retrieval_trace_id must be a string"

  defp format_reason({:invalid_optional_string, :decision_trace_id, _}),
    do: "decision_trace_id must be a string"

  defp format_reason({:invalid_optional_json_map, :action_linkage, _}),
    do: "action_linkage must be a JSON object string"

  defp format_reason({:invalid_optional_json_map, :grounding, _}),
    do: "grounding must be a JSON object string"

  defp format_reason({:unexpected_result, _}), do: "unexpected learning result"
  defp format_reason(other), do: inspect(other)
end
