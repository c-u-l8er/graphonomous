defmodule Graphonomous.TopologyTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Topology
  alias Graphonomous.Types.Edge

  test "empty graph -> κ = 0, routing = :fast" do
    result = Topology.analyze(%{})

    assert result.routing == :fast
    assert result.max_kappa == 0
    assert result.scc_count == 0
    assert result.sccs == []
    assert result.dag_nodes == []
  end

  test "linear chain A->B->C -> κ = 0, routing = :fast" do
    result = Topology.analyze([{"A", "B"}, {"B", "C"}])

    assert result.routing == :fast
    assert result.max_kappa == 0
    assert result.scc_count == 0
    assert result.sccs == []
    assert result.dag_nodes == ["A", "B", "C"]
  end

  test "simple cycle A->B->C->A -> κ = 1, routing = :deliberate" do
    result = Topology.analyze([{"A", "B"}, {"B", "C"}, {"C", "A"}])

    assert result.routing == :deliberate
    assert result.max_kappa == 1
    assert result.scc_count == 1

    [scc] = result.sccs
    assert scc.kappa == 1
    assert scc.approximate == false
    assert scc.routing == :deliberate
    assert Enum.sort(scc.nodes) == ["A", "B", "C"]
    assert is_list(scc.fault_line_edges)

    assert scc.deliberation_budget == %{
             max_iterations: 2,
             agent_count: 1,
             timeout_multiplier: 1.5,
             confidence_threshold: 0.75
           }
  end

  test "two independent cycles -> two SCCs, each with κ > 0" do
    result =
      Topology.analyze([
        {"A", "B"},
        {"B", "A"},
        {"C", "D"},
        {"D", "C"}
      ])

    assert result.routing == :deliberate
    assert result.scc_count == 2
    assert result.max_kappa >= 1

    assert Enum.all?(result.sccs, fn scc ->
             scc.kappa > 0 and scc.routing == :deliberate
           end)

    assert result.dag_nodes == []
  end

  test "mixed DAG + cycle -> dag_nodes listed separately and SCC identified" do
    result =
      Topology.analyze([
        {"A", "B"},
        {"B", "C"},
        {"C", "A"},
        {"D", "E"}
      ])

    assert result.routing == :deliberate
    assert result.scc_count == 1
    assert result.max_kappa == 1
    assert Enum.sort(result.dag_nodes) == ["D", "E"]

    [scc] = result.sccs
    assert Enum.sort(scc.nodes) == ["A", "B", "C"]
    assert scc.kappa == 1
  end

  test "business example topology includes κ=2 SCC and separate customer-retention loop" do
    # κ=2 SCC across two partitions:
    #   {market-share, revenue} <-> {r-and-d, product-quality}
    # plus an independent customer-retention loop
    edges = [
      {"market-share", "r-and-d"},
      {"market-share", "product-quality"},
      {"revenue", "r-and-d"},
      {"revenue", "product-quality"},
      {"r-and-d", "market-share"},
      {"r-and-d", "revenue"},
      {"product-quality", "market-share"},
      {"product-quality", "revenue"},
      {"customer-retention", "churn-risk"},
      {"churn-risk", "customer-retention"}
    ]

    result = Topology.analyze(edges)

    assert result.routing == :deliberate
    assert result.scc_count == 2
    assert result.max_kappa == 2

    k2_scc =
      Enum.find(result.sccs, fn scc ->
        Enum.sort(scc.nodes) ==
          Enum.sort(["market-share", "revenue", "r-and-d", "product-quality"])
      end)

    assert k2_scc
    assert k2_scc.kappa == 2
    assert k2_scc.approximate == false
  end

  test "single isolated node -> κ = 0" do
    result = Topology.analyze(%{"solo" => MapSet.new()})

    assert result.routing == :fast
    assert result.max_kappa == 0
    assert result.scc_count == 0
    assert result.sccs == []
    assert result.dag_nodes == ["solo"]
  end

  test "self-loop only -> κ = 0 (self-loops excluded from adjacency)" do
    result = Topology.analyze([{"A", "A"}])

    assert result.routing == :fast
    assert result.max_kappa == 0
    assert result.scc_count == 0
    assert result.sccs == []
    assert result.dag_nodes == ["A"]
  end

  test "K2,2 with both directions -> κ = 2" do
    left = ["L1", "L2"]
    right = ["R1", "R2"]

    edges =
      for l <- left, r <- right, dir <- [:lr, :rl] do
        case dir do
          :lr -> {l, r}
          :rl -> {r, l}
        end
      end

    result = Topology.analyze(edges)

    assert result.routing == :deliberate
    assert result.scc_count == 1
    assert result.max_kappa == 2

    [scc] = result.sccs
    assert Enum.sort(scc.nodes) == Enum.sort(left ++ right)
    assert scc.kappa == 2
    assert scc.approximate == false
  end

  test "large SCC (> 20 nodes) -> approximate=true and kappa=scc_size" do
    node_ids = Enum.map(1..21, &"N#{&1}")

    cycle_edges =
      node_ids
      |> Enum.with_index()
      |> Enum.map(fn {src, idx} ->
        dst = Enum.at(node_ids, rem(idx + 1, length(node_ids)))
        {src, dst}
      end)

    result = Topology.analyze(cycle_edges)

    assert result.routing == :deliberate
    assert result.scc_count == 1
    assert result.max_kappa == 21

    [scc] = result.sccs
    assert scc.approximate == true
    assert scc.kappa == 21
    assert length(scc.nodes) == 21
    assert scc.fault_line_edges == []
  end

  test "schema compliance uses canonical field names" do
    result = Topology.analyze([{"A", "B"}, {"B", "A"}])

    assert Enum.sort(Map.keys(result)) ==
             Enum.sort([:sccs, :dag_nodes, :routing, :max_kappa, :scc_count])

    [scc] = result.sccs

    assert Enum.sort(Map.keys(scc)) ==
             Enum.sort([
               :id,
               :nodes,
               :kappa,
               :approximate,
               :fault_line_edges,
               :routing,
               :deliberation_budget
             ])

    assert is_list(scc.fault_line_edges)

    Enum.each(scc.fault_line_edges, fn edge ->
      assert Enum.sort(Map.keys(edge)) == [:source, :target]
    end)
  end

  test "build_adjacency/2 converts Edge structs and preserves explicit node universe" do
    node_ids = ["A", "B", "C", "D"]

    edges = [
      edge("A", "B"),
      edge("B", "C"),
      edge("C", "C"),
      edge("X", "A"),
      edge("A", "X")
    ]

    adjacency = Topology.build_adjacency(node_ids, edges)

    assert Map.keys(adjacency) |> Enum.sort() == node_ids
    assert adjacency["A"] == MapSet.new(["B"])
    assert adjacency["B"] == MapSet.new(["C"])
    assert adjacency["C"] == MapSet.new()
    assert adjacency["D"] == MapSet.new()
  end

  test "preview_edge_impact/3 detects new SCC creation" do
    adjacency = %{
      "A" => MapSet.new(["B"]),
      "B" => MapSet.new(["C"]),
      "C" => MapSet.new()
    }

    preview = Topology.preview_edge_impact(adjacency, "C", "A")

    assert preview.creates_new_scc == true
    assert preview.kappa_before == 0
    assert preview.kappa_after == 1
    assert preview.kappa_delta == 1
    assert is_binary(preview.description)
    assert String.length(preview.description) > 0
  end

  test "deliberation_budget applies caps for larger κ values" do
    assert Topology.deliberation_budget(0) == %{
             max_iterations: 1,
             agent_count: 0,
             timeout_multiplier: 1.0,
             confidence_threshold: 0.7
           }

    assert Topology.deliberation_budget(2) == %{
             max_iterations: 3,
             agent_count: 2,
             timeout_multiplier: 2.0,
             confidence_threshold: 0.8
           }

    assert Topology.deliberation_budget(50) == %{
             max_iterations: 4,
             agent_count: 3,
             timeout_multiplier: 3.5,
             confidence_threshold: 0.95
           }
  end

  defp edge(source_id, target_id) do
    %Edge{
      id: "#{source_id}->#{target_id}",
      source_id: source_id,
      target_id: target_id,
      edge_type: :related,
      weight: 1.0,
      metadata: %{},
      created_at: DateTime.utc_now(),
      last_activated_at: DateTime.utc_now()
    }
  end
end
