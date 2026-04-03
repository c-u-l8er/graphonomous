defmodule Graphonomous.P1ContinualLearningTest do
  @moduledoc """
  Integration tests for v0.3 P1 continual learning capabilities:
  - Two-phase retrieval (Q-value utility scoring)
  - Simplified forgetting (hybrid pruning + GDPR hard delete)
  - Q-value decay in consolidation
  """

  use ExUnit.Case, async: false

  alias Graphonomous.{Consolidator, Forgetter, Graph, Learner, Retriever, Store}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_all()
    on_exit(&purge_all/0)
    :ok
  end

  # ---- Two-Phase Retrieval Tests ----

  describe "two-phase retrieval: Q-value utility scoring" do
    test "Q-value updates from successful outcome increase node Q-value" do
      {:ok, %{id: node_id}} =
        Graph.store_node(%{
          content: "Elixir pattern matching is powerful",
          node_type: :semantic,
          confidence: 0.7
        })

      # Verify initial Q-value
      {:ok, node} = Store.get_node(node_id)
      assert node.q_value == 0.5
      assert node.q_update_count == 0

      # Learn from successful outcome
      {:ok, result} =
        Learner.learn_from_outcome(%{
          action_id: "test_action_1",
          status: :success,
          confidence: 0.9,
          causal_node_ids: [node_id]
        })

      assert result.updated == 1
      update = hd(result.updates)
      assert update.new_q_value > 0.5
      assert update.q_update_count == 1

      # Verify persisted
      {:ok, updated_node} = Store.get_node(node_id)
      assert updated_node.q_value > 0.5
      assert updated_node.q_update_count == 1
    end

    test "Q-value updates from failed outcome decrease node Q-value" do
      {:ok, %{id: node_id}} =
        Graph.store_node(%{
          content: "Deprecated API approach",
          node_type: :procedural,
          confidence: 0.6
        })

      {:ok, _} =
        Learner.learn_from_outcome(%{
          action_id: "test_action_2",
          status: :failure,
          confidence: 0.8,
          causal_node_ids: [node_id]
        })

      {:ok, node} = Store.get_node(node_id)
      assert node.q_value < 0.5
      assert node.q_update_count == 1
    end

    test "Q-values don't affect ranking when q_update_count == 0 for all candidates" do
      # Store 5 nodes with no outcome data
      ids =
        for i <- 1..5 do
          {:ok, %{id: id}} =
            Graph.store_node(%{
              content: "Test concept #{i} about retrieval ranking",
              node_type: :semantic,
              confidence: 0.5 + i * 0.05
            })

          id
        end

      # All should have q_update_count == 0
      for id <- ids do
        {:ok, node} = Store.get_node(id)
        assert node.q_update_count == 0
      end

      # Retrieve — Q-values should not change ordering
      {:ok, result} = Retriever.retrieve("retrieval ranking")
      # Scores should be based purely on semantic similarity, not Q-values
      assert length(result.results) > 0
      assert Enum.all?(result.results, fn r -> is_nil(Map.get(r, :utility)) end)
    end

    test "re-ranking promotes successful nodes over failed nodes" do
      # Create nodes with identical confidence but different outcome histories
      {:ok, %{id: good_id}} =
        Graph.store_node(%{
          content: "Effective caching strategy for web applications",
          node_type: :procedural,
          confidence: 0.7
        })

      {:ok, %{id: bad_id}} =
        Graph.store_node(%{
          content: "Outdated caching strategy for web applications",
          node_type: :procedural,
          confidence: 0.7
        })

      # Mark good node as successful 3 times
      for _ <- 1..3 do
        Learner.learn_from_outcome(%{
          action_id: "success_#{:rand.uniform(1000)}",
          status: :success,
          confidence: 0.9,
          causal_node_ids: [good_id]
        })
      end

      # Mark bad node as failed 2 times
      for _ <- 1..2 do
        Learner.learn_from_outcome(%{
          action_id: "failure_#{:rand.uniform(1000)}",
          status: :failure,
          confidence: 0.8,
          causal_node_ids: [bad_id]
        })
      end

      {:ok, good_node} = Store.get_node(good_id)
      {:ok, bad_node} = Store.get_node(bad_id)

      assert good_node.q_value > bad_node.q_value
      assert good_node.q_update_count == 3
      assert bad_node.q_update_count == 2
    end

    test "Q-value decay is slower than confidence decay" do
      {:ok, %{id: node_id}} =
        Graph.store_node(%{
          content: "Node for decay rate comparison",
          node_type: :semantic,
          confidence: 0.8,
          q_value: 0.8
        })

      # Run consolidation (which triggers decay)
      Consolidator.run_now()
      Process.sleep(200)

      {:ok, node} = Store.get_node(node_id)

      # Both should have decayed, but Q-value should decay slower
      conf_decay = 0.8 - node.confidence
      q_decay = 0.8 - node.q_value

      # Q decay should be roughly half of confidence decay
      if conf_decay > 0.001 do
        assert q_decay < conf_decay
        # Allow some tolerance - q_decay should be approximately half
        assert q_decay <= conf_decay * 0.7
      end
    end
  end

  # ---- Intentional Forgetting Tests ----

  describe "intentional forgetting: soft forget" do
    test "soft forget sets forgotten_at and excludes from retrieval" do
      {:ok, %{id: node_id}} =
        Graph.store_node(%{
          content: "This knowledge will be forgotten softly",
          node_type: :semantic,
          confidence: 0.7
        })

      # Verify node exists
      {:ok, node} = Store.get_node(node_id)
      assert is_nil(node.forgotten_at)

      # Soft forget
      {:ok, result} = Forgetter.forget(node_id, :soft)
      assert result.mode == :soft

      # Verify forgotten_at is set
      {:ok, forgotten_node} = Store.get_node(node_id)
      assert %DateTime{} = forgotten_node.forgotten_at

      # Verify excluded from retrieval
      {:ok, retrieval} = Retriever.retrieve("forgotten softly")
      node_ids = Enum.map(retrieval.results, & &1.node_id)
      refute node_id in node_ids
    end
  end

  describe "intentional forgetting: hard delete" do
    test "hard forget removes node and all edges" do
      {:ok, %{id: id_a}} =
        Graph.store_node(%{
          content: "Node A for hard delete",
          node_type: :semantic,
          confidence: 0.7
        })

      {:ok, %{id: id_b}} =
        Graph.store_node(%{content: "Node B linked to A", node_type: :semantic, confidence: 0.6})

      # Create edge between them
      {:ok, _} = Graph.create_edge(id_a, id_b, %{edge_type: :related, weight: 0.5})

      # Verify edge exists
      {:ok, edges} = Graph.get_edges_for_node(id_a)
      assert length(edges) > 0

      # Hard forget node A
      {:ok, result} = Forgetter.forget(id_a, :hard)
      assert result.mode == :hard

      # Verify node A is gone
      assert {:error, :not_found} = Store.get_node(id_a)

      # Verify edges are severed
      {:ok, remaining_edges} = Graph.get_edges_for_node(id_b)

      refute Enum.any?(remaining_edges, fn e ->
               e.source_id == id_a or e.target_id == id_a
             end)
    end
  end

  describe "intentional forgetting: cascade delete" do
    test "cascade forget propagates to orphaned dependents" do
      {:ok, %{id: parent_id}} =
        Graph.store_node(%{content: "Parent node", node_type: :semantic, confidence: 0.8})

      {:ok, %{id: orphan_id}} =
        Graph.store_node(%{content: "Orphan child node", node_type: :semantic, confidence: 0.5})

      {:ok, %{id: supported_id}} =
        Graph.store_node(%{
          content: "Well-supported child",
          node_type: :semantic,
          confidence: 0.6
        })

      {:ok, %{id: other_parent}} =
        Graph.store_node(%{content: "Other parent", node_type: :semantic, confidence: 0.7})

      # Parent -> orphan (orphan's only support)
      {:ok, _} = Graph.create_edge(parent_id, orphan_id, %{edge_type: :supports, weight: 0.7})
      # Parent -> supported
      {:ok, _} = Graph.create_edge(parent_id, supported_id, %{edge_type: :supports, weight: 0.6})
      # Other parent -> supported (supported has multiple parents)
      {:ok, _} =
        Graph.create_edge(other_parent, supported_id, %{edge_type: :supports, weight: 0.5})

      # Cascade delete parent
      {:ok, result} = Forgetter.forget(parent_id, :cascade)
      assert result.mode == :cascade

      # Parent should be gone
      assert {:error, :not_found} = Store.get_node(parent_id)

      # Orphan should be gone (only support was parent)
      assert {:error, :not_found} = Store.get_node(orphan_id)

      # Supported child should survive (has another parent)
      {:ok, _} = Store.get_node(supported_id)
    end
  end

  describe "intentional forgetting: GDPR erase" do
    test "GDPR erase completely removes node with no trace" do
      {:ok, %{id: node_id}} =
        Graph.store_node(%{
          content: "PII data that must be erased",
          node_type: :episodic,
          confidence: 0.9
        })

      {:ok, %{id: linked_id}} =
        Graph.store_node(%{content: "Linked node", node_type: :semantic, confidence: 0.5})

      {:ok, _} = Graph.create_edge(node_id, linked_id, %{edge_type: :related, weight: 0.5})

      # GDPR erase
      {:ok, result} = Forgetter.gdpr_erase(node_id)
      assert result.status == :erased
      assert result.audit.node_id == node_id

      # Completely gone
      assert {:error, :not_found} = Store.get_node(node_id)
    end
  end

  describe "intentional forgetting: hybrid policy" do
    test "budget-aware hybrid pruning respects max_nodes" do
      # Create 20 nodes with varying properties
      for i <- 1..20 do
        Graph.store_node(%{
          content: "Budget test node #{i}",
          node_type: :semantic,
          confidence: 0.1 + i * 0.04,
          access_count: i
        })
      end

      # Run hybrid policy with max_nodes=10
      {:ok, result} = Forgetter.forget_by_policy(:hybrid, max_nodes: 10)

      assert result.forgotten_count == 10
      assert result.surviving_count == 10

      # Verify highest-priority nodes survived
      {:ok, surviving} = Graph.list_nodes(%{})
      active = Enum.filter(surviving, &is_nil(&1.forgotten_at))
      assert length(active) == 10

      # Surviving nodes should have higher confidence (on average)
      avg_conf = Enum.map(active, & &1.confidence) |> Enum.sum() |> Kernel./(10)
      assert avg_conf > 0.5
    end

    test "priority scoring favors high-confidence, recent, connected nodes" do
      {:ok, %{id: high_id}} =
        Graph.store_node(%{
          content: "High priority node",
          node_type: :semantic,
          confidence: 0.9,
          access_count: 50
        })

      {:ok, %{id: low_id}} =
        Graph.store_node(%{
          content: "Low priority node",
          node_type: :semantic,
          confidence: 0.1,
          access_count: 0
        })

      {:ok, high_node} = Store.get_node(high_id)
      {:ok, low_node} = Store.get_node(low_id)

      high_score = Forgetter.priority_score(high_node)
      low_score = Forgetter.priority_score(low_node)

      assert high_score > low_score
    end

    test "dry run returns candidates without forgetting" do
      for i <- 1..10 do
        Graph.store_node(%{
          content: "Dry run test node #{i}",
          node_type: :semantic,
          confidence: 0.1 * i
        })
      end

      {:ok, result} = Forgetter.forget_by_policy(:hybrid, max_nodes: 5, dry_run: true)

      assert result.forgotten_count == 0
      assert result.would_forget == 5
      assert length(result.candidates) == 5
    end
  end

  describe "forgotten nodes in topology" do
    test "forgotten nodes don't appear in retrieval results" do
      {:ok, %{id: _visible_id}} =
        Graph.store_node(%{
          content: "Visible topology test node about graph theory",
          node_type: :semantic,
          confidence: 0.8
        })

      {:ok, %{id: hidden_id}} =
        Graph.store_node(%{
          content: "Hidden topology test node about graph theory",
          node_type: :semantic,
          confidence: 0.8
        })

      # Soft forget one node
      {:ok, _} = Forgetter.forget(hidden_id, :soft)

      # Retrieve
      {:ok, result} = Retriever.retrieve("graph theory topology test")
      result_ids = Enum.map(result.results, & &1.node_id)

      refute hidden_id in result_ids
    end
  end

  # ---- Helpers ----

  defp purge_all do
    case Graph.list_nodes(%{}) do
      {:ok, nodes} ->
        Enum.each(nodes, fn n -> Graph.delete_node(n.id) end)

      _ ->
        :ok
    end

    case Graph.list_all_edges() do
      {:ok, edges} -> Enum.each(edges, fn e -> Graph.delete_edge(e.id) end)
      _ -> :ok
    end
  end
end
