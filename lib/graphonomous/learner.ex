defmodule Graphonomous.Learner do
  @moduledoc """
  Causal feedback learner.

  Processes outcomes and updates confidence on the nodes that informed an action.
  This is the core continual-learning loop:

    1) Persist outcome evidence.
    2) Update confidence on causal nodes.
    3) Emit telemetry for observability.

  Confidence update (Bayesian-inspired smoothing):

      new_confidence = old * (1 - learning_rate) + target_signal * learning_rate

  Where `target_signal` is derived from status and scaled by outcome confidence.
  """

  use GenServer

  require Logger

  alias Graphonomous.Store
  alias Graphonomous.Types.Node

  @default_learning_rate 0.2

  @type status :: :success | :partial_success | :failure | :timeout

  @type state :: %{
          learning_rate: float()
        }

  @type learn_result :: %{
          action_id: binary(),
          status: status(),
          processed: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer(),
          updates: [map()]
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Learn from an action outcome and update confidence for all causal nodes.

  Expected attrs:
    - `action_id` (string)
    - `status` (`success|partial_success|failure|timeout`)
    - `confidence` (0.0..1.0)
    - `causal_node_ids` ([string])
    - `evidence` (map, optional)
    - `retrieval_trace_id` (string, optional)
    - `decision_trace_id` (string, optional)
    - `action_linkage` (map, optional)
    - `grounding` (map, optional)
    - `observed_at` (DateTime or ISO8601 string, optional)
  """
  @spec learn_from_outcome(map()) :: {:ok, learn_result()} | {:error, term()}
  def learn_from_outcome(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:learn_from_outcome, attrs}, 30_000)
  end

  ## GenServer

  @impl true
  def init(opts) do
    learning_rate =
      opts
      |> Keyword.get(
        :learning_rate,
        Application.get_env(:graphonomous, :learning_rate, @default_learning_rate)
      )
      |> normalize_probability()

    {:ok, %{learning_rate: learning_rate}}
  end

  @impl true
  def handle_call({:learn_from_outcome, attrs}, _from, state) do
    outcome = normalize_outcome(attrs)

    with {:ok, _stored_outcome} <- Store.insert_outcome(outcome),
         {:ok, updates} <- apply_feedback(outcome, state.learning_rate) do
      updated = Enum.count(updates, &(&1.result == :updated))
      skipped = Enum.count(updates, &(&1.result != :updated))

      result = %{
        action_id: outcome.action_id,
        status: outcome.status,
        retrieval_trace_id: outcome.retrieval_trace_id,
        decision_trace_id: outcome.decision_trace_id,
        action_linkage: outcome.action_linkage,
        grounding: outcome.grounding,
        processed: length(outcome.causal_node_ids),
        updated: updated,
        skipped: skipped,
        updates: updates
      }

      :telemetry.execute(
        [:graphonomous, :outcome, :processed],
        %{processed: result.processed, updated: result.updated, skipped: result.skipped},
        %{
          action_id: outcome.action_id,
          status: outcome.status,
          retrieval_trace_id: outcome.retrieval_trace_id,
          decision_trace_id: outcome.decision_trace_id
        }
      )

      {:reply, {:ok, result}, state}
    else
      {:error, reason} = err ->
        Logger.error("Outcome processing failed: #{inspect(reason)}")
        {:reply, err, state}
    end
  end

  ## Core learning logic

  defp apply_feedback(outcome, learning_rate) do
    updates =
      Enum.map(outcome.causal_node_ids, fn node_id ->
        update_node_from_outcome(node_id, outcome, learning_rate)
      end)

    {:ok, updates}
  end

  defp update_node_from_outcome(node_id, outcome, learning_rate) do
    case Store.get_node(node_id) do
      {:ok, %Node{} = node} ->
        old_conf = normalize_probability(node.confidence)

        target_signal =
          outcome.status
          |> status_signal()
          |> scale_signal(outcome.confidence)

        new_conf = update_confidence(old_conf, target_signal, learning_rate)

        node_metadata = if is_map(node.metadata), do: node.metadata, else: %{}

        feedback_entry = %{
          action_id: outcome.action_id,
          status: outcome.status,
          outcome_confidence: outcome.confidence,
          old_confidence: old_conf,
          new_confidence: new_conf,
          retrieval_trace_id: outcome.retrieval_trace_id,
          decision_trace_id: outcome.decision_trace_id,
          action_linkage: outcome.action_linkage,
          grounding: outcome.grounding,
          observed_at: DateTime.to_iso8601(outcome.observed_at)
        }

        merged_metadata =
          node_metadata
          |> Map.put("last_feedback", feedback_entry)
          |> Map.update("feedback_count", 1, fn n ->
            if is_integer(n), do: n + 1, else: 1
          end)

        case Store.update_node(node_id, %{confidence: new_conf, metadata: merged_metadata}) do
          {:ok, _updated_node} ->
            :telemetry.execute(
              [:graphonomous, :node, :confidence_updated],
              %{old_confidence: old_conf, new_confidence: new_conf, delta: new_conf - old_conf},
              %{node_id: node_id, status: outcome.status, action_id: outcome.action_id}
            )

            %{
              node_id: node_id,
              result: :updated,
              old_confidence: old_conf,
              new_confidence: new_conf,
              delta: new_conf - old_conf
            }

          {:error, reason} ->
            %{
              node_id: node_id,
              result: :error,
              error: reason
            }
        end

      {:error, :not_found} ->
        %{
          node_id: node_id,
          result: :skipped_not_found
        }

      {:error, reason} ->
        %{
          node_id: node_id,
          result: :error,
          error: reason
        }
    end
  end

  defp update_confidence(old_conf, target_signal, learning_rate) do
    updated = old_conf * (1.0 - learning_rate) + target_signal * learning_rate
    normalize_probability(updated)
  end

  ## Signal model

  # Raw status signal in [-1, 1]
  defp status_signal(:success), do: 1.0
  defp status_signal(:partial_success), do: 0.4
  defp status_signal(:failure), do: -0.5
  defp status_signal(:timeout), do: -0.25
  defp status_signal(_), do: -0.5

  # Scale by outcome confidence, then map [-1, 1] to [0, 1]
  defp scale_signal(raw_signal, outcome_confidence) do
    scaled = raw_signal * normalize_probability(outcome_confidence)
    ((scaled + 1.0) / 2.0) |> normalize_probability()
  end

  ## Normalization

  defp normalize_outcome(attrs) do
    now = DateTime.utc_now()

    %{
      action_id: map_get(attrs, :action_id, gen_id("action")),
      status: normalize_status(map_get(attrs, :status, :failure)),
      confidence: normalize_probability(map_get(attrs, :confidence, 0.5)),
      causal_node_ids: normalize_node_ids(map_get(attrs, :causal_node_ids, [])),
      evidence: normalize_map(map_get(attrs, :evidence, %{})),
      retrieval_trace_id: normalize_optional_string(map_get(attrs, :retrieval_trace_id, nil)),
      decision_trace_id: normalize_optional_string(map_get(attrs, :decision_trace_id, nil)),
      action_linkage: normalize_map(map_get(attrs, :action_linkage, %{})),
      grounding: normalize_map(map_get(attrs, :grounding, %{})),
      observed_at: normalize_datetime(map_get(attrs, :observed_at, now), now)
    }
  end

  defp normalize_status(v) when v in [:success, :partial_success, :failure, :timeout], do: v

  defp normalize_status(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "success" -> :success
      "partial_success" -> :partial_success
      "failure" -> :failure
      "timeout" -> :timeout
      _ -> :failure
    end
  end

  defp normalize_status(_), do: :failure

  defp normalize_probability(v) when is_float(v), do: clamp(v, 0.0, 1.0)
  defp normalize_probability(v) when is_integer(v), do: normalize_probability(v * 1.0)

  defp normalize_probability(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> normalize_probability(f)
      :error -> 0.5
    end
  end

  defp normalize_probability(_), do: 0.5

  defp normalize_map(v) when is_map(v), do: v
  defp normalize_map(_), do: %{}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(v), do: v |> to_string() |> normalize_optional_string()

  defp normalize_node_ids(v) when is_list(v) do
    v
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_node_ids(_), do: []

  defp normalize_datetime(%DateTime{} = dt, _fallback), do: dt

  defp normalize_datetime(value, fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> fallback
    end
  end

  defp normalize_datetime(_, fallback), do: fallback

  defp map_get(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp gen_id(prefix) do
    suffix =
      12
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "#{prefix}_#{suffix}"
  end
end
