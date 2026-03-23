defmodule Graphonomous.ModelTierIntegrationTest do
  use ExUnit.Case, async: false

  alias Graphonomous.{Attention, CostTracker, Deliberator, Topology}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_nodes()
    purge_goals()
    CostTracker.reset_daily()
    _ = Attention.deactivate()

    on_exit(fn ->
      _ = Attention.deactivate()
      CostTracker.reset_daily()
      purge_nodes()
      purge_goals()
    end)

    :ok
  end

  test "Deliberator with local_small tier uses single_pass on κ=2 SCC" do
    topology =
      Topology.analyze([
        {"a1", "b1"},
        {"a1", "b2"},
        {"a2", "b1"},
        {"a2", "b2"},
        {"b1", "a1"},
        {"b1", "a2"},
        {"b2", "a1"},
        {"b2", "a2"}
      ])

    assert topology.max_kappa == 2

    retrieval = [
      %{node_id: "a1", content: "A1 evidence", confidence: 0.9, score: 0.8},
      %{node_id: "a2", content: "A2 evidence", confidence: 0.9, score: 0.8},
      %{node_id: "b1", content: "B1 evidence", confidence: 0.9, score: 0.8},
      %{node_id: "b2", content: "B2 evidence", confidence: 0.9, score: 0.8}
    ]

    result =
      Deliberator.deliberate(topology, "Resolve the cyclic tension", retrieval,
        model_tier: :local_small,
        write_back: false,
        agent_fn: fn prompt ->
          assert getv(prompt, :mode) == :single_pass_deliberation
          %{content: "Single-pass conclusion", confidence: 0.9}
        end
      )

    assert is_map(result)
    assert result.iterations_used >= 1
    assert length(result.conclusions) >= 1
    assert Enum.all?(result.conclusions, &is_binary(getv(&1, :content)))
  end

  test "Deliberator with local_small tier skips κ=1 SCC below floor" do
    topology =
      Topology.analyze([
        {"x", "y"},
        {"y", "z"},
        {"z", "x"}
      ])

    assert topology.max_kappa == 1

    result =
      Deliberator.deliberate(topology, "Should this deliberate?", [],
        model_tier: :local_small,
        write_back: false,
        agent_fn: fn _ -> %{content: "unexpected", confidence: 0.9} end
      )

    assert result.conclusions == []
    assert result.iterations_used == 0
    assert result.converged == true
    assert String.contains?(result.topology_change.note, "below κ deliberation floor")
  end

  test "Deliberator with cloud_frontier tier uses multi_pass on κ=1 SCC" do
    topology =
      Topology.analyze([
        {"m", "n"},
        {"n", "o"},
        {"o", "m"}
      ])

    assert topology.max_kappa == 1

    result =
      Deliberator.deliberate(topology, "Deliberate this loop", [%{node_id: "m", content: "m"}],
        model_tier: :cloud_frontier,
        write_back: false,
        agent_fn: fn prompt ->
          # multi-pass path should produce focused or refinement prompts
          assert getv(prompt, :mode) in [:focused_partition_analysis, :reconcile_refinement]
          %{content: "Multi-pass conclusion", confidence: 0.82}
        end
      )

    assert length(result.conclusions) >= 1
    assert result.iterations_used >= 1
  end

  test "Retriever with local_small tier enriches κ=1 retrieval with topology_notes" do
    a =
      Graphonomous.store_node(%{
        content: "Pricing changes affect market share.",
        node_type: :semantic,
        confidence: 0.9,
        source: "model_tier_integration"
      })

    b =
      Graphonomous.store_node(%{
        content: "Market share influences revenue.",
        node_type: :semantic,
        confidence: 0.9,
        source: "model_tier_integration"
      })

    c =
      Graphonomous.store_node(%{
        content: "Revenue feedback influences pricing changes.",
        node_type: :semantic,
        confidence: 0.9,
        source: "model_tier_integration"
      })

    _ = Graphonomous.link_nodes(a.id, b.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_nodes(b.id, c.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_nodes(c.id, a.id, %{edge_type: :causal, weight: 1.0})

    retrieval =
      Graphonomous.retrieve_context(
        "pricing market share revenue feedback",
        model_tier: :local_small,
        auto_deliberate: false,
        similarity_limit: 10,
        final_limit: 10,
        expansion_hops: 2
      )

    assert retrieval.topology.max_kappa >= 1
    assert is_list(Map.get(retrieval, :topology_notes, []))
    assert length(Map.get(retrieval, :topology_notes, [])) >= 1
    refute Map.has_key?(retrieval, :deliberation)
  end

  test "Attention in demand mode does not schedule heartbeat timer" do
    Application.put_env(:graphonomous, :model_tier, :local_small)

    Application.put_env(:graphonomous, Graphonomous.Attention,
      enabled: true,
      trigger_mode: :demand,
      heartbeat_ms: :disabled,
      autonomy_level: :observe,
      propose_enabled: false,
      budget: %{
        max_items_per_cycle: 1,
        max_explore_calls: 1,
        max_deliberation_sccs: 1,
        max_action_dispatches: 1,
        total_timeout_ms: 30_000
      }
    )

    restart_attention!()

    status = Attention.status()
    assert getv(status, :trigger_mode) == :demand
    assert is_nil(getv(status, :next_heartbeat_in_ms))
  end

  test "Attention demand mode executes on on_demand_check call" do
    Application.put_env(:graphonomous, :model_tier, :local_small)

    Application.put_env(:graphonomous, Graphonomous.Attention,
      enabled: true,
      trigger_mode: :demand,
      heartbeat_ms: :disabled,
      autonomy_level: :observe,
      propose_enabled: false,
      budget: %{
        max_items_per_cycle: 1,
        max_explore_calls: 1,
        max_deliberation_sccs: 1,
        max_action_dispatches: 1,
        total_timeout_ms: 30_000
      }
    )

    restart_attention!()

    goal =
      Graphonomous.create_goal(%{
        title: "Investigate churn dynamics",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :normal
      })

    n1 =
      Graphonomous.store_node(%{
        content: "Churn rises after support delays.",
        node_type: :semantic,
        confidence: 0.8,
        source: "model_tier_integration"
      })

    n2 =
      Graphonomous.store_node(%{
        content: "Support delays increase with queue size.",
        node_type: :semantic,
        confidence: 0.8,
        source: "model_tier_integration"
      })

    _ = Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_nodes(n2.id, n1.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_goal_nodes(goal.id, [n1.id, n2.id])

    topology =
      Topology.analyze([
        {n1.id, n2.id},
        {n2.id, n1.id}
      ])

    assert {:ok, payload} = Attention.on_demand_check(topology, "churn feedback loop")
    assert getv(payload, :mode) == :demand
    assert getv(payload, :checked_items) >= 0
    assert is_list(getv(payload, :dispatches, []))
  end

  test "Attention in heartbeat mode fires timer and updates last_cycle_result" do
    Application.put_env(:graphonomous, :model_tier, :cloud_frontier)

    Application.put_env(:graphonomous, Graphonomous.Attention,
      enabled: true,
      trigger_mode: :heartbeat,
      heartbeat_ms: 1_000,
      autonomy_level: :observe,
      propose_enabled: true,
      budget: %{
        max_items_per_cycle: 1,
        max_explore_calls: 1,
        max_deliberation_sccs: 1,
        max_action_dispatches: 1,
        total_timeout_ms: 30_000
      }
    )

    _goal =
      Graphonomous.create_goal(%{
        title: "Heartbeat cycle goal",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :normal
      })

    restart_attention!()

    # Wait long enough for at least one heartbeat cycle.
    Process.sleep(1_300)

    status = Attention.status()
    assert getv(status, :trigger_mode) == :heartbeat
    assert is_map(getv(status, :last_cycle_result))
  end

  test "CostTracker records events, summarizes session, and supports budget checks" do
    CostTracker.reset_daily()

    :ok =
      CostTracker.record(%{
        operation: :retrieval,
        tier: :local_small,
        tokens_in: 150,
        tokens_out: 80,
        inference_ms: 120.5,
        timestamp: DateTime.utc_now()
      })

    :ok =
      CostTracker.record(%{
        operation: :deliberation,
        tier: :cloud_frontier,
        tokens_in: 2_400,
        tokens_out: 1_200,
        inference_ms: 1_500.0,
        timestamp: DateTime.utc_now()
      })

    summary = CostTracker.session_summary()
    assert summary.total_calls == 2
    assert summary.total_tokens == 3_830
    assert summary.total_inference_ms > 0.0
    assert is_map(summary.by_operation)
    assert is_float(summary.estimated_cost_usd)

    avg = CostTracker.avg_deliberation_cost()
    assert avg.avg_tokens > 0.0
    assert avg.avg_inference_ms > 0.0

    Application.put_env(:graphonomous, Graphonomous.CostTracker, daily_cost_cap_usd: 0.000001)
    assert CostTracker.budget_exceeded?() == true
  end

  test "explicit deliberator opts override tier defaults" do
    topology =
      Topology.analyze([
        {"p", "q"},
        {"q", "r"},
        {"r", "p"}
      ])

    # local_small default would skip κ=1; override floor to force deliberation.
    result =
      Deliberator.deliberate(topology, "Override defaults", [%{node_id: "p", content: "p"}],
        model_tier: :local_small,
        write_back: false,
        budget: %{
          strategy: :multi_pass,
          kappa_deliberation_floor: 1,
          max_iterations: 2,
          confidence_threshold: 0.55
        },
        agent_fn: fn _ -> %{content: "Override conclusion", confidence: 0.8} end
      )

    assert length(result.conclusions) >= 1
    assert result.iterations_used >= 1
  end

  defp restart_attention! do
    case Process.whereis(Graphonomous.Attention) do
      nil ->
        :ok

      _pid ->
        _ = Supervisor.terminate_child(Graphonomous.Supervisor, Graphonomous.Attention)
        _ = Supervisor.restart_child(Graphonomous.Supervisor, Graphonomous.Attention)
        :ok
    end
  end

  defp purge_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        Enum.each(nodes, fn node ->
          _ = Graphonomous.delete_node(node.id)
        end)

      _ ->
        :ok
    end
  end

  defp purge_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: 10_000}) do
      goals when is_list(goals) ->
        Enum.each(goals, fn goal ->
          _ = Graphonomous.delete_goal(goal.id)
        end)

      _ ->
        :ok
    end
  end

  defp getv(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
