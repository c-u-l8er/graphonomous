defmodule Graphonomous.RetrieverTopologyTest do
  use ExUnit.Case, async: false

  setup do
    cleanup_nodes()
    on_exit(&cleanup_nodes/0)
    :ok
  end

  test "retrieve_context includes topology output with canonical field names" do
    market =
      store_node!(%{
        content: "Market share shifts when pricing strategy changes.",
        node_type: :semantic,
        confidence: 0.95,
        source: "retriever-topology-test"
      })

    revenue =
      store_node!(%{
        content: "Revenue responds to market share and pricing strategy.",
        node_type: :semantic,
        confidence: 0.94,
        source: "retriever-topology-test"
      })

    quality =
      store_node!(%{
        content: "Product quality impacts revenue and market share outcomes.",
        node_type: :semantic,
        confidence: 0.93,
        source: "retriever-topology-test"
      })

    _d1 =
      store_node!(%{
        content: "Founding date is a static fact for company profile.",
        node_type: :semantic,
        confidence: 0.5,
        source: "retriever-topology-test"
      })

    _d2 =
      store_node!(%{
        content: "Headquarters location is another static company fact.",
        node_type: :semantic,
        confidence: 0.5,
        source: "retriever-topology-test"
      })

    :ok = link!(market.id, revenue.id)
    :ok = link!(revenue.id, quality.id)
    :ok = link!(quality.id, market.id)

    retrieval =
      Graphonomous.retrieve_context(
        "pricing strategy feedback loop for market share and revenue",
        similarity_limit: 10,
        final_limit: 10,
        expansion_hops: 3,
        neighbors_per_node: 10
      )

    assert is_map(retrieval)
    assert Map.has_key?(retrieval, :results)
    assert Map.has_key?(retrieval, :causal_context)
    assert Map.has_key?(retrieval, :stats)
    assert Map.has_key?(retrieval, :topology)

    topology = retrieval.topology
    assert is_map(topology)

    assert Enum.sort(Map.keys(topology)) ==
             Enum.sort([:sccs, :dag_nodes, :routing, :max_kappa, :scc_count])

    assert is_list(topology.sccs)
    assert is_list(topology.dag_nodes)
    assert topology.routing in [:fast, :deliberate]
    assert is_integer(topology.max_kappa)
    assert is_integer(topology.scc_count)

    assert topology.routing == :deliberate
    assert topology.scc_count >= 1
    assert topology.max_kappa >= 1

    cycle_ids = MapSet.new([market.id, revenue.id, quality.id])

    cycle_scc =
      Enum.find(topology.sccs, fn scc ->
        MapSet.subset?(cycle_ids, MapSet.new(Map.get(scc, :nodes, [])))
      end)

    assert is_map(cycle_scc)

    assert Enum.sort(Map.keys(cycle_scc)) ==
             Enum.sort([
               :id,
               :nodes,
               :kappa,
               :approximate,
               :fault_line_edges,
               :routing,
               :deliberation_budget
             ])

    assert cycle_scc.routing == :deliberate
    assert is_integer(cycle_scc.kappa)
    assert cycle_scc.kappa >= 1
    assert is_boolean(cycle_scc.approximate)

    assert is_map(cycle_scc.deliberation_budget)

    assert Enum.sort(Map.keys(cycle_scc.deliberation_budget)) ==
             Enum.sort([
               :max_iterations,
               :agent_count,
               :timeout_multiplier,
               :confidence_threshold
             ])

    Enum.each(cycle_scc.fault_line_edges, fn edge ->
      assert is_map(edge)
      assert Enum.sort(Map.keys(edge)) == [:source, :target]
      assert is_binary(edge.source)
      assert is_binary(edge.target)
    end)
  end

  defp link!(source_id, target_id) do
    case Graphonomous.link_nodes(source_id, target_id, %{edge_type: :related, weight: 1.0}) do
      %{source_id: ^source_id, target_id: ^target_id} -> :ok
      other -> flunk("expected edge #{source_id} -> #{target_id}, got: #{inspect(other)}")
    end
  end

  defp store_node!(attrs) do
    case Graphonomous.store_node(attrs) do
      %{id: id} = node when is_binary(id) ->
        node

      other ->
        flunk("expected stored node, got: #{inspect(other)}")
    end
  end

  defp cleanup_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        Enum.each(nodes, fn node ->
          _ = Graphonomous.delete_node(node.id)
        end)

      _ ->
        :ok
    end
  end
end
