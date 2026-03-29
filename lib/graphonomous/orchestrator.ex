defmodule Graphonomous.Orchestrator do
  @moduledoc """
  Stability-plasticity monitoring and learning rate adaptation.

  The Orchestrator sits between the Learner and the knowledge graph,
  tracking learning dynamics and adapting the system's plasticity:

  - **High plasticity** (rapid change): lower learning rate to prevent instability
  - **High stability** (little change): allow higher learning rate for novel info
  - **Timescale assignment**: recommend fast/medium/slow/glacial based on content

  ## Metrics tracked

  - Node creation rate (per minute)
  - Confidence change rate (mean absolute delta per update)
  - Churn rate (fraction of nodes updated recently)
  - Novelty rate (fraction of novel queries)

  ## Telemetry events

  - `[:graphonomous, :orchestrator, :metrics_updated]`
  - `[:graphonomous, :orchestrator, :learning_rate_adapted]`
  """

  use GenServer

  require Logger

  @default_sample_window_ms 60_000
  @default_base_learning_rate 0.2
  @default_min_learning_rate 0.05
  @default_max_learning_rate 0.4
  @default_metrics_interval_ms 30_000

  # Plasticity targets
  @high_churn_threshold 0.3
  @low_churn_threshold 0.05
  @high_delta_threshold 0.15
  @low_delta_threshold 0.03

  @type state :: %{
          base_learning_rate: float(),
          current_learning_rate: float(),
          min_learning_rate: float(),
          max_learning_rate: float(),
          sample_window_ms: pos_integer(),
          metrics_interval_ms: pos_integer(),
          timer_ref: reference() | nil,
          # Rolling counters (reset each window)
          nodes_created: non_neg_integer(),
          outcomes_processed: non_neg_integer(),
          confidence_deltas: [float()],
          novelty_checks: non_neg_integer(),
          novel_count: non_neg_integer(),
          # Computed metrics
          metrics: map(),
          last_computed_at: DateTime.t() | nil
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Report that a node was created (called by store pipeline).
  """
  @spec record_node_created() :: :ok
  def record_node_created do
    GenServer.cast(__MODULE__, :node_created)
  end

  @doc """
  Report an outcome was processed with confidence deltas.
  """
  @spec record_outcome(float()) :: :ok
  def record_outcome(mean_delta) when is_number(mean_delta) do
    GenServer.cast(__MODULE__, {:outcome_processed, mean_delta})
  end

  @doc """
  Report a novelty check result.
  """
  @spec record_novelty_check(boolean()) :: :ok
  def record_novelty_check(is_novel) when is_boolean(is_novel) do
    GenServer.cast(__MODULE__, {:novelty_check, is_novel})
  end

  @doc """
  Get the current recommended learning rate.
  """
  @spec current_learning_rate() :: float()
  def current_learning_rate do
    GenServer.call(__MODULE__, :current_learning_rate)
  end

  @doc """
  Recommend a timescale for content based on novelty and type.
  """
  @spec recommend_timescale(map()) :: :fast | :medium | :slow | :glacial
  def recommend_timescale(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:recommend_timescale, attrs})
  end

  @doc """
  Return current orchestrator metrics and state.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    base_lr =
      normalize_probability(Keyword.get(opts, :learning_rate, @default_base_learning_rate))

    state = %{
      base_learning_rate: base_lr,
      current_learning_rate: base_lr,
      min_learning_rate:
        normalize_probability(Keyword.get(opts, :min_learning_rate, @default_min_learning_rate)),
      max_learning_rate:
        normalize_probability(Keyword.get(opts, :max_learning_rate, @default_max_learning_rate)),
      sample_window_ms:
        normalize_pos_int(Keyword.get(opts, :sample_window_ms, @default_sample_window_ms)),
      metrics_interval_ms:
        normalize_pos_int(Keyword.get(opts, :metrics_interval_ms, @default_metrics_interval_ms)),
      timer_ref: nil,
      nodes_created: 0,
      outcomes_processed: 0,
      confidence_deltas: [],
      novelty_checks: 0,
      novel_count: 0,
      metrics: initial_metrics(),
      last_computed_at: nil
    }

    # Attach telemetry handlers to observe learning activity
    attach_telemetry()

    timer_ref = schedule_metrics(state.metrics_interval_ms)

    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_cast(:node_created, state) do
    {:noreply, %{state | nodes_created: state.nodes_created + 1}}
  end

  def handle_cast({:outcome_processed, delta}, state) do
    {:noreply,
     %{
       state
       | outcomes_processed: state.outcomes_processed + 1,
         confidence_deltas: [abs(delta) | Enum.take(state.confidence_deltas, 99)]
     }}
  end

  def handle_cast({:novelty_check, is_novel}, state) do
    novel_inc = if is_novel, do: 1, else: 0

    {:noreply,
     %{
       state
       | novelty_checks: state.novelty_checks + 1,
         novel_count: state.novel_count + novel_inc
     }}
  end

  @impl true
  def handle_call(:current_learning_rate, _from, state) do
    {:reply, state.current_learning_rate, state}
  end

  def handle_call({:recommend_timescale, attrs}, _from, state) do
    timescale = do_recommend_timescale(attrs, state.metrics)
    {:reply, timescale, state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      current_learning_rate: state.current_learning_rate,
      base_learning_rate: state.base_learning_rate,
      min_learning_rate: state.min_learning_rate,
      max_learning_rate: state.max_learning_rate,
      metrics: state.metrics,
      last_computed_at: state.last_computed_at,
      counters: %{
        nodes_created: state.nodes_created,
        outcomes_processed: state.outcomes_processed,
        novelty_checks: state.novelty_checks,
        novel_count: state.novel_count
      }
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info(:compute_metrics, state) do
    new_metrics = compute_metrics(state)
    new_lr = adapt_learning_rate(state, new_metrics)

    if new_lr != state.current_learning_rate do
      :telemetry.execute(
        [:graphonomous, :orchestrator, :learning_rate_adapted],
        %{old_rate: state.current_learning_rate, new_rate: new_lr},
        %{metrics: new_metrics}
      )

      Logger.debug(
        "Orchestrator: learning rate #{Float.round(state.current_learning_rate, 4)} → #{Float.round(new_lr, 4)}"
      )
    end

    :telemetry.execute(
      [:graphonomous, :orchestrator, :metrics_updated],
      new_metrics,
      %{}
    )

    timer_ref = schedule_metrics(state.metrics_interval_ms)

    {:noreply,
     %{
       state
       | metrics: new_metrics,
         current_learning_rate: new_lr,
         last_computed_at: DateTime.utc_now(),
         timer_ref: timer_ref,
         # Reset rolling counters
         nodes_created: 0,
         outcomes_processed: 0,
         confidence_deltas: [],
         novelty_checks: 0,
         novel_count: 0
     }}
  end

  ## Metrics computation

  defp compute_metrics(state) do
    window_minutes = max(state.metrics_interval_ms / 60_000, 0.5)

    node_creation_rate = state.nodes_created / window_minutes
    outcome_rate = state.outcomes_processed / window_minutes

    mean_confidence_delta =
      case state.confidence_deltas do
        [] -> 0.0
        deltas -> Enum.sum(deltas) / length(deltas)
      end

    novelty_rate =
      if state.novelty_checks > 0 do
        state.novel_count / state.novelty_checks
      else
        0.0
      end

    # Estimate churn: fraction of outcomes vs total node approximation
    # (We don't query node count here to avoid blocking; use a heuristic)
    churn_estimate =
      if state.outcomes_processed > 0 do
        min(state.outcomes_processed / max(state.nodes_created + 10, 10), 1.0)
      else
        0.0
      end

    %{
      node_creation_rate: Float.round(node_creation_rate, 4),
      outcome_rate: Float.round(outcome_rate, 4),
      mean_confidence_delta: Float.round(mean_confidence_delta, 6),
      novelty_rate: Float.round(novelty_rate, 4),
      churn_estimate: Float.round(churn_estimate, 4),
      plasticity_level: classify_plasticity(churn_estimate, mean_confidence_delta),
      window_minutes: Float.round(window_minutes, 2)
    }
  end

  defp classify_plasticity(churn, delta) do
    cond do
      churn > @high_churn_threshold or delta > @high_delta_threshold -> :high
      churn < @low_churn_threshold and delta < @low_delta_threshold -> :low
      true -> :moderate
    end
  end

  ## Learning rate adaptation

  defp adapt_learning_rate(state, metrics) do
    plasticity = Map.get(metrics, :plasticity_level, :moderate)

    target_lr =
      case plasticity do
        :high ->
          # Too much change — reduce plasticity
          state.base_learning_rate * 0.5

        :low ->
          # Graph is stable — allow more learning
          state.base_learning_rate * 1.5

        :moderate ->
          state.base_learning_rate
      end

    # Smooth toward target (don't jump)
    smoothed = state.current_learning_rate * 0.7 + target_lr * 0.3

    smoothed
    |> max(state.min_learning_rate)
    |> min(state.max_learning_rate)
    |> Float.round(6)
  end

  ## Timescale recommendation

  defp do_recommend_timescale(attrs, metrics) do
    node_type = Map.get(attrs, :node_type) || Map.get(attrs, "node_type")
    confidence = Map.get(attrs, :confidence) || Map.get(attrs, "confidence") || 0.5
    plasticity = Map.get(metrics, :plasticity_level, :moderate)

    cond do
      # Episodic events start fast, may promote later
      node_type in [:episodic, "episodic"] ->
        :fast

      # High-confidence procedural knowledge is slow
      node_type in [:procedural, "procedural"] and confidence > 0.7 ->
        :slow

      # Semantic knowledge depends on plasticity
      plasticity == :high ->
        :medium

      confidence > 0.8 ->
        :slow

      confidence < 0.3 ->
        :fast

      true ->
        :medium
    end
  end

  ## Telemetry integration

  defp attach_telemetry do
    :telemetry.attach(
      "orchestrator-outcome-listener",
      [:graphonomous, :outcome, :processed],
      &handle_outcome_telemetry/4,
      nil
    )

    :telemetry.attach(
      "orchestrator-confidence-listener",
      [:graphonomous, :node, :confidence_updated],
      &handle_confidence_telemetry/4,
      nil
    )
  rescue
    _ -> :ok
  end

  defp handle_outcome_telemetry(_event, measurements, _metadata, _config) do
    updated = Map.get(measurements, :updated, 0)

    if updated > 0 do
      GenServer.cast(__MODULE__, {:outcome_processed, 0.0})
    end
  rescue
    _ -> :ok
  end

  defp handle_confidence_telemetry(_event, measurements, _metadata, _config) do
    delta = Map.get(measurements, :delta, 0.0)
    GenServer.cast(__MODULE__, {:outcome_processed, delta})
  rescue
    _ -> :ok
  end

  ## Helpers

  defp schedule_metrics(interval_ms) do
    Process.send_after(self(), :compute_metrics, interval_ms)
  end

  defp initial_metrics do
    %{
      node_creation_rate: 0.0,
      outcome_rate: 0.0,
      mean_confidence_delta: 0.0,
      novelty_rate: 0.0,
      churn_estimate: 0.0,
      plasticity_level: :moderate,
      window_minutes: 0.0
    }
  end

  defp normalize_probability(v) when is_float(v), do: max(0.0, min(1.0, v))
  defp normalize_probability(v) when is_integer(v), do: normalize_probability(v * 1.0)

  defp normalize_probability(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> normalize_probability(f)
      :error -> 0.5
    end
  end

  defp normalize_probability(_), do: 0.5

  defp normalize_pos_int(v) when is_integer(v) and v > 0, do: v
  defp normalize_pos_int(_), do: @default_metrics_interval_ms
end
