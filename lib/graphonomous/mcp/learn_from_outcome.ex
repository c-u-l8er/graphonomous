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
    field :action_id, :string, required: true,
      description: "ID of the action that produced this outcome"

    field :status, :string, required: true,
      description: "success, partial_success, failure, or timeout"

    field :confidence, :number, required: true,
      description: "0.0-1.0 confidence in this outcome signal"

    field :causal_node_ids, :string, required: true,
      description: "JSON array of node IDs that informed this action"

    field :evidence, :string,
      description: "Optional JSON object with additional evidence"
  end

  @impl true
  def execute(params, frame) do
    with {:ok, action_id} <- read_required_string(params, :action_id),
         {:ok, status} <- read_status(params),
         {:ok, confidence} <- read_confidence(params),
         {:ok, causal_node_ids} <- read_causal_node_ids(params),
         {:ok, evidence} <- read_evidence(params),
         {:ok, result} <-
           do_learn(%{
             action_id: action_id,
             status: status,
             confidence: confidence,
             causal_node_ids: causal_node_ids,
             evidence: evidence
           }) do
      response = %{
        action_id: action_id,
        status: to_string(status),
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

  defp fetch(params, key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp clamp01(v) when v < 0.0, do: 0.0
  defp clamp01(v) when v > 1.0, do: 1.0
  defp clamp01(v), do: v

  defp format_reason({:missing_or_invalid, key}), do: "#{key} is required"
  defp format_reason({:invalid_status, _}), do: "status must be one of: success, partial_success, failure, timeout"
  defp format_reason({:invalid_confidence, _}), do: "confidence must be a number in the range 0.0..1.0"
  defp format_reason({:invalid_causal_node_ids, _}), do: "causal_node_ids must be a JSON array of node ID strings"
  defp format_reason({:invalid_evidence, _}), do: "evidence must be a JSON object string"
  defp format_reason({:unexpected_result, _}), do: "unexpected learning result"
  defp format_reason(other), do: inspect(other)
end
