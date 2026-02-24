defmodule Graphonomous.Consolidator do
  @moduledoc """
  Periodic memory maintenance for Graphonomous.

  Responsibilities:
    - decay node confidence over time
    - prune low-confidence nodes
    - emit telemetry for observability

  Telemetry events emitted:
    - `[:graphonomous, :node, :decayed]`
    - `[:graphonomous, :node, :pruned]`
    - `[:graphonomous, :consolidator, :cycle]`
  """

  use GenServer

  require Logger

  alias Graphonomous.Graph

  @default_interval_ms 300_000
  @default_decay_rate 0.02
  @default_prune_threshold 0.1
  @default_merge_similarity 0.95
  @min_interval_ms 1_000

  @type state :: %{
          interval_ms: pos_integer(),
          decay_rate: float(),
          prune_threshold: float(),
          merge_similarity: float(),
          timer_ref: reference() | nil,
          cycle_count: non_neg_integer(),
          last_run_at: DateTime.t() | nil
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an immediate consolidation cycle.

  Useful for tests and manual verification.
  """
  @spec run_now() :: :ok
  def run_now do
    GenServer.cast(__MODULE__, :run_now)
  end

  @doc """
  Returns consolidator runtime info.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      interval_ms:
        opts
        |> Keyword.get(:interval_ms, @default_interval_ms)
        |> normalize_interval(),
      decay_rate:
        opts
        |> Keyword.get(:decay_rate, @default_decay_rate)
        |> normalize_probability(),
      prune_threshold:
        opts
        |> Keyword.get(:prune_threshold, @default_prune_threshold)
        |> normalize_probability(),
      merge_similarity:
        opts
        |> Keyword.get(:merge_similarity, @default_merge_similarity)
        |> normalize_probability(),
      timer_ref: nil,
      cycle_count: 0,
      last_run_at: nil
    }

    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, Map.drop(state, [:timer_ref]), state}
  end

  @impl true
  def handle_cast(:run_now, state) do
    {:noreply, run_cycle(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    state = %{state | timer_ref: nil}
    {:noreply, run_cycle(state)}
  end

  @impl true
  def terminate(_reason, state) do
    cancel_timer(state.timer_ref)
    :ok
  end

  ## Core cycle

  defp run_cycle(state) do
    started_at = DateTime.utc_now()

    {decayed, pruned, unchanged, errors} =
      case Graph.list_nodes(%{}) do
        {:ok, nodes} when is_list(nodes) ->
          Enum.reduce(nodes, {0, 0, 0, 0}, fn node, {d, p, u, e} ->
            case process_node(node, state.decay_rate, state.prune_threshold) do
              :decayed -> {d + 1, p, u, e}
              :pruned -> {d, p + 1, u, e}
              :unchanged -> {d, p, u + 1, e}
              :error -> {d, p, u, e + 1}
            end
          end)

        {:error, reason} ->
          Logger.warning("Consolidator failed to fetch nodes: #{inspect(reason)}")
          {0, 0, 0, 1}

        other ->
          Logger.warning("Consolidator got unexpected list_nodes response: #{inspect(other)}")
          {0, 0, 0, 1}
      end

    duration_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

    :telemetry.execute(
      [:graphonomous, :consolidator, :cycle],
      %{
        decayed: decayed,
        pruned: pruned,
        unchanged: unchanged,
        errors: errors,
        duration_ms: duration_ms
      },
      %{
        cycle: state.cycle_count + 1,
        prune_threshold: state.prune_threshold,
        decay_rate: state.decay_rate,
        merge_similarity: state.merge_similarity
      }
    )

    Logger.info(
      "Consolidator cycle=#{state.cycle_count + 1} decayed=#{decayed} pruned=#{pruned} unchanged=#{unchanged} errors=#{errors} duration_ms=#{duration_ms}"
    )

    state
    |> Map.put(:cycle_count, state.cycle_count + 1)
    |> Map.put(:last_run_at, DateTime.utc_now())
    |> schedule_next()
  end

  defp process_node(node, decay_rate, prune_threshold) do
    node_id = Map.get(node, :id)
    old_conf = node |> Map.get(:confidence, 0.5) |> normalize_probability()
    new_conf = clamp(old_conf * (1.0 - decay_rate), 0.0, 1.0)

    cond do
      not is_binary(node_id) ->
        :error

      new_conf < prune_threshold ->
        case Graph.delete_node(node_id) do
          :ok ->
            :telemetry.execute(
              [:graphonomous, :node, :pruned],
              %{old_confidence: old_conf, new_confidence: new_conf},
              %{node_id: node_id, threshold: prune_threshold}
            )

            :pruned

          {:error, _reason} ->
            :error
        end

      abs(new_conf - old_conf) <= 1.0e-12 ->
        :unchanged

      true ->
        case Graph.update_node(node_id, %{confidence: new_conf}) do
          {:ok, _updated} ->
            :telemetry.execute(
              [:graphonomous, :node, :decayed],
              %{old_confidence: old_conf, new_confidence: new_conf, delta: new_conf - old_conf},
              %{node_id: node_id}
            )

            :decayed

          {:error, _reason} ->
            :error
        end
    end
  end

  ## Timer helpers

  defp schedule_next(state) do
    cancel_timer(state.timer_ref)
    ref = Process.send_after(self(), :tick, state.interval_ms)
    %{state | timer_ref: ref}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref, async: true, info: false)

  ## Normalization helpers

  defp normalize_interval(v) when is_integer(v), do: max(v, @min_interval_ms)
  defp normalize_interval(_), do: @default_interval_ms

  defp normalize_probability(v) when is_float(v), do: clamp(v, 0.0, 1.0)
  defp normalize_probability(v) when is_integer(v), do: normalize_probability(v * 1.0)

  defp normalize_probability(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> normalize_probability(f)
      :error -> 0.5
    end
  end

  defp normalize_probability(_), do: 0.5

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end
