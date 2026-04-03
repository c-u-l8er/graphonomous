defmodule Graphonomous.LearnerTest do
  use ExUnit.Case, async: false

  describe "learn_from_outcome/1 confidence updates" do
    test "increases confidence when outcome is success" do
      node = create_node(0.40)

      result =
        Graphonomous.learn_from_outcome(%{
          action_id: unique_action_id(),
          status: "success",
          confidence: 1.0,
          causal_node_ids: [node.id],
          evidence: %{source: "learner_test"}
        })

      assert is_map(result)
      assert result.processed == 1
      assert result.updated == 1
      assert result.skipped == 0

      assert [%{node_id: node_id, result: :updated, old_confidence: old_c, new_confidence: new_c}] =
               result.updates

      assert node_id == node.id
      assert new_c > old_c
      assert_in_delta new_c, expected_new(old_c, :success, 1.0), 1.0e-9

      updated = Graphonomous.get_node(node.id)
      assert_in_delta updated.confidence, new_c, 1.0e-9
    end

    test "decreases confidence when outcome is failure" do
      node = create_node(0.80)

      result =
        Graphonomous.learn_from_outcome(%{
          action_id: unique_action_id(),
          status: "failure",
          confidence: 1.0,
          causal_node_ids: [node.id],
          evidence: %{source: "learner_test"}
        })

      assert is_map(result)
      assert result.processed == 1
      assert result.updated == 1
      assert result.skipped == 0

      assert [%{node_id: node_id, result: :updated, old_confidence: old_c, new_confidence: new_c}] =
               result.updates

      assert node_id == node.id
      assert new_c < old_c
      assert_in_delta new_c, expected_new(old_c, :failure, 1.0), 1.0e-9

      updated = Graphonomous.get_node(node.id)
      assert_in_delta updated.confidence, new_c, 1.0e-9
    end

    test "processes mixed causal node IDs and reports skipped not found nodes" do
      node_a = create_node(0.60)
      node_b = create_node(0.20)
      missing_id = "node_missing_#{System.unique_integer([:positive, :monotonic])}"

      result =
        Graphonomous.learn_from_outcome(%{
          action_id: unique_action_id(),
          status: "partial_success",
          confidence: 1.0,
          causal_node_ids: [node_a.id, missing_id, node_b.id],
          evidence: %{"scenario" => "mixed_ids"}
        })

      assert is_map(result)
      assert result.processed == 3
      assert result.updated == 2
      assert result.skipped == 1
      assert length(result.updates) == 3

      update_a = Enum.find(result.updates, &(&1.node_id == node_a.id))
      update_b = Enum.find(result.updates, &(&1.node_id == node_b.id))
      update_missing = Enum.find(result.updates, &(&1.node_id == missing_id))

      assert update_a.result == :updated
      assert update_b.result == :updated
      assert update_missing.result == :skipped_not_found

      assert_in_delta update_a.new_confidence,
                      expected_new(update_a.old_confidence, :partial_success, 1.0),
                      1.0e-9

      assert_in_delta update_b.new_confidence,
                      expected_new(update_b.old_confidence, :partial_success, 1.0),
                      1.0e-9

      updated_a = Graphonomous.get_node(node_a.id)
      updated_b = Graphonomous.get_node(node_b.id)

      assert_in_delta updated_a.confidence, update_a.new_confidence, 1.0e-9
      assert_in_delta updated_b.confidence, update_b.new_confidence, 1.0e-9
    end

    test "propagates retrieval and decision trace fields through learner result and node feedback metadata" do
      node = create_node(0.55)
      retrieval_trace_id = "retrieval_#{System.unique_integer([:positive, :monotonic])}"
      decision_trace_id = "decision_#{System.unique_integer([:positive, :monotonic])}"

      result =
        Graphonomous.learn_from_outcome(%{
          action_id: unique_action_id(),
          status: "success",
          confidence: 0.9,
          causal_node_ids: [node.id],
          evidence: %{source: "learner_test"},
          retrieval_trace_id: retrieval_trace_id,
          decision_trace_id: decision_trace_id,
          action_linkage: %{"step" => "execute"},
          grounding: %{"basis" => "retrieval_context"}
        })

      assert is_map(result)
      assert result.retrieval_trace_id == retrieval_trace_id
      assert result.decision_trace_id == decision_trace_id
      assert result.action_linkage["step"] == "execute"
      assert result.grounding["basis"] == "retrieval_context"

      updated = Graphonomous.get_node(node.id)
      feedback = updated.metadata["last_feedback"]

      assert is_map(feedback)
      assert Map.get(feedback, :retrieval_trace_id) == retrieval_trace_id
      assert Map.get(feedback, :decision_trace_id) == decision_trace_id
      assert Map.get(feedback, :action_linkage)["step"] == "execute"
      assert Map.get(feedback, :grounding)["basis"] == "retrieval_context"
    end
  end

  describe "P3: causal edge metadata updates" do
    test "success outcome strengthens causal edge" do
      node_a = create_node(0.5)
      node_b = create_node(0.5)

      # Create a causal edge between the nodes
      {:ok, edge} =
        Graphonomous.Graph.create_edge(node_a.id, node_b.id, %{
          edge_type: :causal,
          weight: 0.7,
          metadata: %{"causal_strength" => 0.5}
        })

      result =
        Graphonomous.learn_from_outcome(%{
          action_id: unique_action_id(),
          status: "success",
          confidence: 1.0,
          causal_node_ids: [node_a.id, node_b.id],
          evidence: %{source: "causal_test"}
        })

      assert result.causal_edges_updated == 1

      # Verify edge metadata updated
      {:ok, updated_edge} = Graphonomous.Store.get_edge(edge.id)
      assert updated_edge.metadata["causal_strength"] == 0.6
      assert is_list(updated_edge.metadata["intervention_history"])
      assert length(updated_edge.metadata["intervention_history"]) == 1
    end

    test "failure outcome weakens causal edge" do
      node_a = create_node(0.5)
      node_b = create_node(0.5)

      {:ok, edge} =
        Graphonomous.Graph.create_edge(node_a.id, node_b.id, %{
          edge_type: :causal,
          weight: 0.7,
          metadata: %{"causal_strength" => 0.5}
        })

      Graphonomous.learn_from_outcome(%{
        action_id: unique_action_id(),
        status: "failure",
        confidence: 1.0,
        causal_node_ids: [node_a.id, node_b.id]
      })

      {:ok, updated_edge} = Graphonomous.Store.get_edge(edge.id)
      assert_in_delta updated_edge.metadata["causal_strength"], 0.35, 1.0e-9
    end

    test "causal_strength persists in edge metadata" do
      node_a = create_node(0.6)
      node_b = create_node(0.6)

      {:ok, _edge} =
        Graphonomous.Graph.create_edge(node_a.id, node_b.id, %{
          edge_type: :causes,
          weight: 0.7
        })

      # No initial causal_strength → defaults to 0.5
      Graphonomous.learn_from_outcome(%{
        action_id: unique_action_id(),
        status: "success",
        confidence: 0.9,
        causal_node_ids: [node_a.id, node_b.id]
      })

      {:ok, edges} = Graphonomous.Store.list_edges_for_node(node_a.id)

      causal_edges =
        Enum.filter(edges, fn e -> e.edge_type in [:causal, :causes] end)

      assert length(causal_edges) >= 1
      causal_edge = hd(causal_edges)
      assert is_float(causal_edge.metadata["causal_strength"])
      assert causal_edge.metadata["causal_strength"] == 0.6
    end

    test "confounders field accepted and stored" do
      node_a = create_node(0.5)
      node_b = create_node(0.5)
      node_c = create_node(0.5)

      {:ok, edge} =
        Graphonomous.Graph.create_edge(node_a.id, node_b.id, %{
          edge_type: :causal,
          weight: 0.7,
          metadata: %{
            "causal_strength" => 0.6,
            "confounders" => [node_c.id]
          }
        })

      Graphonomous.learn_from_outcome(%{
        action_id: unique_action_id(),
        status: "success",
        confidence: 1.0,
        causal_node_ids: [node_a.id, node_b.id]
      })

      {:ok, updated_edge} = Graphonomous.Store.get_edge(edge.id)
      assert updated_edge.metadata["confounders"] == [node_c.id]
      assert updated_edge.metadata["causal_strength"] == 0.7
    end
  end

  defp create_node(confidence) do
    node =
      Graphonomous.store_node(%{
        content: "test fact #{System.unique_integer([:positive, :monotonic])}",
        node_type: "semantic",
        confidence: confidence,
        source: "learner_test"
      })

    assert is_map(node)
    assert is_binary(node.id)
    node
  end

  defp unique_action_id do
    "action_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp expected_new(old_confidence, status, outcome_confidence, learning_rate \\ 0.2) do
    old = clamp01(old_confidence)
    signal = status_signal(status) * clamp01(outcome_confidence)
    target = clamp01((signal + 1.0) / 2.0)
    clamp01(old * (1.0 - learning_rate) + target * learning_rate)
  end

  defp status_signal(:success), do: 1.0
  defp status_signal(:partial_success), do: 0.4
  defp status_signal(:failure), do: -0.5
  defp status_signal(:timeout), do: -0.25

  defp clamp01(v) when v < 0.0, do: 0.0
  defp clamp01(v) when v > 1.0, do: 1.0
  defp clamp01(v), do: v
end
