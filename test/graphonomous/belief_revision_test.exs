defmodule Graphonomous.BeliefRevisionTest do
  use ExUnit.Case, async: false

  alias Graphonomous.{BeliefRevision, Graph, Store}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_all()
    on_exit(&purge_all/0)
    :ok
  end

  # ---- Expand ----

  test "expand stores a node and records a revision" do
    assert {:ok, result} = BeliefRevision.expand("The sky is blue")
    assert is_binary(result.node_id)
    assert is_binary(result.revision_id)
    assert is_list(result.contradictions)

    # Verify node exists
    assert {:ok, node} = Store.get_node(result.node_id)
    assert node.content == "The sky is blue"
    assert node.revision_id == result.revision_id

    # Verify revision record
    assert {:ok, revisions} = Store.list_revisions_for_node(result.node_id)
    assert length(revisions) >= 1
    rev = hd(revisions)
    assert rev.operation == "expansion"
  end

  test "expand with custom confidence" do
    assert {:ok, result} = BeliefRevision.expand("Custom confidence fact", confidence: 0.8)
    assert {:ok, node} = Store.get_node(result.node_id)
    assert_in_delta node.confidence, 0.8, 0.01
  end

  # ---- Revise ----

  test "revise supersedes old node and creates new one" do
    # Create original belief
    {:ok, %{id: old_id}} =
      Graph.store_node(%{content: "Original belief", confidence: 0.7, node_type: :semantic})

    assert {:ok, result} =
             BeliefRevision.revise(old_id, "Revised belief", rationale: "Updated understanding")

    assert result.old_node_id == old_id
    assert is_binary(result.new_node_id)
    assert result.new_node_id != old_id

    # Old node should be superseded
    assert {:ok, old_node} = Store.get_node(old_id)
    assert old_node.superseded_by == result.new_node_id
    assert old_node.confidence < 0.3

    # New node should exist
    assert {:ok, new_node} = Store.get_node(result.new_node_id)
    assert new_node.content == "Revised belief"

    # superseded_by edge should exist
    assert {:ok, edges} = Graph.get_edges_for_node(old_id)
    superseded_edges = Enum.filter(edges, &(&1.edge_type == :superseded_by))
    assert length(superseded_edges) >= 1
  end

  test "revise returns error for non-existent node" do
    assert {:error, :not_found} = BeliefRevision.revise("nonexistent_id", "New content")
  end

  # ---- Contract ----

  test "contract reduces confidence to near-zero" do
    {:ok, %{id: node_id}} =
      Graph.store_node(%{content: "Belief to contract", confidence: 0.8, node_type: :semantic})

    assert {:ok, result} = BeliefRevision.contract(node_id, rationale: "No longer valid")
    assert result.node_id == node_id

    # Confidence should be near zero
    assert {:ok, node} = Store.get_node(node_id)
    assert node.confidence < 0.1
  end

  test "contract propagates retraction to dependents" do
    # Create a node and a dependent
    {:ok, %{id: parent_id}} =
      Graph.store_node(%{content: "Parent belief", confidence: 0.8, node_type: :semantic})

    {:ok, %{id: child_id}} =
      Graph.store_node(%{content: "Derived belief", confidence: 0.7, node_type: :semantic})

    # Create derived_from edge
    {:ok, _} =
      Graph.create_edge(parent_id, child_id, %{edge_type: :derived_from, weight: 0.8})

    # Contract the parent
    assert {:ok, result} = BeliefRevision.contract(parent_id)
    assert child_id in result.affected_node_ids

    # Child confidence should be reduced
    assert {:ok, child} = Store.get_node(child_id)
    assert child.confidence < 0.7
  end

  # ---- Contradiction detection ----

  test "detect_contradictions returns empty for novel content" do
    # With no nodes in graph, nothing contradicts anything
    assert [] = BeliefRevision.detect_contradictions("Completely novel content")
  end

  test "detect_contradictions_for_node returns empty for non-existent node" do
    assert [] = BeliefRevision.detect_contradictions_for_node("nonexistent")
  end

  # ---- Resolution ----

  test "resolve_contradiction returns :unresolved for equal-strength nodes" do
    {:ok, %{id: id_a}} =
      Graph.store_node(%{content: "Claim A", confidence: 0.5, node_type: :semantic})

    {:ok, %{id: id_b}} =
      Graph.store_node(%{content: "Claim B", confidence: 0.5, node_type: :semantic})

    assert {:ok, decision} = BeliefRevision.resolve_contradiction(id_a, id_b)
    assert decision in [:keep_a, :keep_b, :unresolved]
  end

  test "resolve_contradiction errors for non-existent nodes" do
    assert {:error, :not_found} = BeliefRevision.resolve_contradiction("fake_a", "fake_b")
  end

  # ---- Resolution hooks ----

  test "register and use custom resolution hook" do
    defmodule TestResolver do
      def resolve(_a, _b), do: {:ok, :keep_a}
    end

    BeliefRevision.register_resolution_hook(TestResolver)
    assert BeliefRevision.get_resolution_hook() == TestResolver

    {:ok, %{id: id_a}} =
      Graph.store_node(%{content: "Hook claim A", confidence: 0.5, node_type: :semantic})

    {:ok, %{id: id_b}} =
      Graph.store_node(%{content: "Hook claim B", confidence: 0.5, node_type: :semantic})

    assert {:ok, :keep_a} = BeliefRevision.resolve_contradiction(id_a, id_b)

    # Clean up
    :persistent_term.erase({BeliefRevision, :resolution_hook})
  end

  # ---- Helpers ----

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
