defmodule Graphonomous.Attention do
  @moduledoc """
  Proactive attention engine.

  Periodically surveys active goals, evaluates epistemic coverage and κ-topology,
  triages what needs attention, and dispatches bounded actions according to
  autonomy level.

  Autonomy levels:
    - `:observe` — survey only, no execution
    - `:advise`  — propose actions, no execution
    - `:act`     — execute within configured budgets
  """

  use GenServer

  alias Graphonomous.{Coverage, Deliberator, GoalGraph, ModelTier, Store, Topology}

  @type autonomy_level :: :observe | :advise | :act
  @type dispatch_mode :: :explore | :focus | :act | :escalate | :propose | :idle

  @type attention_item :: %{
          goal_id: binary() | nil,
          goal_title: binary() | nil,
          region_node_ids: [binary()],
          coverage: map(),
          topology: map(),
          urgency: float(),
          gap: float(),
          surprise: float(),
          friction: non_neg_integer(),
          attention_score: float(),
          dispatch_mode: dispatch_mode()
        }

  @type attention_cycle_result :: %{
          cycle_id: binary(),
          timestamp: DateTime.t(),
          items_surveyed: non_neg_integer(),
          items_dispatched: non_neg_integer(),
          dispatches: [
            %{
              item: attention_item(),
              mode: dispatch_mode(),
              result: :ok | :escalated | :deferred | {:error, term()},
              duration_ms: float()
            }
          ],
          next_heartbeat_ms: non_neg_integer()
        }

  @default_heartbeat_ms 300_000
  @default_autonomy :observe
  @default_escalation_cooldown_ms 300_000
  @cache_table :graphonomous_attention_cache
  @cache_ttl_ms 30_000

  @default_budget %{
    max_items_per_cycle: 3,
    max_explore_calls: 5,
    max_deliberation_sccs: 2,
    max_action_dispatches: 1,
    total_timeout_ms: 60_000
  }

  @type state :: %{
          active: boolean(),
          autonomy_level: autonomy_level(),
          heartbeat_ms: non_neg_integer(),
          budget: map(),
          trigger_mode: :heartbeat | :demand,
          propose_enabled: boolean(),
          model_tier: ModelTier.model_tier(),
          timer_ref: reference() | nil,
          next_heartbeat_at: DateTime.t() | nil,
          last_cycle_result: attention_cycle_result() | nil,
          last_attention_items: [attention_item()],
          escalation_cooldown_ms: non_neg_integer(),
          last_escalated_at: %{optional(binary()) => DateTime.t()}
        }

  # -- Client API --------------------------------------------------------------

  @doc "Start the attention engine (usually called by supervisor)."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Activate the engine."
  @spec activate(autonomy_level()) :: :ok
  def activate(level \\ :observe) do
    GenServer.call(__MODULE__, {:activate, level})
  end

  @doc "Deactivate the engine (stops heartbeat, keeps process alive)."
  @spec deactivate() :: :ok
  def deactivate do
    GenServer.call(__MODULE__, :deactivate)
  end

  @doc "Run one attention cycle immediately."
  @spec run_cycle(keyword()) :: {:ok, attention_cycle_result()}
  def run_cycle(opts \\ []) do
    GenServer.call(__MODULE__, {:run_cycle, opts}, 65_000)
  end

  @doc "Get the current attention map without dispatching."
  @spec survey() :: {:ok, [attention_item()]}
  def survey do
    GenServer.call(__MODULE__, :survey, 30_000)
  end

  @doc "Get engine state for observability."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Notify the attention engine that the graph has been mutated.

  Bumps the cache generation counter so the next survey will recompute
  instead of returning stale cached results. This is a non-blocking cast.

  Called automatically by the Graphonomous facade on store_node, store_edge,
  delete_node, and via telemetry handlers on learn_from_outcome and consolidation.
  """
  @spec notify_graph_mutation() :: :ok
  def notify_graph_mutation do
    if GenServer.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :graph_mutated)
    end

    :ok
  end

  @doc """
  Demand-triggered attention check for constrained tiers.
  Performs a lightweight, query-scoped attention pass.
  """
  @spec on_demand_check(map(), binary()) :: {:ok, map()}
  def on_demand_check(topology, query) when is_map(topology) and is_binary(query) do
    GenServer.call(__MODULE__, {:on_demand_check, topology, query}, 30_000)
  end

  # -- GenServer ---------------------------------------------------------------

  @impl true
  def init(opts) do
    app_cfg = Application.get_env(:graphonomous, __MODULE__, [])
    cfg = Keyword.merge(app_cfg, opts)

    tier =
      :graphonomous
      |> Application.get_env(:model_tier, :local_small)
      |> ModelTier.normalize_tier()

    tier_attention = ModelTier.attention_config(tier)

    trigger_mode =
      cfg
      |> Keyword.get(:trigger_mode, Map.get(tier_attention, :trigger_mode, :heartbeat))
      |> normalize_trigger_mode()

    heartbeat_cfg =
      Keyword.get(cfg, :heartbeat_ms, Map.get(tier_attention, :heartbeat_ms, 300_000))

    heartbeat_ms =
      if heartbeat_cfg == :disabled do
        :disabled
      else
        normalize_ms(heartbeat_cfg)
      end

    budget =
      tier_attention
      |> Map.take([
        :max_items_per_cycle,
        :max_explore_calls,
        :max_deliberation_sccs,
        :max_action_dispatches,
        :total_timeout_ms
      ])
      |> merge_budget(Keyword.get(cfg, :budget, %{}))

    enabled = cfg |> Keyword.get(:enabled, false) |> to_bool(false)

    autonomy_level =
      cfg
      |> Keyword.get(
        :autonomy_level,
        Map.get(tier_attention, :default_autonomy, @default_autonomy)
      )
      |> normalize_autonomy_level()

    escalation_cooldown_ms =
      cfg
      |> Keyword.get(:escalation_cooldown_ms, @default_escalation_cooldown_ms)
      |> normalize_ms()

    propose_enabled =
      cfg
      |> Keyword.get(:propose_enabled, Map.get(tier_attention, :propose_enabled, false))
      |> to_bool(false)

    # ETS cache for amortized O(1) survey on stable graphs
    init_cache_table()
    attach_mutation_telemetry()

    state = %{
      active: enabled and trigger_mode == :heartbeat and heartbeat_ms != :disabled,
      autonomy_level: autonomy_level,
      heartbeat_ms: heartbeat_ms,
      budget: budget,
      trigger_mode: trigger_mode,
      propose_enabled: propose_enabled,
      model_tier: tier,
      timer_ref: nil,
      next_heartbeat_at: nil,
      last_cycle_result: nil,
      last_attention_items: [],
      escalation_cooldown_ms: escalation_cooldown_ms,
      last_escalated_at: %{},
      cache_generation: 0
    }

    {:ok, maybe_schedule_heartbeat(state)}
  end

  @impl true
  def handle_call({:activate, level}, _from, state) do
    level = normalize_autonomy_level(level)

    state =
      state
      |> Map.put(:active, true)
      |> Map.put(:autonomy_level, level)
      |> maybe_schedule_heartbeat()

    {:reply, :ok, state}
  end

  def handle_call(:deactivate, _from, state) do
    state = cancel_heartbeat(%{state | active: false})
    {:reply, :ok, state}
  end

  def handle_call(:survey, _from, state) do
    {items, state} = cached_or_fresh_survey(state)
    {:reply, {:ok, items}, %{state | last_attention_items: items}}
  end

  def handle_call({:on_demand_check, topology, query}, _from, state) do
    if state.trigger_mode == :demand do
      items = partial_survey(Map.get(topology, :sccs, []), query)

      {dispatches, new_state} =
        dispatch(items, state.budget, state.autonomy_level, state)

      payload = %{
        status: :ok,
        mode: :demand,
        checked_items: length(items),
        dispatched_items: Enum.count(dispatches, &dispatch_successful?/1),
        dispatches: dispatches
      }

      {:reply, {:ok, payload}, %{new_state | last_attention_items: items}}
    else
      {:reply, {:ok, %{status: :ignored, reason: :not_in_demand_mode}}, state}
    end
  end

  def handle_call(:status, _from, state) do
    next_in_ms =
      case state.next_heartbeat_at do
        %DateTime{} = dt -> max(DateTime.diff(dt, DateTime.utc_now(), :millisecond), 0)
        _ -> nil
      end

    payload = %{
      active: state.active,
      autonomy_level: state.autonomy_level,
      heartbeat_ms: state.heartbeat_ms,
      trigger_mode: state.trigger_mode,
      propose_enabled: state.propose_enabled,
      model_tier: state.model_tier,
      next_heartbeat_in_ms: next_in_ms,
      budget: state.budget,
      last_cycle_result: serialize_term(state.last_cycle_result),
      last_attention_count: length(state.last_attention_items)
    }

    {:reply, payload, state}
  end

  def handle_call({:run_cycle, opts}, _from, state) do
    override = opts |> Keyword.get(:autonomy_override) |> normalize_autonomy_override()
    timeout_ms = get_in(state, [:budget, :total_timeout_ms]) || @default_budget.total_timeout_ms

    task =
      Task.async(fn ->
        run_cycle_once(state, override)
      end)

    reply =
      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, result, updated_state}} ->
          {{:ok, result}, updated_state}

        nil ->
          timed_out = timeout_cycle_result(state.heartbeat_ms)
          {{:ok, timed_out}, %{state | last_cycle_result: timed_out}}

        {:ok, {:error, reason}} ->
          {{:ok, error_cycle_result(reason, state.heartbeat_ms)}, state}
      end

    {response, new_state} = reply
    {:reply, response, new_state}
  end

  @impl true
  def handle_cast(:graph_mutated, state) do
    new_gen = state.cache_generation + 1
    {:noreply, %{state | cache_generation: new_gen}}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    state =
      if state.active and state.trigger_mode == :heartbeat and state.heartbeat_ms != :disabled do
        case run_cycle_once(state, nil) do
          {:ok, _result, updated_state} -> updated_state
          _ -> state
        end
      else
        state
      end

    {:noreply, maybe_schedule_heartbeat(state)}
  end

  # -- Core Cycle --------------------------------------------------------------

  defp run_cycle_once(state, autonomy_override) do
    autonomy_level = autonomy_override || state.autonomy_level
    cycle_id = "attn_#{System.unique_integer([:positive, :monotonic])}"
    timestamp = DateTime.utc_now()

    items = build_attention_map()
    _ = emit_cycle_start(length(items), autonomy_level)

    {dispatches, state_after_dispatch} = dispatch(items, state.budget, autonomy_level, state)

    result = %{
      cycle_id: cycle_id,
      timestamp: timestamp,
      items_surveyed: length(items),
      items_dispatched: Enum.count(dispatches, &dispatch_successful?/1),
      dispatches: dispatches,
      next_heartbeat_ms: state.heartbeat_ms
    }

    _ = emit_cycle_complete(result)

    {:ok, result,
     %{
       state_after_dispatch
       | last_cycle_result: result,
         last_attention_items: items
     }}
  rescue
    error ->
      {:error, {:cycle_failed, error}}
  end

  # -- Survey + Triage ---------------------------------------------------------

  defp build_attention_map do
    items =
      survey_goals()
      |> triage()

    # P1: Check memory pressure and inject warning if near budget
    case check_memory_pressure() do
      nil -> items
      pressure_item -> [pressure_item | items]
    end
  end

  # P1: Memory pressure detection — warn when approaching forgetting budget
  defp check_memory_pressure do
    config = Graphonomous.Forgetter.get_config()
    count = Store.count_active_nodes()

    cond do
      count > config.max_nodes ->
        %{
          goal_id: nil,
          goal_title: "Memory pressure: over budget",
          region_node_ids: [],
          coverage: %{},
          topology: %{},
          urgency: 0.9,
          gap: 1.0,
          surprise: 0.0,
          friction: 0,
          attention_score: 0.95,
          dispatch_mode: :escalate,
          attention_rationale:
            "Node count #{count} exceeds max_nodes #{config.max_nodes}. " <>
              "Run forget_by_policy to free memory.",
          coverage_decision: "escalate",
          coverage_rationale: ["memory_pressure: count=#{count} max=#{config.max_nodes}"],
          max_kappa: 0,
          routing: "fast",
          decision_confidence: 0.9,
          coverage_score: 0.0
        }

      count > config.max_nodes * 0.9 ->
        %{
          goal_id: nil,
          goal_title: "Memory pressure: approaching budget",
          region_node_ids: [],
          coverage: %{},
          topology: %{},
          urgency: 0.5,
          gap: 0.5,
          surprise: 0.0,
          friction: 0,
          attention_score: 0.4,
          dispatch_mode: :focus,
          attention_rationale:
            "Node count #{count} at #{Float.round(count / config.max_nodes * 100, 1)}% " <>
              "of max_nodes #{config.max_nodes}.",
          coverage_decision: "learn",
          coverage_rationale: [
            "memory_approaching: count=#{count} max=#{config.max_nodes}"
          ],
          max_kappa: 0,
          routing: "fast",
          decision_confidence: 0.5,
          coverage_score: 0.5
        }

      true ->
        nil
    end
  end

  defp partial_survey(sccs, query) do
    scoped_nodes =
      sccs
      |> Enum.flat_map(fn scc -> map_get(scc, :nodes, []) end)
      |> Enum.uniq()

    query_terms = tokenize(query)

    build_attention_map()
    |> Enum.filter(fn item ->
      region_overlap? =
        item.region_node_ids
        |> Enum.any?(&(&1 in scoped_nodes))

      goal_terms =
        [item.goal_title || ""]
        |> Enum.join(" ")
        |> tokenize()

      semantic_overlap? = overlap_ratio(query_terms, goal_terms) > 0.1
      region_overlap? or semantic_overlap?
    end)
    |> Enum.take(3)
  end

  # Two-phase attention: Phase 1 ranks all goals cheaply from metadata,
  # Phase 2 does expensive retrieval/coverage/topology only for top-K.
  # Layer 3: batch ANN — embed all K queries in one call, rank against shared node list.
  defp survey_goals do
    max_deep = get_max_items_per_cycle()

    case GoalGraph.list_goals(%{status: :active, include_abandoned: false, limit: 10_000}) do
      {:ok, goals} when is_list(goals) ->
        # Phase 1: cheap rank from goal metadata only (no retrieval calls)
        ranked =
          goals
          |> Enum.map(&quick_rank_goal/1)
          |> Enum.sort_by(fn {_goal, score} -> score end, :desc)

        top_k = Enum.take(ranked, max(max_deep, 3))

        # Layer 3: batch embed + single node list fetch for all K goals
        titles = Enum.map(top_k, fn {goal, _} -> Map.get(goal, :title, "") end)
        batch_results = batch_retrieve_similar(titles, 25)

        # Hoist shared outcome data once (not per-goal)
        all_outcomes = shared_list_outcomes(100)

        # Phase 2: deep eval only for top-K goals, using pre-batched retrieval
        Enum.map(top_k, fn {goal, _cheap_score} ->
          title = Map.get(goal, :title, "")
          retrieval_rows_raw = Map.get(batch_results, title, [])
          deep_eval_goal(goal, all_outcomes, retrieval_rows_raw)
        end)

      _ ->
        []
    end
  end

  # Phase 1: score a goal from metadata alone — O(1), no retrieval
  defp quick_rank_goal(goal) do
    priority_score = priority_weight_from_goal(goal)
    linked_count = goal |> Map.get(:linked_node_ids, []) |> length()
    linked_bonus = min(linked_count / 20.0, 0.3)

    staleness =
      case Map.get(goal, :updated_at) do
        %DateTime{} = dt ->
          hours_ago = DateTime.diff(DateTime.utc_now(), dt, :second) / 3600.0
          clamp01(hours_ago / 168.0)

        _ ->
          0.5
      end

    deadline = deadline_proximity_from_goal(goal)

    cheap_score = priority_score * 0.4 + staleness * 0.25 + deadline * 0.25 + linked_bonus * 0.1
    {goal, clamp01(cheap_score)}
  end

  defp priority_weight_from_goal(goal) do
    case Map.get(goal, :priority, :normal) do
      :critical -> 1.0
      :high -> 0.9
      :normal -> 0.6
      :low -> 0.3
      _ -> 0.6
    end
  end

  defp deadline_proximity_from_goal(goal) do
    case Map.get(goal, :due_at) do
      %DateTime{} = due_at ->
        ms_left = DateTime.diff(due_at, DateTime.utc_now(), :millisecond)
        days_left = ms_left / 86_400_000.0

        cond do
          days_left <= 0.0 -> 1.0
          days_left >= 7.0 -> 0.0
          true -> clamp01(1.0 - days_left / 7.0)
        end

      _ ->
        0.5
    end
  end

  # Phase 2: full coverage + topology for a single goal using pre-batched retrieval
  defp deep_eval_goal(goal, all_outcomes, retrieval_rows_raw) do
    retrieved_ids =
      retrieval_rows_raw
      |> Enum.map(fn row -> map_get(row, :node_id) end)
      |> Enum.filter(&is_binary/1)

    linked =
      goal
      |> Map.get(:linked_node_ids, [])
      |> normalize_string_list()

    node_ids = Enum.uniq(linked ++ retrieved_ids)

    retrieval_rows =
      Enum.map(retrieval_rows_raw, fn row ->
        %{
          node_id: map_get(row, :node_id),
          content: map_get(row, :content),
          score: to_float(map_get(row, :score)),
          confidence: to_float(map_get(row, :confidence)),
          similarity: to_float(map_get(row, :similarity))
        }
      end)

    # Use pre-fetched outcomes instead of per-goal Store.list_outcomes
    node_set = MapSet.new(node_ids)

    goal_outcomes =
      Enum.filter(all_outcomes, fn o ->
        o
        |> map_get(:causal_node_ids, [])
        |> normalize_string_list()
        |> Enum.any?(&MapSet.member?(node_set, &1))
      end)

    coverage =
      Coverage.recommend(
        %{
          retrieved_nodes: retrieval_rows,
          outcomes: goal_outcomes,
          contradictions: 0,
          graph_support: length(node_ids),
          known_unknowns: infer_known_unknowns(retrieval_rows),
          goal_criticality: priority_to_criticality(Map.get(goal, :priority))
        },
        []
      )
      |> enrich_coverage_gaps(goal, retrieval_rows)

    topology =
      if length(node_ids) > 1 do
        edges =
          case Store.list_edges_between(node_ids) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end

        node_ids
        |> Topology.build_adjacency(edges)
        |> Topology.analyze()
      else
        %{max_kappa: 0, scc_count: 0, routing: :fast, sccs: [], dag_nodes: node_ids}
      end

    surprise = compute_surprise_from_outcomes(all_outcomes, node_ids)

    build_attention_item(goal, node_ids, coverage, topology, surprise)
  end

  defp get_max_items_per_cycle do
    case GenServer.whereis(__MODULE__) do
      nil -> @default_budget.max_items_per_cycle
      _pid -> @default_budget.max_items_per_cycle
    end
  end

  # Layer 3: Batch ANN retrieval — one embed_many call + one node list fetch
  # for all K goal titles. Returns %{title => [retrieval_row, ...]}
  defp batch_retrieve_similar(titles, limit) do
    alias Graphonomous.{Embedder, Graph, HNSWIndex}

    # Filter out empty titles
    valid_titles = Enum.filter(titles, &(is_binary(&1) and String.trim(&1) != ""))

    if valid_titles == [] do
      Map.new(titles, fn t -> {t, []} end)
    else
      with {:ok, query_vecs} <- Embedder.embed_many(valid_titles) do
        pairs = Enum.zip(valid_titles, query_vecs)
        use_hnsw = HNSWIndex.available?()

        Map.new(pairs, fn {title, query_vec} ->
          ranked =
            if use_hnsw do
              hnsw_ranked(query_vec, limit)
            else
              brute_force_ranked(query_vec, limit)
            end

          {title, ranked}
        end)
      else
        _ ->
          Map.new(titles, fn t -> {t, []} end)
      end
    end
  rescue
    _ -> Map.new(titles, fn t -> {t, []} end)
  end

  defp hnsw_ranked(query_vec, limit) do
    alias Graphonomous.HNSWIndex

    case HNSWIndex.query(query_vec, limit * 3) do
      {:ok, results} ->
        results
        |> Enum.flat_map(fn {node_id, distance} ->
          case Store.get_node(node_id) do
            {:ok, node} ->
              similarity = max(1.0 - distance, 0.0)
              score = similarity * clamp01(to_float(node.confidence))

              [
                %{
                  node_id: node.id,
                  content: node.content,
                  node_type: node.node_type,
                  confidence: node.confidence,
                  similarity: similarity,
                  score: score
                }
              ]

            _ ->
              []
          end
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      _ ->
        brute_force_ranked(query_vec, limit)
    end
  end

  defp brute_force_ranked(query_vec, limit) do
    alias Graphonomous.Graph

    case Store.list_nodes(%{}) do
      {:ok, all_nodes} ->
        all_nodes
        |> Enum.map(fn node ->
          node_vec = Graph.decode_embedding_blob(node.embedding)
          similarity = Graph.cosine_similarity(query_vec, node_vec)
          score = similarity * clamp01(to_float(node.confidence))

          %{
            node_id: node.id,
            content: node.content,
            node_type: node.node_type,
            confidence: node.confidence,
            similarity: similarity,
            score: score
          }
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      _ ->
        []
    end
  end

  # Fetch outcomes once, share across all goal evaluations
  defp shared_list_outcomes(limit) do
    case Store.list_outcomes(limit) do
      {:ok, outcomes} when is_list(outcomes) -> outcomes
      _ -> []
    end
  end

  defp triage(attention_items) do
    attention_items
    |> Enum.map(fn item ->
      urgency = compute_urgency(item)
      gap = 1.0 - clamp01(map_get(item.coverage, :coverage_score, 0.0))
      surprise = clamp01(item.surprise)
      score = urgency * gap + surprise * 0.3
      mode = determine_dispatch_mode(item)

      %{
        item
        | urgency: urgency,
          gap: gap,
          attention_score: score,
          dispatch_mode: mode
      }
    end)
    |> Enum.sort_by(& &1.attention_score, :desc)
  end

  defp compute_urgency(item) do
    case item.goal_id do
      nil ->
        0.1

      _ ->
        deadline_factor = deadline_proximity(item)
        priority_factor = priority_weight(item)
        clamp01(deadline_factor * priority_factor)
    end
  end

  defp determine_dispatch_mode(item) do
    decision = map_get(item.coverage, :decision)
    coverage_score = to_float(map_get(item.coverage, :coverage_score, 0.0))
    routing = map_get(item.topology, :routing, :fast)

    cond do
      decision == :escalate ->
        :escalate

      decision == :learn and coverage_score < 0.45 ->
        :explore

      decision == :learn ->
        :focus

      routing == :deliberate ->
        :focus

      decision == :act ->
        :act

      is_nil(item.goal_id) and item.gap > 0.3 ->
        :propose

      true ->
        :idle
    end
  end

  # -- Dispatch ----------------------------------------------------------------

  defp dispatch(ranked_items, budget, autonomy_level, state) do
    ranked_items
    |> Enum.take(map_get(budget, :max_items_per_cycle, 3))
    |> Enum.reject(&(&1.dispatch_mode == :idle))
    |> Enum.reduce({[], init_budget_runtime(budget), state}, fn item, {acc, limits, st} ->
      {dispatch_result, limits, st} =
        case {item.dispatch_mode, autonomy_level} do
          {_mode, :observe} ->
            log_attention_item(item, :observed)

            {%{item: item, mode: item.dispatch_mode, result: :deferred, duration_ms: 0.0}, limits,
             st}

          {mode, :advise} ->
            proposal = build_proposal(item, mode)
            notify_proposal(proposal)
            {%{item: item, mode: mode, result: :deferred, duration_ms: 0.0}, limits, st}

          {:explore, :act} ->
            execute_explore(item, limits, st)

          {:focus, :act} ->
            execute_focus(item, limits, st)

          {:act, :act} ->
            execute_action(item, limits, st)

          {:escalate, _} ->
            execute_escalate(item, limits, st)

          {:propose, :act} ->
            execute_propose(item, limits, st)
        end

      _ = emit_dispatch_telemetry(dispatch_result)
      {[dispatch_result | acc], limits, st}
    end)
    |> then(fn {dispatches, _limits, st} -> {Enum.reverse(dispatches), st} end)
  end

  defp init_budget_runtime(budget) do
    %{
      explore_left: map_get(budget, :max_explore_calls, 5),
      focus_left: map_get(budget, :max_deliberation_sccs, 2),
      action_left: map_get(budget, :max_action_dispatches, 1)
    }
  end

  # -- Mode implementations ----------------------------------------------------

  defp execute_explore(item, limits, state) do
    cond do
      limits.explore_left <= 0 ->
        {%{item: item, mode: :explore, result: :deferred, duration_ms: 0.0}, limits, state}

      true ->
        {duration_us, result} =
          :timer.tc(fn ->
            gaps = map_get(item.coverage, :gaps, [])
            expanded = expand_internally(item.region_node_ids, gaps)
            researched = research_gaps(gaps, item.goal_title, limits.explore_left)
            store_exploration_results(expanded ++ researched, item.goal_id)
          end)

        dispatch =
          %{
            item: item,
            mode: :explore,
            result: result_to_dispatch_result(result),
            duration_ms: duration_us / 1000.0
          }

        {dispatch, %{limits | explore_left: max(limits.explore_left - 1, 0)}, state}
    end
  end

  defp execute_focus(item, limits, state) do
    cond do
      limits.focus_left <= 0 ->
        {%{item: item, mode: :focus, result: :deferred, duration_ms: 0.0}, limits, state}

      true ->
        query = item.goal_title || "Analyze this knowledge region"

        retrieval =
          safe_retrieve_context(query,
            limit: 50,
            similarity_limit: 50,
            final_limit: 50,
            expansion_hops: 1
          )

        {duration_us, deliberation_result} =
          :timer.tc(fn ->
            Deliberator.deliberate(item.topology, query, Map.get(retrieval, :results, []),
              agent_fn: &default_agent_fn/1,
              write_back: true
            )
          end)

        dispatch_result =
          case deliberation_result do
            %{converged: true} = result ->
              _ = learn_from_deliberation(item, result)
              :ok

            %{converged: false} ->
              :escalated

            _ ->
              {:error, :unexpected_deliberation_result}
          end

        dispatch =
          %{
            item: item,
            mode: :focus,
            result: dispatch_result,
            duration_ms: duration_us / 1000.0
          }

        {dispatch, %{limits | focus_left: max(limits.focus_left - 1, 0)}, state}
    end
  end

  defp execute_action(item, limits, state) do
    cond do
      limits.action_left <= 0 ->
        {%{item: item, mode: :act, result: :deferred, duration_ms: 0.0}, limits, state}

      true ->
        {duration_us, result} =
          :timer.tc(fn ->
            action = select_action(item)
            execute_via_opensentience(action, item.goal_id)
          end)

        dispatch = %{item: item, mode: :act, result: result, duration_ms: duration_us / 1000.0}
        {dispatch, %{limits | action_left: max(limits.action_left - 1, 0)}, state}
    end
  end

  defp execute_escalate(item, limits, state) do
    goal_id = item.goal_id || "global"

    should_escalate? =
      case Map.get(state.last_escalated_at, goal_id) do
        nil ->
          true

        %DateTime{} = last ->
          DateTime.diff(DateTime.utc_now(), last, :millisecond) >= state.escalation_cooldown_ms
      end

    if should_escalate? do
      log_attention_item(item, :escalated)

      updated_state =
        put_in(state.last_escalated_at[goal_id], DateTime.utc_now())

      {%{item: item, mode: :escalate, result: :escalated, duration_ms: 0.0}, limits,
       updated_state}
    else
      {%{item: item, mode: :escalate, result: :deferred, duration_ms: 0.0}, limits, state}
    end
  end

  defp execute_propose(item, limits, state) do
    gaps = map_get(item.coverage, :gaps, [])

    existing_goals =
      case GoalGraph.list_goals(%{include_abandoned: false, limit: 10_000}) do
        {:ok, goals} when is_list(goals) -> goals
        _ -> []
      end

    anchor_goals =
      Enum.filter(existing_goals, fn g ->
        source_type = map_get(g, :source_type, :user)
        source_type in [:user, :system]
      end)

    coherent? = coherent_with_existing?(gaps, anchor_goals)

    if state.propose_enabled and coherent? do
      goal_attrs = %{
        title: synthesize_goal_title(gaps),
        description: synthesize_goal_description(gaps, item),
        status: :proposed,
        source_type: :inferred,
        timescale: infer_timescale(gaps),
        priority: infer_priority(item.attention_score),
        linked_node_ids: item.region_node_ids,
        success_criteria: %{
          coverage_threshold: 0.72,
          target_node_ids: item.region_node_ids
        },
        metadata: %{
          generated_by: :attention_engine,
          coverage_at_proposal: map_get(item.coverage, :coverage_score, 0.0),
          kappa_at_proposal: map_get(item.topology, :max_kappa, 0),
          gaps: gaps
        }
      }

      result =
        case GoalGraph.create_goal(goal_attrs) do
          {:ok, goal} ->
            _ =
              :telemetry.execute(
                [:graphonomous, :attention, :goal_proposed],
                %{},
                %{
                  goal_id: goal.id,
                  coverage_at_proposal: map_get(item.coverage, :coverage_score, 0.0),
                  kappa_at_proposal: map_get(item.topology, :max_kappa, 0)
                }
              )

            :ok

          {:error, reason} ->
            {:error, reason}
        end

      {%{item: item, mode: :propose, result: result_to_dispatch_result(result), duration_ms: 0.0},
       limits, state}
    else
      {%{item: item, mode: :propose, result: :deferred, duration_ms: 0.0}, limits, state}
    end
  end

  # -- Exploration internals ---------------------------------------------------

  defp expand_internally(region_node_ids, _gaps) do
    region_set = MapSet.new(region_node_ids)

    region_node_ids
    |> Enum.flat_map(fn node_id ->
      case Graphonomous.query_graph(%{operation: :get_edges, node_id: node_id}) do
        edges when is_list(edges) ->
          Enum.map(edges, fn e ->
            neighbor =
              if map_get(e, :source_id) == node_id,
                do: map_get(e, :target_id),
                else: map_get(e, :source_id)

            %{source_node_id: node_id, neighbor_id: neighbor}
          end)

        _ ->
          []
      end
    end)
    |> Enum.filter(fn row ->
      is_binary(row.neighbor_id) and not MapSet.member?(region_set, row.neighbor_id)
    end)
    |> Enum.uniq_by(& &1.neighbor_id)
    |> Enum.take(12)
  end

  defp research_gaps(gaps, goal_title, max_calls) do
    gaps
    |> Enum.take(max_calls)
    |> Enum.map(fn gap ->
      %{
        content:
          "Exploration note for '#{goal_title}': investigate gap '#{gap}' and collect grounded evidence.",
        node_type: :semantic,
        confidence: 0.55,
        source: "attention:explore",
        metadata: %{
          kind: "coverage_gap_exploration",
          gap: gap,
          generated_at: DateTime.to_iso8601(DateTime.utc_now())
        }
      }
    end)
  end

  defp store_exploration_results(rows, goal_id) when is_list(rows) do
    stored_ids =
      rows
      |> Enum.map(fn row ->
        attrs =
          cond do
            is_map(row) and Map.has_key?(row, :content) ->
              row

            is_map(row) and is_binary(Map.get(row, :neighbor_id)) ->
              %{
                content: "Discovered adjacent node #{row.neighbor_id} from #{row.source_node_id}",
                node_type: :episodic,
                confidence: 0.5,
                source: "attention:expand",
                metadata: %{
                  kind: "neighbor_discovery",
                  source_node_id: row.source_node_id,
                  neighbor_id: row.neighbor_id
                }
              }

            true ->
              nil
          end

        case attrs do
          nil ->
            nil

          map ->
            case Graphonomous.store_node(map) do
              %{id: id} when is_binary(id) ->
                if is_binary(goal_id) do
                  _ = GoalGraph.link_nodes(goal_id, [id])
                end

                id

              _ ->
                nil
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    if stored_ids == [], do: :deferred, else: :ok
  end

  # -- Deliberation/Action helpers --------------------------------------------

  defp learn_from_deliberation(item, result) do
    content =
      "Deliberation completed for goal '#{item.goal_title}'. converged=#{inspect(Map.get(result, :converged))}"

    _ =
      Graphonomous.store_node(%{
        content: content,
        node_type: :episodic,
        confidence: 0.7,
        source: "attention:focus",
        metadata: %{
          kind: "deliberation_summary",
          goal_id: item.goal_id,
          source_kappa: map_get(item.topology, :max_kappa, 0)
        }
      })

    :ok
  end

  defp select_action(item) do
    %{
      action_id: "action_#{System.unique_integer([:positive])}",
      goal_id: item.goal_id,
      title: item.goal_title,
      rationale:
        "Coverage indicates act path with score=#{Float.round(map_get(item.coverage, :coverage_score, 0.0), 3)}",
      context_node_ids: item.region_node_ids
    }
  end

  # Placeholder for OpenSentience integration.
  defp execute_via_opensentience(action, goal_id) do
    _ =
      Graphonomous.learn_from_outcome(%{
        action_id: action.action_id,
        status: :partial_success,
        confidence: 0.6,
        causal_node_ids: action.context_node_ids,
        evidence: %{
          summary: "Action selected by Attention engine (stub execution).",
          goal_id: goal_id
        }
      })

    :ok
  rescue
    _ -> :deferred
  end

  defp default_agent_fn(prompt) do
    mode = map_get(prompt, :mode, :focused_partition_analysis)
    query = map_get(prompt, :query, "")

    %{
      content: "Attention deliberation #{mode} synthesized for '#{query}'.",
      confidence: 0.7
    }
  end

  # -- Scoring helpers ---------------------------------------------------------

  defp build_attention_item(goal, node_ids, coverage, topology, surprise) do
    %{
      goal_id: map_get(goal, :id),
      goal_title: map_get(goal, :title),
      region_node_ids: node_ids,
      coverage: coverage,
      topology: topology,
      urgency: 0.0,
      gap: 0.0,
      surprise: clamp01(surprise),
      friction: as_non_neg_int(map_get(topology, :max_kappa, 0)),
      attention_score: 0.0,
      dispatch_mode: :idle,
      priority: map_get(goal, :priority, :normal),
      due_at: map_get(goal, :due_at, nil)
    }
  end

  defp deadline_proximity(item) do
    case Map.get(item, :due_at) do
      %DateTime{} = due_at ->
        ms_left = DateTime.diff(due_at, DateTime.utc_now(), :millisecond)
        days_left = ms_left / 86_400_000.0

        cond do
          days_left <= 0.0 -> 1.0
          days_left >= 7.0 -> 0.0
          true -> clamp01(1.0 - days_left / 7.0)
        end

      _ ->
        0.5
    end
  end

  defp priority_weight(item) do
    case Map.get(item, :priority, :normal) do
      :critical -> 1.0
      :high -> 0.9
      :normal -> 0.6
      :low -> 0.3
      _ -> 0.6
    end
  end

  # Compute surprise from pre-fetched outcomes (no per-goal DB call)
  defp compute_surprise_from_outcomes(all_outcomes, node_ids) do
    node_set = MapSet.new(node_ids)

    related =
      Enum.filter(all_outcomes, fn outcome ->
        outcome
        |> map_get(:causal_node_ids, [])
        |> normalize_string_list()
        |> Enum.any?(&MapSet.member?(node_set, &1))
      end)

    if related == [] do
      0.0
    else
      related
      |> Enum.map(fn o ->
        status = map_get(o, :status, :partial_success)
        conf = to_float(map_get(o, :confidence, 0.5))

        case status do
          :failure -> 0.9 * conf
          :timeout -> 0.8 * conf
          :partial_success -> 0.5 * conf
          _ -> 0.2 * conf
        end
      end)
      |> avg_or(0.0)
      |> clamp01()
    end
  end

  defp infer_known_unknowns(retrieval_rows) do
    avg_score =
      retrieval_rows
      |> Enum.map(&to_float(map_get(&1, :score, 0.0)))
      |> avg_or(0.0)

    clamp01(1.0 - avg_score)
  end

  defp priority_to_criticality(priority) do
    case priority do
      :critical -> 1.0
      :high -> 0.8
      :normal -> 0.5
      :low -> 0.2
      _ -> 0.5
    end
  end

  defp enrich_coverage_gaps(coverage, goal, retrieval_rows) do
    rationale = map_get(coverage, :rationale, []) |> Enum.map(&to_string/1)

    default_gap =
      if retrieval_rows == [] do
        ["No retrieved context for active goal '#{map_get(goal, :title, "unknown")}'"]
      else
        []
      end

    Map.put(coverage, :gaps, Enum.uniq(rationale ++ default_gap))
  end

  # -- Proposal coherence ------------------------------------------------------

  defp coherent_with_existing?(gaps, goals) do
    gap_terms =
      gaps
      |> Enum.join(" ")
      |> tokenize()

    if gap_terms == [] do
      true
    else
      Enum.any?(goals, fn g ->
        goal_terms =
          [map_get(g, :title, ""), map_get(g, :description, "")]
          |> Enum.join(" ")
          |> tokenize()

        overlap_ratio(gap_terms, goal_terms) >= 0.15
      end)
    end
  end

  defp synthesize_goal_title(gaps) do
    head =
      gaps
      |> List.first()
      |> to_string()

    short = if String.trim(head) == "", do: "coverage gap", else: String.slice(head, 0, 64)
    "Investigate: #{short}"
  end

  defp synthesize_goal_description(gaps, item) do
    """
    Proposed by Attention Engine due to persistent coverage gap.

    Goal context:
    - source goal: #{item.goal_title || "none"}
    - attention_score: #{Float.round(item.attention_score, 3)}
    - coverage_score: #{Float.round(map_get(item.coverage, :coverage_score, 0.0), 3)}
    - kappa: #{map_get(item.topology, :max_kappa, 0)}

    Gaps:
    #{Enum.map_join(gaps, "\n", &("- " <> to_string(&1)))}
    """
    |> String.trim()
  end

  defp infer_timescale(gaps) do
    if length(gaps) >= 3, do: :medium_term, else: :short_term
  end

  defp infer_priority(attention_score) when is_number(attention_score) do
    cond do
      attention_score >= 0.8 -> :high
      attention_score >= 0.5 -> :normal
      true -> :low
    end
  end

  defp infer_priority(_), do: :normal

  # -- Heartbeat ---------------------------------------------------------------

  defp maybe_schedule_heartbeat(state) do
    state = cancel_heartbeat(state)

    if state.active and state.trigger_mode == :heartbeat and state.heartbeat_ms != :disabled do
      ref = Process.send_after(self(), :heartbeat, state.heartbeat_ms)

      %{
        state
        | timer_ref: ref,
          next_heartbeat_at: DateTime.add(DateTime.utc_now(), state.heartbeat_ms, :millisecond)
      }
    else
      %{state | timer_ref: nil, next_heartbeat_at: nil}
    end
  end

  defp cancel_heartbeat(%{timer_ref: ref} = state) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    %{state | timer_ref: nil, next_heartbeat_at: nil}
  end

  defp cancel_heartbeat(state), do: state

  # -- Telemetry ---------------------------------------------------------------

  defp emit_cycle_start(count, level) do
    :telemetry.execute(
      [:graphonomous, :attention, :cycle_start],
      %{items_surveyed: count},
      %{trigger: :heartbeat, autonomy: level}
    )
  end

  defp emit_dispatch_telemetry(dispatch) do
    item = dispatch.item

    :telemetry.execute(
      [:graphonomous, :attention, :dispatch],
      %{duration_ms: dispatch.duration_ms, attention_score: item.attention_score},
      %{
        mode: dispatch.mode,
        goal_id: item.goal_id,
        kappa: map_get(item.topology, :max_kappa, 0),
        coverage: map_get(item.coverage, :coverage_score, 0.0)
      }
    )
  end

  defp emit_cycle_complete(result) do
    modes =
      result.dispatches
      |> Enum.group_by(& &1.mode)
      |> Enum.map(fn {mode, rows} -> {mode, length(rows)} end)
      |> Map.new()

    :telemetry.execute(
      [:graphonomous, :attention, :cycle_complete],
      %{
        total_duration_ms:
          Enum.reduce(result.dispatches, 0.0, fn d, acc -> acc + d.duration_ms end),
        items_dispatched: result.items_dispatched
      },
      %{modes: modes}
    )
  end

  # -- Utility -----------------------------------------------------------------

  defp dispatch_successful?(%{result: :ok}), do: true
  defp dispatch_successful?(%{result: :escalated}), do: true
  defp dispatch_successful?(_), do: false

  defp build_proposal(item, mode) do
    %{
      goal_id: item.goal_id,
      goal_title: item.goal_title,
      mode: mode,
      attention_score: item.attention_score,
      rationale: map_get(item.coverage, :rationale, [])
    }
  end

  defp notify_proposal(_proposal), do: :ok
  defp log_attention_item(_item, _event), do: :ok

  defp safe_retrieve_context(query, opts) when is_binary(query) do
    if String.trim(query) == "" do
      %{results: []}
    else
      case Graphonomous.retrieve_context(query, opts) do
        %{} = map -> map
        _ -> %{results: []}
      end
    end
  rescue
    _ -> %{results: []}
  end

  defp merge_budget(base_budget, user_budget) when is_map(base_budget) and is_map(user_budget) do
    merged = Map.merge(base_budget, user_budget)

    %{
      max_items_per_cycle:
        merged
        |> map_get(:max_items_per_cycle, @default_budget.max_items_per_cycle)
        |> as_non_neg_int()
        |> max(1),
      max_explore_calls:
        merged
        |> map_get(:max_explore_calls, @default_budget.max_explore_calls)
        |> as_non_neg_int(),
      max_deliberation_sccs:
        merged
        |> map_get(:max_deliberation_sccs, @default_budget.max_deliberation_sccs)
        |> as_non_neg_int(),
      max_action_dispatches:
        merged
        |> map_get(:max_action_dispatches, @default_budget.max_action_dispatches)
        |> as_non_neg_int(),
      total_timeout_ms:
        merged
        |> map_get(:total_timeout_ms, @default_budget.total_timeout_ms)
        |> normalize_ms()
    }
  end

  defp timeout_cycle_result(next_ms) do
    %{
      cycle_id: "attn_timeout_#{System.unique_integer([:positive])}",
      timestamp: DateTime.utc_now(),
      items_surveyed: 0,
      items_dispatched: 0,
      dispatches: [],
      next_heartbeat_ms: next_ms
    }
  end

  defp error_cycle_result(reason, next_ms) do
    %{
      cycle_id: "attn_error_#{System.unique_integer([:positive])}",
      timestamp: DateTime.utc_now(),
      items_surveyed: 0,
      items_dispatched: 0,
      dispatches: [
        %{
          item: %{
            goal_id: nil,
            goal_title: nil,
            region_node_ids: [],
            coverage: %{},
            topology: %{},
            urgency: 0.0,
            gap: 0.0,
            surprise: 0.0,
            friction: 0,
            attention_score: 0.0,
            dispatch_mode: :idle
          },
          mode: :idle,
          result: {:error, reason},
          duration_ms: 0.0
        }
      ],
      next_heartbeat_ms: next_ms
    }
  end

  defp result_to_dispatch_result(:ok), do: :ok
  defp result_to_dispatch_result(:deferred), do: :deferred
  defp result_to_dispatch_result({:error, _} = err), do: err
  defp result_to_dispatch_result(other), do: {:error, other}

  defp normalize_autonomy_override(nil), do: nil
  defp normalize_autonomy_override(v), do: normalize_autonomy_level(v)

  defp normalize_autonomy_level(:observe), do: :observe
  defp normalize_autonomy_level(:advise), do: :advise
  defp normalize_autonomy_level(:act), do: :act

  defp normalize_autonomy_level(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "observe" -> :observe
      "advise" -> :advise
      "act" -> :act
      _ -> @default_autonomy
    end
  end

  defp normalize_autonomy_level(_), do: @default_autonomy

  defp normalize_trigger_mode(:heartbeat), do: :heartbeat
  defp normalize_trigger_mode(:demand), do: :demand

  defp normalize_trigger_mode(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "heartbeat" -> :heartbeat
      "demand" -> :demand
      _ -> :heartbeat
    end
  end

  defp normalize_trigger_mode(_), do: :heartbeat

  defp normalize_ms(v) when is_integer(v), do: max(v, 1_000)
  defp normalize_ms(v) when is_float(v), do: v |> trunc() |> normalize_ms()

  defp normalize_ms(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} -> normalize_ms(i)
      :error -> @default_heartbeat_ms
    end
  end

  defp normalize_ms(_), do: @default_heartbeat_ms

  defp to_bool(v, _default) when is_boolean(v), do: v

  defp to_bool(v, default) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "true" -> true
      "1" -> true
      "yes" -> true
      "on" -> true
      "false" -> false
      "0" -> false
      "no" -> false
      "off" -> false
      _ -> default
    end
  end

  defp to_bool(_, default), do: default

  defp tokenize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/u, " ")
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
  end

  defp tokenize(_), do: []

  defp overlap_ratio(a_terms, b_terms) do
    a = MapSet.new(a_terms)
    b = MapSet.new(b_terms)
    inter = MapSet.intersection(a, b) |> MapSet.size()
    denom = max(MapSet.size(a), 1)
    inter / denom
  end

  defp avg_or([], fallback), do: fallback
  defp avg_or(list, _fallback), do: Enum.sum(list) / max(length(list), 1)

  defp normalize_string_list(list) when is_list(list) do
    list
    |> Enum.map(fn
      v when is_binary(v) -> String.trim(v)
      v -> to_string(v)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_string_list(_), do: []

  defp as_non_neg_int(v) when is_integer(v) and v >= 0, do: v
  defp as_non_neg_int(v) when is_float(v) and v >= 0, do: trunc(v)

  defp as_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> 0
    end
  end

  defp as_non_neg_int(_), do: 0

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp clamp01(v), do: clamp(v, 0.0, 1.0)
  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default

  defp serialize_term(nil), do: nil
  defp serialize_term(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp serialize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {serialize_key(k), serialize_term(v)} end)
    |> Map.new()
  end

  defp serialize_term(list) when is_list(list), do: Enum.map(list, &serialize_term/1)
  defp serialize_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp serialize_term(other), do: other

  defp serialize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp serialize_key(k), do: k

  # -- ETS Cache ---------------------------------------------------------------

  defp init_cache_table do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  defp attach_mutation_telemetry do
    handler_id = "graphonomous_attention_cache_invalidation"

    # Detach first in case of process restart to avoid duplicate handler error
    _ = :telemetry.detach(handler_id)

    :telemetry.attach_many(
      handler_id,
      [
        [:graphonomous, :outcome, :processed],
        [:graphonomous, :consolidator, :complete],
        [:graphonomous, :consolidator, :stage_complete]
      ],
      fn _event, _measurements, _metadata, _config ->
        notify_graph_mutation()
      end,
      nil
    )
  end

  # Returns {items, updated_state} — either from cache or fresh computation
  defp cached_or_fresh_survey(state) do
    case read_survey_cache(state.cache_generation) do
      {:hit, items} ->
        {items, state}

      :miss ->
        items = build_attention_map()
        write_survey_cache(state.cache_generation, items)
        {items, state}
    end
  end

  defp read_survey_cache(current_generation) do
    case :ets.lookup(@cache_table, :survey_cache) do
      [{:survey_cache, gen, items, cached_at}]
      when gen == current_generation ->
        age_ms = System.monotonic_time(:millisecond) - cached_at

        if age_ms <= @cache_ttl_ms do
          {:hit, items}
        else
          :miss
        end

      _ ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp write_survey_cache(generation, items) do
    :ets.insert(
      @cache_table,
      {:survey_cache, generation, items, System.monotonic_time(:millisecond)}
    )
  rescue
    ArgumentError -> :ok
  end
end
