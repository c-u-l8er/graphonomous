defmodule Graphonomous.GraphTest do
  use ExUnit.Case, async: false

  alias Graphonomous.Graph

  setup do
    # Keep tests deterministic by clearing all existing nodes first.
    {:ok, nodes} = Graph.list_nodes(%{})

    Enum.each(nodes, fn node ->
      _ = Graph.delete_node(node.id)
    end)

    :ok
  end

  test "node CRUD lifecycle works end-to-end" do
    create_attrs = %{
      content: "I prefer PostgreSQL over MySQL for OLTP workloads.",
      node_type: "semantic",
      confidence: 0.7,
      source: "unit-test",
      metadata: %{"topic" => "databases"}
    }

    assert {:ok, node} = Graph.store_node(create_attrs)
    assert is_binary(node.id)
    assert node.content == create_attrs.content
    assert node.node_type == :semantic
    assert_in_delta node.confidence, 0.7, 1.0e-6

    assert {:ok, fetched} = Graph.get_node(node.id)
    assert fetched.id == node.id
    assert fetched.content == node.content

    assert {:ok, updated} =
             Graph.update_node(node.id, %{
               content: "I now prefer CockroachDB for global OLTP workloads.",
               confidence: 0.9,
               source: "unit-test-update"
             })

    assert updated.id == node.id
    assert updated.content == "I now prefer CockroachDB for global OLTP workloads."
    assert_in_delta updated.confidence, 0.9, 1.0e-6
    assert updated.source == "unit-test-update"

    assert :ok == Graph.delete_node(node.id)
    assert {:error, :not_found} = Graph.get_node(node.id)
  end

  test "edge queries return connected edges for a node" do
    {:ok, source} =
      Graph.store_node(%{
        content: "PostgreSQL supports ACID transactions.",
        node_type: "semantic",
        confidence: 0.8
      })

    {:ok, target} =
      Graph.store_node(%{
        content: "CockroachDB is compatible with PostgreSQL wire protocol.",
        node_type: "semantic",
        confidence: 0.75
      })

    assert {:ok, edge} =
             Graph.create_edge(source.id, target.id, %{
               edge_type: "supports",
               weight: 0.85,
               metadata: %{"reason" => "shared SQL ecosystem"}
             })

    assert edge.source_id == source.id
    assert edge.target_id == target.id

    assert {:ok, source_edges} = Graph.get_edges_for_node(source.id)
    assert Enum.any?(source_edges, fn e -> e.id == edge.id end)

    assert {:ok, target_edges} = Graph.get_edges_for_node(target.id)
    assert Enum.any?(target_edges, fn e -> e.id == edge.id end)

    assert {:ok, queried_edges} = Graph.query(%{operation: "get_edges", node_id: source.id})
    assert Enum.any?(queried_edges, fn e -> e.id == edge.id end)
  end

  test "query list_nodes applies type and confidence filters" do
    {:ok, _semantic} =
      Graph.store_node(%{
        content: "Semantic memory node",
        node_type: "semantic",
        confidence: 0.9
      })

    {:ok, _episodic} =
      Graph.store_node(%{
        content: "Episodic memory node",
        node_type: "episodic",
        confidence: 0.4
      })

    assert {:ok, semantic_nodes} =
             Graph.query(%{
               operation: "list_nodes",
               node_type: "semantic",
               min_confidence: 0.5
             })

    assert length(semantic_nodes) == 1
    only = hd(semantic_nodes)
    assert only.node_type == :semantic
    assert only.confidence >= 0.5
  end
end
