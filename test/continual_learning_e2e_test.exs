defmodule Graphonomous.ContinualLearningE2ETest do
  @moduledoc """
  End-to-end tests for the full continual learning loop:

    store → retrieve → act → learn_from_outcome → re-retrieve → consolidate

  Exercises the complete cycle that Phase 2 was designed to enable.
  """

  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_nodes()
    purge_goals()
    :ok
  end

  describe "happy path: full learning cycle" do
    test "store → retrieve → outcome(success) → re-retrieve shows confidence increase" do
      # 1. Store initial knowledge
      node =
        Graphonomous.store_node(%{
          content: "Elixir GenServers should use handle_continue for async init.",
          node_type: "procedural",
          confidence: 0.6,
          source: "e2e_test"
        })

      assert is_binary(node.id)

      # 2. Retrieve — node should appear
      retrieval1 =
        Graphonomous.retrieve_context(
          "how should I initialize GenServer state asynchronously?",
          limit: 5,
          expansion_hops: 1
        )

      results1 = Map.get(retrieval1, :results, [])
      assert Enum.any?(results1, &(&1.node_id == node.id))
      _causal_ids = Map.get(retrieval1, :causal_context, [])

      # 3. Act on the knowledge, then report success
      outcome =
        Graphonomous.learn_from_outcome(%{
          action_id: uniq("action"),
          status: :success,
          confidence: 0.9,
          causal_node_ids: [node.id],
          evidence: %{"scenario" => "handle_continue worked correctly in production"}
        })

      assert outcome.processed == 1
      assert outcome.updated == 1

      # 4. Verify confidence increased
      updated_node = Graphonomous.get_node(node.id)
      assert updated_node.confidence > node.confidence

      # 5. Re-retrieve — same query, node should still appear with higher confidence
      retrieval2 =
        Graphonomous.retrieve_context(
          "how should I initialize GenServer state asynchronously?",
          limit: 5,
          expansion_hops: 1
        )

      results2 = Map.get(retrieval2, :results, [])
      match2 = Enum.find(results2, &(&1.node_id == node.id))
      assert match2 != nil
      assert match2.confidence > node.confidence
    end

    test "store → outcome(failure) → re-retrieve shows confidence decrease" do
      node =
        Graphonomous.store_node(%{
          content: "Always use Task.async for database queries in Phoenix controllers.",
          node_type: "procedural",
          confidence: 0.7,
          source: "e2e_test"
        })

      # Report failure
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("action"),
        status: :failure,
        confidence: 0.95,
        causal_node_ids: [node.id],
        evidence: %{"scenario" => "Task.async caused race conditions with Ecto sandbox"}
      })

      after_failure = Graphonomous.get_node(node.id)
      assert after_failure.confidence < node.confidence
    end

    test "multiple outcomes compound confidence updates" do
      node =
        Graphonomous.store_node(%{
          content: "Use ETS for read-heavy caches in Elixir applications.",
          node_type: "semantic",
          confidence: 0.5,
          source: "e2e_test"
        })

      # Three successes in a row
      for _ <- 1..3 do
        Graphonomous.learn_from_outcome(%{
          action_id: uniq("action"),
          status: :success,
          confidence: 0.85,
          causal_node_ids: [node.id]
        })
      end

      after_3_successes = Graphonomous.get_node(node.id)
      assert after_3_successes.confidence > 0.6

      # Then a failure
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("action"),
        status: :failure,
        confidence: 0.9,
        causal_node_ids: [node.id]
      })

      after_failure = Graphonomous.get_node(node.id)
      # Should decrease but not below original
      assert after_failure.confidence < after_3_successes.confidence
      assert after_failure.confidence > node.confidence
    end
  end

  describe "edge-supported retrieval" do
    test "edges between nodes improve graph_support in coverage evaluation" do
      n1 =
        Graphonomous.store_node(%{
          content: "PostgreSQL excels at OLTP with strong ACID guarantees.",
          node_type: "semantic",
          confidence: 0.8,
          source: "e2e_test"
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Use pg_stat_statements to find slow queries in PostgreSQL.",
          node_type: "procedural",
          confidence: 0.75,
          source: "e2e_test"
        })

      n3 =
        Graphonomous.store_node(%{
          content: "PostgreSQL connection pooling with PgBouncer reduces overhead.",
          node_type: "semantic",
          confidence: 0.7,
          source: "e2e_test"
        })

      # Create supporting edges
      Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "supports", weight: 0.9})
      Graphonomous.link_nodes(n1.id, n3.id, %{edge_type: "related", weight: 0.8})
      Graphonomous.link_nodes(n2.id, n3.id, %{edge_type: "supports", weight: 0.7})

      # Retrieve and build coverage signal
      retrieval =
        Graphonomous.retrieve_context("PostgreSQL performance tuning",
          limit: 5,
          expansion_hops: 1
        )

      results = Map.get(retrieval, :results, [])
      assert length(results) >= 2

      # Evaluate coverage — graph_support should be non-zero thanks to edges
      signal = %{
        retrieved_nodes: results,
        outcomes: [],
        contradictions: 0
      }

      evaluation = Graphonomous.evaluate_coverage(signal)
      assert evaluation.components.graph_support > 0.0
    end
  end

  describe "goal-driven learning cycle" do
    test "create goal → store knowledge → link → review → outcome → progress" do
      # 1. Create a goal
      goal =
        Graphonomous.create_goal(%{
          title: "Optimize database queries",
          description: "Reduce p99 latency below 100ms",
          status: :proposed,
          timescale: :short_term,
          source_type: :user,
          priority: :high,
          owner: "e2e_test"
        })

      assert goal.status == :proposed

      # 2. Store relevant knowledge
      n1 =
        Graphonomous.store_node(%{
          content: "Query plan analysis revealed sequential scans on the orders table.",
          node_type: "episodic",
          confidence: 0.9,
          source: "e2e_test"
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Adding a composite index on (user_id, created_at) fixes the scan.",
          node_type: "procedural",
          confidence: 0.85,
          source: "e2e_test"
        })

      Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "causal", weight: 0.9})

      # 3. Link knowledge to goal
      linked = Graphonomous.link_goal_nodes(goal.id, [n1.id, n2.id])
      assert n1.id in linked.linked_node_ids
      assert n2.id in linked.linked_node_ids

      # 4. Review coverage
      signal = %{
        retrieved_nodes: [
          %{node_id: n1.id, confidence: 0.9, similarity: 0.85, edge_count: 1},
          %{node_id: n2.id, confidence: 0.85, similarity: 0.80, edge_count: 1}
        ],
        outcomes: [],
        contradictions: 0,
        graph_support: 2
      }

      {:ok, reviewed, evaluation} = Graphonomous.review_goal(goal.id, signal)
      assert evaluation.decision in [:act, :learn, :escalate]
      assert reviewed.last_reviewed_at != nil

      # 5. Transition to active and act
      active = Graphonomous.transition_goal(goal.id, :active, %{"reason" => "coverage adequate"})
      assert active.status == :active

      # 6. Report outcome
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("db-optimization"),
        status: :success,
        confidence: 0.95,
        causal_node_ids: [n1.id, n2.id],
        evidence: %{"p99_before" => "450ms", "p99_after" => "78ms"}
      })

      # 7. Complete goal
      completed = Graphonomous.set_goal_progress(goal.id, 1.0)
      assert completed.status == :completed
      assert completed.completed_at != nil

      # 8. Verify knowledge confidence increased
      n1_after = Graphonomous.get_node(n1.id)
      n2_after = Graphonomous.get_node(n2.id)
      assert n1_after.confidence > n1.confidence
      assert n2_after.confidence > n2.confidence
    end
  end

  describe "consolidation survives learning" do
    test "consolidation preserves high-confidence nodes and their edges" do
      n1 =
        Graphonomous.store_node(%{
          content: "Consolidation test: high confidence node that should survive.",
          node_type: "semantic",
          confidence: 0.9,
          source: "e2e_test"
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Consolidation test: another high confidence node.",
          node_type: "semantic",
          confidence: 0.85,
          source: "e2e_test"
        })

      Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "supports", weight: 0.8})

      # Run consolidation
      _result = Graphonomous.run_consolidation_now()

      # Both nodes should still exist (high confidence, not prunable)
      assert Graphonomous.get_node(n1.id) != nil
      assert Graphonomous.get_node(n2.id) != nil

      # Edge should still exist
      edges = Graphonomous.query_graph(%{operation: "get_edges", node_id: n1.id})
      assert is_list(edges)
      assert length(edges) >= 1
    end

    test "consolidation cycle count increments" do
      info_before = Graphonomous.consolidator_info()
      count_before = Map.get(info_before, :cycle_count, 0)

      Graphonomous.run_consolidation_now()

      info_after = Graphonomous.consolidator_info()
      count_after = Map.get(info_after, :cycle_count, 0)

      assert count_after > count_before
    end
  end

  describe "conflicting knowledge" do
    test "contradicting nodes can coexist with edges marking the contradiction" do
      n1 =
        Graphonomous.store_node(%{
          content: "Microservices are the best architecture for all new projects.",
          node_type: "semantic",
          confidence: 0.6,
          source: "e2e_test:opinion_a"
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Monoliths are better than microservices for small teams.",
          node_type: "semantic",
          confidence: 0.7,
          source: "e2e_test:opinion_b"
        })

      # Mark contradiction
      edge =
        Graphonomous.link_nodes(n1.id, n2.id, %{
          edge_type: "contradicts",
          weight: 0.9,
          metadata: %{"reason" => "opposing architectural recommendations"}
        })

      assert edge.edge_type == :contradicts || edge.edge_type == "contradicts"

      # Coverage with contradiction should increase risk
      signal = %{
        retrieved_nodes: [
          %{node_id: n1.id, confidence: 0.6, similarity: 0.8},
          %{node_id: n2.id, confidence: 0.7, similarity: 0.75}
        ],
        outcomes: [],
        contradictions: 1,
        graph_support: 1
      }

      evaluation = Graphonomous.evaluate_coverage(signal)
      # Contradiction should reduce consistency score
      assert evaluation.components.consistency < 1.0
    end

    test "failure outcome reduces confidence, tipping the balance" do
      n_wrong =
        Graphonomous.store_node(%{
          content: "Always use SELECT * in production queries for flexibility.",
          node_type: "procedural",
          confidence: 0.7,
          source: "e2e_test"
        })

      n_right =
        Graphonomous.store_node(%{
          content: "Only select needed columns to reduce I/O and improve cache hit rate.",
          node_type: "procedural",
          confidence: 0.7,
          source: "e2e_test"
        })

      Graphonomous.link_nodes(n_wrong.id, n_right.id, %{edge_type: "contradicts", weight: 0.9})

      # Report failure for the wrong advice
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("action"),
        status: :failure,
        confidence: 0.95,
        causal_node_ids: [n_wrong.id],
        evidence: %{"scenario" => "SELECT * caused OOM on wide table"}
      })

      # Report success for the right advice
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("action"),
        status: :success,
        confidence: 0.95,
        causal_node_ids: [n_right.id],
        evidence: %{"scenario" => "selective columns reduced memory 80%"}
      })

      wrong_after = Graphonomous.get_node(n_wrong.id)
      right_after = Graphonomous.get_node(n_right.id)

      # The correct advice should now have higher confidence
      assert right_after.confidence > wrong_after.confidence
    end
  end

  describe "topology awareness" do
    test "retrieve_context returns topology signals" do
      _n1 =
        Graphonomous.store_node(%{
          content: "Auth middleware validates JWT tokens.",
          node_type: "semantic",
          confidence: 0.8,
          source: "e2e_test"
        })

      retrieval =
        Graphonomous.retrieve_context("JWT token validation",
          limit: 5,
          expansion_hops: 1
        )

      assert is_map(retrieval)
      topology = Map.get(retrieval, :topology, %{})
      assert is_map(topology)
      assert Map.has_key?(topology, :routing)
      assert Map.get(topology, :routing) in ["fast", "deliberate", :fast, :deliberate]
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp purge_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        Enum.each(nodes, fn node -> _ = Graphonomous.delete_node(node.id) end)

      _ ->
        :ok
    end
  end

  defp purge_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: 10_000}) do
      goals when is_list(goals) ->
        Enum.each(goals, fn goal -> _ = Graphonomous.delete_goal(goal.id) end)

      _ ->
        :ok
    end
  end

  defp uniq(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
