defmodule Graphonomous.MCP.LearnFromFeedback do
  @moduledoc """
  MCP tool for integrating explicit user feedback on a knowledge node.

  Supports three feedback types:
  - `positive` — reinforces confidence
  - `negative` — decreases confidence
  - `correction` — replaces content and resets confidence

  Internally this delegates to the Learner's confidence update mechanism
  (via `learn_from_outcome`) for positive/negative, and to direct node
  update for corrections.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @allowed_feedback ~w(positive negative correction)

  schema do
    field(:node_id, :string,
      required: true,
      description: "ID of the node to apply feedback to"
    )

    field(:feedback, :string,
      required: true,
      description: "Feedback type: positive, negative, or correction"
    )

    field(:correction, :string,
      description: "Corrected content (required when feedback is 'correction')"
    )

    field(:reason, :string, description: "Optional reason for the feedback")
  end

  @impl true
  def execute(params, frame) do
    with {:ok, node_id} <- read_required_string(params, :node_id),
         {:ok, feedback} <- read_feedback(params),
         {:ok, correction} <- read_correction(params, feedback),
         {:ok, reason} <- read_optional_string(params, :reason) do
      case apply_feedback(node_id, feedback, correction, reason) do
        {:ok, result} ->
          {:reply, ok_response(result), frame}

        {:error, reason} ->
          {:reply, error_response(format_reason(reason)), frame}
      end
    else
      {:error, reason} ->
        {:reply, error_response(format_reason(reason)), frame}
    end
  end

  defp apply_feedback(node_id, :positive, _correction, reason) do
    # Use learn_from_outcome with success status to boost confidence
    case Graphonomous.learn_from_outcome(%{
           action_id: "feedback_positive_#{gen_suffix()}",
           status: :success,
           confidence: 0.9,
           causal_node_ids: [node_id],
           evidence: %{type: "user_feedback", feedback: "positive", reason: reason}
         }) do
      %{updates: updates} ->
        updated_node = fetch_updated_node(node_id, updates)
        {:ok, build_result(node_id, :positive, updated_node)}

      {:error, _} = err ->
        err
    end
  end

  defp apply_feedback(node_id, :negative, _correction, reason) do
    # Use learn_from_outcome with failure status to decrease confidence
    case Graphonomous.learn_from_outcome(%{
           action_id: "feedback_negative_#{gen_suffix()}",
           status: :failure,
           confidence: 0.9,
           causal_node_ids: [node_id],
           evidence: %{type: "user_feedback", feedback: "negative", reason: reason}
         }) do
      %{updates: updates} ->
        updated_node = fetch_updated_node(node_id, updates)
        {:ok, build_result(node_id, :negative, updated_node)}

      {:error, _} = err ->
        err
    end
  end

  defp apply_feedback(node_id, :correction, correction_text, reason) do
    # Direct update: replace content, reset confidence to moderate level
    case Graphonomous.get_node(node_id) do
      %{} = node ->
        old_content = Map.get(node, :content)
        old_confidence = Map.get(node, :confidence, 0.5)

        metadata =
          (Map.get(node, :metadata) || %{})
          |> Map.put("last_correction", %{
            old_content: old_content,
            old_confidence: old_confidence,
            reason: reason,
            corrected_at: DateTime.to_iso8601(DateTime.utc_now())
          })
          |> Map.update("correction_count", 1, fn n ->
            if is_integer(n), do: n + 1, else: 1
          end)

        case Graphonomous.update_node(node_id, %{
               content: correction_text,
               confidence: 0.6,
               metadata: metadata
             }) do
          %{} = updated ->
            {:ok,
             %{
               node_id: node_id,
               feedback: "correction",
               old_content: old_content,
               new_content: correction_text,
               old_confidence: old_confidence,
               new_confidence: Map.get(updated, :confidence, 0.6)
             }}

          {:error, _} = err ->
            err
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, _} = err ->
        err
    end
  end

  defp build_result(node_id, feedback_type, updated_node) do
    base = %{
      node_id: node_id,
      feedback: to_string(feedback_type)
    }

    case updated_node do
      %{old_confidence: old_c, new_confidence: new_c} ->
        Map.merge(base, %{
          old_confidence: old_c,
          new_confidence: new_c,
          confidence_delta: new_c - old_c
        })

      _ ->
        base
    end
  end

  defp fetch_updated_node(node_id, updates) when is_list(updates) do
    Enum.find(updates, fn u ->
      Map.get(u, :node_id) == node_id and Map.get(u, :result) == :updated
    end)
  end

  defp fetch_updated_node(_node_id, _), do: nil

  defp ok_response(data) do
    payload = Map.put(data, :status, "ok")

    Response.tool()
    |> Response.text(Jason.encode!(payload))
  end

  defp error_response(message) do
    payload = %{status: "error", error: message}

    Response.tool()
    |> Response.text(Jason.encode!(payload))
    |> Map.put(:isError, true)
  end

  defp read_required_string(params, key) do
    case fetch(params, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed != "", do: {:ok, trimmed}, else: {:error, {:missing, key}}

      _ ->
        {:error, {:missing, key}}
    end
  end

  defp read_feedback(params) do
    case fetch(params, :feedback) do
      value when is_binary(value) ->
        normalized = value |> String.trim() |> String.downcase()

        if normalized in @allowed_feedback do
          {:ok, String.to_atom(normalized)}
        else
          {:error, :invalid_feedback}
        end

      _ ->
        {:error, {:missing, :feedback}}
    end
  end

  defp read_correction(params, :correction) do
    case fetch(params, :correction) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed != "", do: {:ok, trimmed}, else: {:error, :correction_required}

      _ ->
        {:error, :correction_required}
    end
  end

  defp read_correction(_params, _feedback), do: {:ok, nil}

  defp read_optional_string(params, key) do
    case fetch(params, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, String.trim(value)}
      _ -> {:ok, nil}
    end
  end

  defp fetch(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp gen_suffix do
    6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  defp format_reason({:missing, key}), do: "#{key} is required"
  defp format_reason(:invalid_feedback), do: "feedback must be: positive, negative, or correction"

  defp format_reason(:correction_required),
    do: "correction text is required when feedback is 'correction'"

  defp format_reason(:not_found), do: "node not found"
  defp format_reason(other), do: inspect(other)
end
