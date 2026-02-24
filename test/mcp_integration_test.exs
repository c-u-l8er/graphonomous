defmodule Graphonomous.MCPIntegrationTest do
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

  test "store_node + retrieve_context behaves like MCP memory retrieval" do
    node =
      Graphonomous.store_node(%{
        content: "I prefer PostgreSQL over MySQL for OLTP workloads.",
        node_type: "semantic",
        confidence: 0.74,
        source: "integration_test:mcp"
      })

    assert is_binary(node.id)
    assert node.content =~ "PostgreSQL"

    retrieval =
      Graphonomous.retrieve_context(
        "what databases do I prefer for transactional workloads?",
        similarity_limit: 8,
        final_limit: 8,
        expansion_hops: 1
      )

    assert is_map(retrieval)

    results = Map.get(retrieval, :results, [])
    causal_context = Map.get(retrieval, :causal_context, [])

    assert is_list(results)
    assert is_list(causal_context)

    result_ids =
      Enum.map(results, fn row ->
        Map.get(row, :node_id)
      end)

    assert node.id in result_ids or node.id in causal_context
  end

  test "query_graph supports list/get/edges/similarity operations from API boundary" do
    n1 =
      Graphonomous.store_node(%{
        content: "PostgreSQL is my default OLTP database.",
        node_type: "semantic",
        confidence: 0.68,
        source: "integration_test:mcp"
      })

    n2 =
      Graphonomous.store_node(%{
        content: "CockroachDB is worth considering for geo-distributed SQL.",
        node_type: "semantic",
        confidence: 0.61,
        source: "integration_test:mcp"
      })

    edge =
      Graphonomous.link_nodes(n1.id, n2.id, %{
        edge_type: "related",
        weight: 0.83,
        metadata: %{"reason" => "database decision graph"}
      })

    assert edge.source_id == n1.id
    assert edge.target_id == n2.id

    listed =
      Graphonomous.query_graph(%{
        operation: "list_nodes",
        node_type: "semantic",
        limit: 20
      })

    assert is_list(listed)
    assert Enum.any?(listed, &(&1.id == n1.id))
    assert Enum.any?(listed, &(&1.id == n2.id))

    fetched = Graphonomous.query_graph(%{operation: "get_node", node_id: n1.id})
    assert fetched.id == n1.id

    edges = Graphonomous.query_graph(%{operation: "get_edges", node_id: n1.id})
    assert is_list(edges)

    assert Enum.any?(edges, fn e ->
             (e.source_id == n1.id and e.target_id == n2.id) or
               (e.source_id == n2.id and e.target_id == n1.id)
           end)

    matches =
      Graphonomous.query_graph(%{
        operation: "similarity_search",
        query: "preferred SQL database for OLTP",
        limit: 5
      })

    assert is_list(matches)

    assert Enum.any?(matches, fn m ->
             Map.get(m, :node_id) in [n1.id, n2.id]
           end)
  end

  test "learn_from_outcome updates confidence upward on success and downward on failure" do
    node =
      Graphonomous.store_node(%{
        content: "Use PostgreSQL for transactional systems by default.",
        node_type: "semantic",
        confidence: 0.5,
        source: "integration_test:mcp"
      })

    assert_in_delta(node.confidence, 0.5, 0.0001)

    success_result =
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("action"),
        status: :success,
        confidence: 1.0,
        causal_node_ids: [node.id],
        evidence: %{"scenario" => "query returned correct recommendation"}
      })

    assert success_result.processed == 1
    assert success_result.updated == 1

    after_success = Graphonomous.get_node(node.id)
    assert after_success.confidence > node.confidence

    failure_result =
      Graphonomous.learn_from_outcome(%{
        action_id: uniq("action"),
        status: :failure,
        confidence: 1.0,
        causal_node_ids: [node.id],
        evidence: %{"scenario" => "recommendation caused regression"}
      })

    assert failure_result.processed == 1
    assert failure_result.updated == 1

    after_failure = Graphonomous.get_node(node.id)
    assert after_failure.confidence < after_success.confidence
  end

  test "goal management flow supports create, list, transition, dependency, and node linking" do
    primary =
      Graphonomous.create_goal(%{
        title: "Ship Graphonomous v0.1",
        description: "MCP + continual learning loop",
        status: :proposed,
        timescale: :short_term,
        source_type: :user,
        priority: :high,
        owner: "integration_test",
        tags: ["mvp", "launch"],
        metadata: %{"suite" => "mcp_integration"},
        linked_node_ids: []
      })

    dependency =
      Graphonomous.create_goal(%{
        title: "Write release docs",
        status: :proposed,
        timescale: :short_term,
        source_type: :user,
        priority: :normal,
        owner: "integration_test"
      })

    assert is_binary(primary.id)
    assert is_binary(dependency.id)
    assert primary.status == :proposed
    assert dependency.status == :proposed

    listed = Graphonomous.list_goals(%{owner: "integration_test"})
    assert is_list(listed)
    assert Enum.any?(listed, &(&1.id == primary.id))
    assert Enum.any?(listed, &(&1.id == dependency.id))

    with_dep = Graphonomous.GoalGraph.add_dependency(primary.id, dependency.id)
    assert {:ok, dep_goal} = with_dep
    dependency_ids = dep_goal.constraints["dependency_goal_ids"] || []
    assert dependency.id in dependency_ids

    linked = Graphonomous.link_goal_nodes(primary.id, ["node_a", "node_b"])
    assert "node_a" in linked.linked_node_ids
    assert "node_b" in linked.linked_node_ids

    transitioned =
      Graphonomous.transition_goal(primary.id, :active, %{
        "source" => "integration_test",
        "reason" => "execution started"
      })

    assert transitioned.status == :active
    assert is_list(transitioned.metadata["transitions"])

    progressed = Graphonomous.set_goal_progress(primary.id, 1.0)
    assert progressed.status == :completed
    assert_in_delta progressed.progress, 1.0, 0.0001
    assert progressed.completed_at != nil
  end

  test "coverage review flow persists evaluation and supports decision-driven status transition" do
    goal =
      Graphonomous.create_goal(%{
        title: "Decide database strategy",
        status: :proposed,
        timescale: :short_term,
        source_type: :user,
        priority: :high,
        owner: "integration_test"
      })

    assert goal.status == :proposed

    signal = %{
      retrieved_nodes: [
        %{
          score: 0.95,
          confidence: 0.96,
          similarity: 0.95,
          edge_count: 8,
          updated_at: DateTime.utc_now()
        },
        %{
          score: 0.92,
          confidence: 0.93,
          similarity: 0.92,
          edge_count: 7,
          updated_at: DateTime.utc_now()
        },
        %{
          score: 0.90,
          confidence: 0.91,
          similarity: 0.90,
          edge_count: 6,
          updated_at: DateTime.utc_now()
        }
      ],
      outcomes: [
        %{status: :success, confidence: 0.95},
        %{status: :partial_success, confidence: 0.80}
      ],
      contradictions: 0,
      graph_support: 9,
      known_unknowns: 0.1,
      goal_criticality: 0.3
    }

    assert {:ok, reviewed_goal, evaluation} =
             Graphonomous.review_goal(goal.id, signal, top_k: 5, min_context_nodes: 2)

    assert reviewed_goal.id == goal.id
    assert reviewed_goal.last_reviewed_at != nil
    assert is_map(reviewed_goal.metadata["last_coverage_review"])
    assert evaluation.decision in [:act, :learn, :escalate]
    assert is_float(evaluation.coverage_score)
    assert is_float(evaluation.uncertainty_score)
    assert is_float(evaluation.risk_score)

    decided_status =
      case evaluation.decision do
        :act -> :active
        :learn -> :proposed
        :escalate -> :blocked
      end

    transitioned =
      Graphonomous.transition_goal(goal.id, decided_status, %{
        "source" => "integration_test:coverage",
        "decision" => Atom.to_string(evaluation.decision)
      })

    assert transitioned.status == decided_status
  end

  test "resource snapshots return runtime health and durable goals payloads" do
    _node =
      Graphonomous.store_node(%{
        content: "Resource snapshot integration coverage node",
        node_type: "semantic",
        confidence: 0.66,
        source: "integration_test:mcp_resources"
      })

    goal =
      Graphonomous.create_goal(%{
        title: "Validate MCP resource snapshot integration",
        status: :proposed,
        timescale: :short_term,
        source_type: :user,
        priority: :normal,
        owner: "integration_test"
      })

    frame = Anubis.Server.Frame.new()

    assert {:reply, health_response, _frame_after_health} =
             Graphonomous.MCP.Resources.HealthSnapshot.read(%{}, frame)

    assert health_response.type == :resource
    assert is_map(health_response.contents)
    assert is_binary(health_response.contents["text"])

    health_payload = Jason.decode!(health_response.contents["text"])
    assert is_map(health_payload["health"])
    assert is_map(health_payload["counts"])
    assert health_payload["counts"]["nodes"] >= 1
    assert health_payload["counts"]["goals"] >= 1

    assert {:reply, goals_response, _frame_after_goals} =
             Graphonomous.MCP.Resources.GoalsSnapshot.read(%{}, frame)

    assert goals_response.type == :resource
    assert is_map(goals_response.contents)
    assert is_binary(goals_response.contents["text"])

    goals_payload = Jason.decode!(goals_response.contents["text"])
    assert goals_payload["total"] >= 1
    assert is_map(goals_payload["by_status"])
    assert is_list(goals_payload["goals"])

    assert Enum.any?(goals_payload["goals"], fn g ->
             g["id"] == goal.id and g["title"] == goal.title
           end)
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

  defp uniq(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
