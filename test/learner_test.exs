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
