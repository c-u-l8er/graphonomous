defmodule Graphonomous.AttentionTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_goals()
    purge_nodes()
    _ = Graphonomous.Attention.deactivate()

    on_exit(fn ->
      _ = Graphonomous.Attention.deactivate()
      purge_goals()
      purge_nodes()
    end)

    :ok
  end

  test "survey/0 returns attention items for active goals with coverage and topology" do
    goal =
      Graphonomous.create_goal(%{
        title: "Improve retention forecast quality",
        description: "Need better retention and churn assumptions",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :high
      })

    n1 =
      Graphonomous.store_node(%{
        content: "Retention has dropped 3% quarter-over-quarter.",
        node_type: :semantic,
        confidence: 0.72,
        source: "attention_test"
      })

    n2 =
      Graphonomous.store_node(%{
        content: "Churn spikes after pricing increases for SMB segment.",
        node_type: :semantic,
        confidence: 0.69,
        source: "attention_test"
      })

    _ = Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: :causal, weight: 0.8})
    _ = Graphonomous.link_goal_nodes(goal.id, [n1.id, n2.id])

    assert {:ok, items} = Graphonomous.Attention.survey()
    assert is_list(items)
    assert length(items) >= 1

    item =
      Enum.find(items, fn i ->
        getv(i, :goal_id) == goal.id
      end)

    assert is_map(item)
    assert getv(item, :goal_title) == goal.title
    assert is_list(getv(item, :region_node_ids))
    assert goal.id == getv(item, :goal_id)

    coverage = getv(item, :coverage)
    assert is_map(coverage)
    assert is_number(getv(coverage, :coverage_score))
    assert getv(coverage, :decision) in [:act, :learn, :escalate]

    topology = getv(item, :topology)
    assert is_map(topology)
    assert is_integer(getv(topology, :max_kappa))
    assert getv(topology, :routing) in [:fast, :deliberate]

    assert is_number(getv(item, :attention_score))
    assert getv(item, :dispatch_mode) in [:explore, :focus, :act, :escalate, :propose, :idle]
  end

  test "run_cycle/1 in :observe mode surveys and defers all dispatches" do
    goal =
      Graphonomous.create_goal(%{
        title: "Resolve product-quality feedback loop",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :high
      })

    a =
      Graphonomous.store_node(%{
        content: "Market share impacts revenue.",
        node_type: :semantic,
        confidence: 0.8,
        source: "attention_test"
      })

    b =
      Graphonomous.store_node(%{
        content: "Revenue controls R&D investment.",
        node_type: :semantic,
        confidence: 0.8,
        source: "attention_test"
      })

    c =
      Graphonomous.store_node(%{
        content: "R&D investment influences market share.",
        node_type: :semantic,
        confidence: 0.8,
        source: "attention_test"
      })

    _ = Graphonomous.link_nodes(a.id, b.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_nodes(b.id, c.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_nodes(c.id, a.id, %{edge_type: :causal, weight: 1.0})
    _ = Graphonomous.link_goal_nodes(goal.id, [a.id, b.id, c.id])

    assert :ok = Graphonomous.Attention.activate(:observe)
    assert {:ok, cycle} = Graphonomous.Attention.run_cycle()
    assert is_map(cycle)

    assert is_binary(getv(cycle, :cycle_id))
    assert is_integer(getv(cycle, :items_surveyed))
    assert is_integer(getv(cycle, :items_dispatched))

    dispatches = getv(cycle, :dispatches, [])
    assert is_list(dispatches)

    Enum.each(dispatches, fn d ->
      assert getv(d, :result) == :deferred
      assert getv(d, :mode) in [:explore, :focus, :act, :escalate, :propose, :idle]
      assert is_number(getv(d, :duration_ms))
    end)
  end

  test "lifecycle controls: activate/deactivate/status and manual run_cycle" do
    assert :ok = Graphonomous.Attention.deactivate()
    status0 = Graphonomous.Attention.status()
    assert getv(status0, :active) == false

    assert :ok = Graphonomous.Attention.activate(:advise)

    status1 = Graphonomous.Attention.status()
    assert getv(status1, :active) == true
    assert getv(status1, :autonomy_level) == :advise

    next_ms = getv(status1, :next_heartbeat_in_ms)

    if is_nil(next_ms) do
      # demand-trigger tiers may not schedule a heartbeat timer
      assert is_nil(next_ms)
    else
      assert is_integer(next_ms)
      assert next_ms >= 0
    end

    # Manual cycle should work regardless of heartbeat cadence
    assert {:ok, cycle} = Graphonomous.Attention.run_cycle(autonomy_override: :observe)
    assert is_map(cycle)
    assert is_binary(getv(cycle, :cycle_id))

    assert :ok = Graphonomous.Attention.deactivate()

    status2 = Graphonomous.Attention.status()
    assert getv(status2, :active) == false
    assert is_nil(getv(status2, :next_heartbeat_in_ms))
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
