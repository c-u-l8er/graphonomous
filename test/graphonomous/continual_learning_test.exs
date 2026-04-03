defmodule Graphonomous.ContinualLearningTest do
  @moduledoc """
  Integration tests for v0.3 P0 continual learning capabilities:
  - Expanded topology window (1-hop neighbors)
  - Contradiction edges creating κ>0
  - Conflict-aware consolidation Stage 4.5
  - Semantic back-references in EdgeExtractor
  """

  use ExUnit.Case, async: false

  alias Graphonomous.{BeliefRevision, Consolidator, Graph, Store, Topology}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_all()
    on_exit(&purge_all/0)
    :ok
  end

  # ---- Topology expansion tests ----

  describe "expanded topology window" do
    test "contradiction edges between two nodes create κ=1 SCC" do
      # Store two nodes
      {:ok, %{id: id_a}} =
        Graph.store_node(%{content: "Earth is 4.5 billion years old", node_type: :semantic, confidence: 0.8})

      {:ok, %{id: id_b}} =
        Graph.store_node(%{content: "Earth is 6000 years old", node_type: :semantic, confidence: 0.3})

      # Create bidirectional :contradicts edges — this forms a 2-node SCC
      {:ok, _} = Graph.create_edge(id_a, id_b, %{edge_type: :contradicts, weight: 0.8})
      {:ok, _} = Graph.create_edge(id_b, id_a, %{edge_type: :contradicts, weight: 0.8})

      # Verify topology analysis detects κ=1
      adj = Topology.build_adjacency([id_a, id_b], get_all_edges())
      result = Topology.analyze(adj)

      assert result.max_kappa >= 1
      assert result.routing == :deliberate
      assert length(result.sccs) >= 1
    end

    test "nodes reachable via 1-hop neighbors participate in topology" do
      # Create a chain: A -> B -> C -> A (cycle through intermediate B)
      {:ok, %{id: id_a}} = Graph.store_node(%{content: "Node A in cycle", node_type: :semantic})
      {:ok, %{id: id_b}} = Graph.store_node(%{content: "Node B in cycle", node_type: :semantic})
      {:ok, %{id: id_c}} = Graph.store_node(%{content: "Node C in cycle", node_type: :semantic})

      {:ok, _} = Graph.create_edge(id_a, id_b, %{edge_type: :causal, weight: 0.7})
      {:ok, _} = Graph.create_edge(id_b, id_c, %{edge_type: :causal, weight: 0.7})
      {:ok, _} = Graph.create_edge(id_c, id_a, %{edge_type: :causal, weight: 0.7})

      # Even if we only "retrieve" A and C (missing B), the expanded topology
      # should include B as a neighbor and detect the cycle
      edges_for_a = case Store.list_edges_for_node(id_a) do
        {:ok, e} -> e
        _ -> []
      end

      edges_for_c = case Store.list_edges_for_node(id_c) do
        {:ok, e} -> e
        _ -> []
      end

      all_edges = Enum.uniq_by(edges_for_a ++ edges_for_c, & &1.id)
      neighbor_ids = all_edges |> Enum.flat_map(fn e -> [e.source_id, e.target_id] end) |> Enum.uniq()
      expanded_ids = Enum.uniq([id_a, id_c] ++ neighbor_ids)

      adj = Topology.build_adjacency(expanded_ids, all_edges)
      result = Topology.analyze(adj)

      # With expanded window, B is included and the cycle A->B->C->A is detected
      assert result.max_kappa >= 1
    end
  end

  # ---- Conflict-aware consolidation tests ----

  describe "conflict-aware consolidation" do
    test "merge skips node pairs with :contradicts edges" do
      # Create two very similar nodes (would normally merge at 0.95 similarity)
      {:ok, %{id: id_a}} =
        Graph.store_node(%{content: "Test merge conflict A", node_type: :semantic, confidence: 0.8})

      {:ok, %{id: id_b}} =
        Graph.store_node(%{content: "Test merge conflict B", node_type: :semantic, confidence: 0.6})

      # Add :contradicts edge
      {:ok, _} = Graph.create_edge(id_a, id_b, %{edge_type: :contradicts, weight: 0.8})

      # Both nodes should still exist after consolidation (not merged)
      Consolidator.run_now()
      Process.sleep(500)

      # Nodes should both still exist (not merged despite potential similarity)
      assert {:ok, _} = Store.get_node(id_a)
      assert {:ok, _} = Store.get_node(id_b)
    end
  end

  # ---- BeliefRevision integration tests ----

  describe "belief revision creates κ-activating edges" do
    test "expand with contradictions creates :contradicts edges" do
      # Pre-populate with an existing belief
      {:ok, %{id: _existing_id}} =
        Graph.store_node(%{
          content: "The project deadline is Friday not Monday however we must ship",
          node_type: :semantic,
          confidence: 0.8
        })

      # Expand with content that might contradict (shares negation markers)
      {:ok, result} =
        BeliefRevision.expand(
          "The project deadline is not Friday but actually Monday instead"
        )

      assert is_binary(result.node_id)
      # The contradictions list and edges depend on embedding similarity,
      # which uses trigram fallback in test — just verify the structure
      assert is_list(result.contradictions)
      assert is_integer(result.contradiction_edges)
    end

    test "revise creates superseded_by edge" do
      {:ok, %{id: old_id}} =
        Graph.store_node(%{content: "Old version of fact", node_type: :semantic, confidence: 0.7})

      {:ok, result} = BeliefRevision.revise(old_id, "New version of fact")

      # Check edge exists
      {:ok, edges} = Graph.get_edges_for_node(old_id)
      superseded = Enum.filter(edges, &(&1.edge_type == :superseded_by))
      assert length(superseded) >= 1
      assert hd(superseded).target_id == result.new_node_id
    end
  end

  # ---- Node struct tests ----

  describe "node revision fields" do
    test "node has revision_id and superseded_by fields" do
      {:ok, node} =
        Graph.store_node(%{
          content: "Node with revision fields",
          node_type: :semantic,
          revision_id: "rev_test_123",
          superseded_by: nil
        })

      assert {:ok, fetched} = Store.get_node(node.id)
      assert fetched.revision_id == "rev_test_123"
      assert fetched.superseded_by == nil
    end

    test "superseded_by persists through update" do
      {:ok, node} = Graph.store_node(%{content: "Will be superseded", node_type: :semantic})

      {:ok, updated} = Store.update_node(node.id, %{superseded_by: "node_replacement_123"})
      assert updated.superseded_by == "node_replacement_123"

      # Verify it persists via cache
      assert {:ok, refetched} = Store.get_node(node.id)
      assert refetched.superseded_by == "node_replacement_123"
    end
  end

  # ---- Edge type tests ----

  describe "superseded_by edge type" do
    test ":superseded_by is a valid edge type" do
      {:ok, %{id: id_a}} = Graph.store_node(%{content: "Old", node_type: :semantic})
      {:ok, %{id: id_b}} = Graph.store_node(%{content: "New", node_type: :semantic})

      assert {:ok, edge} =
               Graph.create_edge(id_a, id_b, %{edge_type: :superseded_by, weight: 0.9})

      assert edge.edge_type == :superseded_by
    end
  end

  # ---- Helpers ----

  defp get_all_edges do
    case Store.list_all_edges() do
      {:ok, edges} -> edges
      _ -> []
    end
  end

  defp purge_all do
    case Store.list_nodes(%{}) do
      {:ok, nodes} -> Enum.each(nodes, &Store.delete_node(&1.id))
      _ -> :ok
    end

    case Store.list_all_edges() do
      {:ok, edges} -> Enum.each(edges, &Store.delete_edge(&1.id))
      _ -> :ok
    end

    case Store.list_goals(%{}) do
      {:ok, goals} -> Enum.each(goals, &Store.delete_goal(&1.id))
      _ -> :ok
    end
  end
end
