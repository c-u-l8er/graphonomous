defmodule Graphonomous.CostTracker do
  @moduledoc """
  ETS-backed inference cost tracker.

  Tracks per-call usage across operations and model tiers, emits telemetry, and
  supports daily budget checks for unattended autonomy.

  Cost behavior:
  - `:cloud_frontier` -> estimated monetary cost (USD)
  - local tiers        -> compute-time only (USD remains `nil`)
  """

  alias Graphonomous.ModelTier

  @type operation :: :deliberation | :exploration | :attention | :retrieval

  @type cost_entry :: %{
          operation: operation(),
          tier: ModelTier.model_tier(),
          tokens_in: non_neg_integer(),
          tokens_out: non_neg_integer(),
          inference_ms: float(),
          timestamp: DateTime.t()
        }

  @entries_table :graphonomous_cost_tracker_entries
  @meta_table :graphonomous_cost_tracker_meta
  @meta_day_key :current_day

  @default_daily_cost_cap_usd 10.0

  # Approximate cloud pricing per 1K tokens.
  # Keep these configurable if needed; these defaults are intentionally conservative.
  @cloud_price_per_1k_input 0.01
  @cloud_price_per_1k_output 0.03

  @doc """
  Record an inference cost event.

  Emits telemetry:
    [:graphonomous, :inference, :complete]
  """
  @spec record(cost_entry() | map()) :: :ok
  def record(entry) when is_map(entry) do
    ensure_tables!()
    maybe_rollover_daily!()

    normalized = normalize_entry(entry)
    id = System.unique_integer([:positive, :monotonic])
    true = :ets.insert(@entries_table, {id, normalized})

    :telemetry.execute(
      [:graphonomous, :inference, :complete],
      %{
        tokens_in: normalized.tokens_in,
        tokens_out: normalized.tokens_out,
        inference_ms: normalized.inference_ms
      },
      %{
        tier: normalized.tier,
        operation: normalized.operation
      }
    )

    :ok
  end

  @doc """
  Get cost totals for the current session (since last reset/rollover).
  """
  @spec session_summary() :: %{
          total_calls: non_neg_integer(),
          total_tokens: non_neg_integer(),
          total_inference_ms: float(),
          estimated_cost_usd: float() | nil,
          by_operation: map()
        }
  def session_summary do
    ensure_tables!()
    maybe_rollover_daily!()

    entries = all_entries()

    total_calls = length(entries)
    total_tokens = Enum.reduce(entries, 0, fn e, acc -> acc + e.tokens_in + e.tokens_out end)

    total_inference_ms =
      entries
      |> Enum.reduce(0.0, fn e, acc -> acc + e.inference_ms end)
      |> Float.round(3)

    by_operation = summarize_by_operation(entries)

    estimated_cost_usd =
      entries
      |> estimate_total_usd()
      |> maybe_nil_if_zero()

    %{
      total_calls: total_calls,
      total_tokens: total_tokens,
      total_inference_ms: total_inference_ms,
      estimated_cost_usd: estimated_cost_usd,
      by_operation: by_operation
    }
  end

  @doc """
  Get average cost of deliberation calls.
  """
  @spec avg_deliberation_cost() :: %{
          avg_tokens: float(),
          avg_inference_ms: float(),
          avg_cost_usd: float() | nil
        }
  def avg_deliberation_cost do
    ensure_tables!()
    maybe_rollover_daily!()

    entries =
      all_entries()
      |> Enum.filter(&(&1.operation == :deliberation))

    count = length(entries)

    if count == 0 do
      %{
        avg_tokens: 0.0,
        avg_inference_ms: 0.0,
        avg_cost_usd: nil
      }
    else
      avg_tokens =
        entries
        |> Enum.map(fn e -> e.tokens_in + e.tokens_out end)
        |> avg()

      avg_inference_ms =
        entries
        |> Enum.map(& &1.inference_ms)
        |> avg()

      avg_cost_usd =
        entries
        |> Enum.map(&estimate_entry_usd/1)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          values -> avg(values)
        end

      %{
        avg_tokens: Float.round(avg_tokens, 3),
        avg_inference_ms: Float.round(avg_inference_ms, 3),
        avg_cost_usd: avg_cost_usd && Float.round(avg_cost_usd, 6)
      }
    end
  end

  @doc """
  Returns true when estimated daily cloud cost exceeds configured cap.

  Config override:
    config :graphonomous, Graphonomous.CostTracker, daily_cost_cap_usd: 10.0
  """
  @spec budget_exceeded?() :: boolean()
  def budget_exceeded? do
    ensure_tables!()
    maybe_rollover_daily!()

    cap =
      :graphonomous
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:daily_cost_cap_usd, @default_daily_cost_cap_usd)
      |> to_float()
      |> max(0.0)

    case session_summary().estimated_cost_usd do
      nil -> false
      usd -> usd > cap
    end
  end

  @doc """
  Reset current day's counters and entries.
  """
  @spec reset_daily() :: :ok
  def reset_daily do
    ensure_tables!()
    :ets.delete_all_objects(@entries_table)
    :ets.insert(@meta_table, {@meta_day_key, Date.utc_today()})
    :ok
  end

  # -- Internal ----------------------------------------------------------------

  defp ensure_tables! do
    ensure_table(@entries_table, [:named_table, :set, :public, read_concurrency: true])
    ensure_table(@meta_table, [:named_table, :set, :public])
    ensure_day_initialized!()
    :ok
  end

  defp ensure_table(name, opts) do
    case :ets.whereis(name) do
      :undefined ->
        _ = :ets.new(name, opts)
        :ok

      _ ->
        :ok
    end
  end

  defp ensure_day_initialized! do
    case :ets.lookup(@meta_table, @meta_day_key) do
      [{@meta_day_key, %Date{}}] ->
        :ok

      _ ->
        :ets.insert(@meta_table, {@meta_day_key, Date.utc_today()})
        :ok
    end
  end

  defp maybe_rollover_daily! do
    today = Date.utc_today()

    case :ets.lookup(@meta_table, @meta_day_key) do
      [{@meta_day_key, ^today}] ->
        :ok

      _ ->
        :ets.delete_all_objects(@entries_table)
        :ets.insert(@meta_table, {@meta_day_key, today})
        :ok
    end
  end

  defp all_entries do
    @entries_table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, entry} -> entry end)
  end

  defp summarize_by_operation(entries) do
    entries
    |> Enum.group_by(& &1.operation)
    |> Enum.map(fn {op, rows} ->
      total_tokens = Enum.reduce(rows, 0, fn e, acc -> acc + e.tokens_in + e.tokens_out end)
      total_inference_ms = Enum.reduce(rows, 0.0, fn e, acc -> acc + e.inference_ms end)
      estimated_cost_usd = rows |> estimate_total_usd() |> maybe_nil_if_zero()

      {op,
       %{
         calls: length(rows),
         total_tokens: total_tokens,
         total_inference_ms: Float.round(total_inference_ms, 3),
         estimated_cost_usd: estimated_cost_usd
       }}
    end)
    |> Map.new()
  end

  defp estimate_total_usd(entries) do
    entries
    |> Enum.map(&estimate_entry_usd/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
    |> Kernel.*(1.0)
    |> Float.round(6)
  end

  defp estimate_entry_usd(%{tier: :cloud_frontier} = entry) do
    in_cost = entry.tokens_in / 1_000.0 * @cloud_price_per_1k_input
    out_cost = entry.tokens_out / 1_000.0 * @cloud_price_per_1k_output
    in_cost + out_cost
  end

  defp estimate_entry_usd(_), do: nil

  defp maybe_nil_if_zero(value) when is_number(value) do
    if value <= 0.0, do: nil, else: Float.round(value, 6)
  end

  defp normalize_entry(entry) do
    %{
      operation: normalize_operation(map_get(entry, :operation, :retrieval)),
      tier: entry |> map_get(:tier, ModelTier.current_tier()) |> ModelTier.normalize_tier(),
      tokens_in: entry |> map_get(:tokens_in, 0) |> to_non_neg_int(),
      tokens_out: entry |> map_get(:tokens_out, 0) |> to_non_neg_int(),
      inference_ms: entry |> map_get(:inference_ms, 0.0) |> to_float() |> max(0.0),
      timestamp:
        entry
        |> map_get(:timestamp, DateTime.utc_now())
        |> normalize_datetime(DateTime.utc_now())
    }
  end

  defp normalize_operation(:deliberation), do: :deliberation
  defp normalize_operation(:exploration), do: :exploration
  defp normalize_operation(:attention), do: :attention
  defp normalize_operation(:retrieval), do: :retrieval

  defp normalize_operation(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "deliberation" -> :deliberation
      "exploration" -> :exploration
      "attention" -> :attention
      "retrieval" -> :retrieval
      _ -> :retrieval
    end
  end

  defp normalize_operation(_), do: :retrieval

  defp normalize_datetime(%DateTime{} = dt, _fallback), do: dt

  defp normalize_datetime(value, fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> fallback
    end
  end

  defp normalize_datetime(_, fallback), do: fallback

  defp map_get(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default

  defp to_non_neg_int(v) when is_integer(v) and v >= 0, do: v
  defp to_non_neg_int(v) when is_float(v) and v >= 0, do: trunc(v)

  defp to_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> 0
    end
  end

  defp to_non_neg_int(_), do: 0

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp avg(list) when is_list(list) and list != [] do
    Enum.sum(list) / length(list)
  end
end
