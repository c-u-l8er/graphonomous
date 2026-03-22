defmodule Graphonomous.TopologyPhase0Test do
  use ExUnit.Case, async: true

  alias Graphonomous.Topology

  test "empty adjacency → κ=0, routing=:fast" do
    result = Topology.analyze(%{})
    assert result.max_kappa == 0
    assert result.routing == :fast
    assert result.sccs == []
  end

  test "linear chain A→B→C → κ=0, routing=:fast" do
    adj = %{
      "a" => MapSet.new(["b"]),
      "b" => MapSet.new(["c"]),
      "c" => MapSet.new()
    }

    result = Topology.analyze(adj)
    assert result.max_kappa == 0
    assert result.routing == :fast
  end

  test "simple cycle A→B→C→A → κ=1, routing=:deliberate" do
    adj = %{
      "a" => MapSet.new(["b"]),
      "b" => MapSet.new(["c"]),
      "c" => MapSet.new(["a"])
    }

    result = Topology.analyze(adj)
    assert result.max_kappa == 1
    assert result.routing == :deliberate
    assert length(result.sccs) == 1
    assert hd(result.sccs).kappa == 1
  end

  test "single node → κ=0" do
    adj = %{"a" => MapSet.new()}
    result = Topology.analyze(adj)
    assert result.max_kappa == 0
  end

  test "self-loop excluded from adjacency" do
    edges = [%{source_id: "a", target_id: "a", edge_type: :causal}]
    adj = Topology.build_adjacency(["a"], edges)
    assert adj == %{"a" => MapSet.new()}
  end

  test "business example: 5-node cycle → κ=1" do
    adj = %{
      "market-share" => MapSet.new(["revenue"]),
      "revenue" => MapSet.new(["r-and-d"]),
      "r-and-d" => MapSet.new(["product-quality"]),
      "product-quality" => MapSet.new(["market-share"]),
      "customer-retention" => MapSet.new(["product-quality"])
    }

    result = Topology.analyze(adj)
    assert result.max_kappa >= 1
    assert result.routing == :deliberate
  end

  test "mixed DAG + cycle → dag_nodes separated from SCC" do
    adj = %{
      "a" => MapSet.new(["b"]),
      "b" => MapSet.new(["c"]),
      "c" => MapSet.new(["a"]),
      "d" => MapSet.new(["a"]),
      "e" => MapSet.new()
    }

    result = Topology.analyze(adj)
    assert result.scc_count == 1
    dag_ids = result.dag_nodes
    assert "d" in dag_ids or "e" in dag_ids
  end

  test "K2,2 complete bipartite (both directions) → κ=2" do
    adj = %{
      "a1" => MapSet.new(["b1", "b2"]),
      "a2" => MapSet.new(["b1", "b2"]),
      "b1" => MapSet.new(["a1", "a2"]),
      "b2" => MapSet.new(["a1", "a2"])
    }

    result = Topology.analyze(adj)
    assert result.max_kappa == 2
  end

  test "deliberation_budget scales with kappa" do
    assert Topology.deliberation_budget(0) == %{
             max_iterations: 1,
             agent_count: 0,
             timeout_multiplier: 1.0,
             confidence_threshold: 0.7
           }

    assert Topology.deliberation_budget(1) == %{
             max_iterations: 2,
             agent_count: 1,
             timeout_multiplier: 1.5,
             confidence_threshold: 0.75
           }

    assert Topology.deliberation_budget(2) == %{
             max_iterations: 3,
             agent_count: 2,
             timeout_multiplier: 2.0,
             confidence_threshold: 0.8
           }
  end

  test "canonical schema field names" do
    adj = %{"a" => MapSet.new(["b"]), "b" => MapSet.new(["a"])}
    result = Topology.analyze(adj)

    assert Map.has_key?(result, :sccs)
    assert Map.has_key?(result, :dag_nodes)
    assert Map.has_key?(result, :routing)
    assert Map.has_key?(result, :max_kappa)
    assert Map.has_key?(result, :scc_count)

    scc = hd(result.sccs)
    assert Map.has_key?(scc, :id)
    assert Map.has_key?(scc, :nodes)
    assert Map.has_key?(scc, :kappa)
    assert Map.has_key?(scc, :approximate)
    assert Map.has_key?(scc, :fault_line_edges)
    assert Map.has_key?(scc, :routing)
    assert Map.has_key?(scc, :deliberation_budget)
  end
end
