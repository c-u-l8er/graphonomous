defmodule Graphonomous.GoalGraphTest do
  use ExUnit.Case, async: false

  alias Graphonomous.GoalGraph

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_goals()
    on_exit(&purge_goals/0)
    :ok
  end

  test "durable goal CRUD lifecycle works end-to-end" do
    due_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    assert {:ok, created} =
             GoalGraph.create_goal(%{
               title: "Ship Graphonomous v0.1",
               description: "Deliver MCP server + CL loop",
               status: :proposed,
               timescale: :short_term,
               source_type: :user,
               priority: :high,
               confidence: 0.8,
               progress: 0.1,
               owner: "ampersandbox",
               tags: ["launch", "mvp"],
               constraints: %{"deadline" => "4 weeks"},
               success_criteria: %{"tests" => "all green"},
               metadata: %{"origin" => "goal_graph_test"},
               linked_node_ids: ["node_alpha"],
               due_at: due_at
             })

    assert is_binary(created.id)
    assert created.title == "Ship Graphonomous v0.1"
    assert created.status == :proposed
    assert created.priority == :high
    assert created.timescale == :short_term
    assert created.source_type == :user
    assert created.owner == "ampersandbox"
    assert "launch" in created.tags
    assert "mvp" in created.tags
    assert created.linked_node_ids == ["node_alpha"]

    assert {:ok, fetched} = GoalGraph.get_goal(created.id)
    assert fetched.id == created.id
    assert fetched.title == created.title

    assert {:ok, updated} =
             GoalGraph.update_goal(created.id, %{
               title: "Ship Graphonomous v0.1.1",
               priority: :critical,
               progress: 0.6,
               tags: ["launch", "mvp", "critical-path"]
             })

    assert updated.id == created.id
    assert updated.title == "Ship Graphonomous v0.1.1"
    assert updated.priority == :critical
    assert_in_delta updated.progress, 0.6, 1.0e-6
    assert "critical-path" in updated.tags

    assert :ok = GoalGraph.delete_goal(created.id)
    assert {:error, :not_found} = GoalGraph.get_goal(created.id)
  end

  test "valid transitions are applied and invalid transitions are rejected" do
    goal = create_goal!("Transition readiness goal")

    assert {:ok, active} =
             GoalGraph.transition_goal(goal.id, :active, %{
               "reason" => "execution started"
             })

    assert active.status == :active
    assert is_map(active.metadata)
    assert is_list(active.metadata["transitions"])
    assert hd(active.metadata["transitions"])["to"] == "active"

    assert {:ok, completed} =
             GoalGraph.transition_goal(goal.id, :completed, %{
               "reason" => "done"
             })

    assert completed.status == :completed
    assert completed.completed_at != nil
    assert_in_delta completed.progress, 1.0, 1.0e-6

    assert {:error, {:invalid_transition, :completed, :active}} =
             GoalGraph.transition_goal(goal.id, :active, %{})
  end

  test "dependencies and linked node operations persist correctly" do
    main = create_goal!("Main objective")
    dep = create_goal!("Dependency objective")

    assert {:ok, with_dep} = GoalGraph.add_dependency(main.id, dep.id)

    deps =
      with_dep.constraints
      |> Map.get("dependency_goal_ids", [])

    assert dep.id in deps

    assert {:ok, without_dep} = GoalGraph.remove_dependency(main.id, dep.id)

    deps_after_removal =
      without_dep.constraints
      |> Map.get("dependency_goal_ids", [])

    refute dep.id in deps_after_removal

    assert {:ok, linked} =
             GoalGraph.link_nodes(main.id, ["node_a", "node_b", "node_a"])

    assert Enum.sort(linked.linked_node_ids) == ["node_a", "node_b"]

    assert {:ok, unlinked} = GoalGraph.unlink_nodes(main.id, ["node_b"])
    assert unlinked.linked_node_ids == ["node_a"]
  end

  test "goal review writes coverage evaluation metadata and last reviewed timestamp" do
    goal = create_goal!("Coverage-reviewed objective")

    signal = %{
      retrieved_nodes: [
        %{score: 0.95, confidence: 0.95, similarity: 0.95, edge_count: 5},
        %{score: 0.90, confidence: 0.90, similarity: 0.90, edge_count: 4}
      ],
      outcomes: [
        %{status: :success, confidence: 0.9},
        %{status: :partial_success, confidence: 0.8}
      ],
      contradictions: 0,
      graph_support: 8,
      known_unknowns: 0.1,
      goal_criticality: 0.4
    }

    assert {:ok, reviewed_goal, evaluation} =
             GoalGraph.review_goal(goal.id, signal, top_k: 5, min_context_nodes: 2)

    assert reviewed_goal.id == goal.id
    assert reviewed_goal.last_reviewed_at != nil

    review_meta = reviewed_goal.metadata["last_coverage_review"]
    assert is_map(review_meta)
    assert review_meta["decision"] in ["act", "learn", "escalate"]
    assert is_number(review_meta["coverage_score"])
    assert is_number(review_meta["uncertainty_score"])
    assert is_number(review_meta["risk_score"])

    assert evaluation.decision in [:act, :learn, :escalate]
    assert evaluation.coverage_score >= 0.0 and evaluation.coverage_score <= 1.0
    assert evaluation.uncertainty_score >= 0.0 and evaluation.uncertainty_score <= 1.0
    assert evaluation.risk_score >= 0.0 and evaluation.risk_score <= 1.0
    assert is_list(evaluation.rationale)
  end

  defp create_goal!(title) do
    assert {:ok, goal} =
             GoalGraph.create_goal(%{
               title: title,
               status: :proposed,
               priority: :normal,
               source_type: :user,
               timescale: :short_term,
               metadata: %{"suite" => "goal_graph_test"}
             })

    goal
  end

  defp purge_goals do
    case GoalGraph.list_goals(%{include_abandoned: true, limit: 10_000}) do
      {:ok, goals} when is_list(goals) ->
        Enum.each(goals, fn goal ->
          _ = GoalGraph.delete_goal(goal.id)
        end)

      _ ->
        :ok
    end
  end
end
