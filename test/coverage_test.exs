defmodule Graphonomous.CoverageTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Coverage

  describe "evaluate/2 decision policy" do
    test "returns :act for strong, consistent, low-risk evidence" do
      now = DateTime.utc_now()

      signal = %{
        retrieved_nodes: [
          node(0.96, 0.98, 0.96, now, 10),
          node(0.93, 0.95, 0.94, now, 9),
          node(0.91, 0.94, 0.93, now, 8),
          node(0.90, 0.93, 0.92, now, 8),
          node(0.88, 0.92, 0.91, now, 7)
        ],
        outcomes: [
          %{status: :success, confidence: 1.0},
          %{status: :success, confidence: 0.9}
        ],
        contradictions: 0,
        graph_support: 12,
        known_unknowns: 0.05,
        goal_criticality: 0.2
      }

      result = Coverage.evaluate(signal)

      assert result.decision == :act
      assert result.coverage_score >= 0.72
      assert result.uncertainty_score <= 0.35
      assert result.risk_score <= 0.45
      assert result.decision_confidence > 0.7

      assert is_map(result.components)
      assert Map.has_key?(result.components, :semantic_coverage)
      assert Map.has_key?(result.components, :consistency)
      assert Map.has_key?(result.components, :freshness)
      assert Map.has_key?(result.components, :graph_support)
      assert Map.has_key?(result.components, :outcome_reliability)

      assert is_list(result.rationale)
      assert length(result.rationale) >= 1
      assert %DateTime{} = result.computed_at
    end

    test "returns :learn for moderate evidence that is below act threshold but acceptable for learning" do
      now = DateTime.utc_now()

      signal = %{
        retrieved_nodes: [
          node(0.58, 0.72, 0.66, now, 4),
          node(0.56, 0.70, 0.64, now, 4),
          node(0.54, 0.68, 0.63, now, 3),
          node(0.50, 0.66, 0.60, now, 3)
        ],
        outcomes: [
          %{status: :partial_success, confidence: 0.8},
          %{status: :success, confidence: 0.6},
          %{status: :failure, confidence: 0.3}
        ],
        contradictions: 1,
        graph_support: 5,
        known_unknowns: 0.35,
        goal_criticality: 0.45
      }

      result = Coverage.evaluate(signal)

      assert result.decision == :learn
      assert result.coverage_score >= 0.45
      assert result.uncertainty_score <= 0.70
      assert result.risk_score <= 0.75
      refute result.decision == :act
    end

    test "returns :escalate for sparse, contradictory, and risky evidence" do
      stale = ~U[2020-01-01 00:00:00Z]

      signal = %{
        retrieved_nodes: [
          node(0.18, 0.25, 0.30, stale, 0),
          node(0.15, 0.22, 0.28, stale, 0)
        ],
        outcomes: [
          %{status: :failure, confidence: 1.0},
          %{status: :timeout, confidence: 0.9},
          %{status: :failure, confidence: 0.8}
        ],
        contradictions: 4,
        graph_support: 0,
        known_unknowns: 0.9,
        goal_criticality: 0.95
      }

      result = Coverage.evaluate(signal)

      assert result.decision == :escalate

      assert result.risk_score > 0.45 or result.uncertainty_score > 0.70 or
               result.coverage_score < 0.45

      assert result.decision_confidence >= 0.0 and result.decision_confidence <= 1.0
    end
  end

  describe "decide/2 and recommend/2" do
    test "decide/2 returns only the decision atom" do
      now = DateTime.utc_now()

      signal = %{
        retrieved_nodes: [
          node(0.95, 0.97, 0.95, now, 8),
          node(0.92, 0.95, 0.93, now, 8),
          node(0.90, 0.94, 0.92, now, 7)
        ],
        outcomes: [%{status: :success, confidence: 0.95}],
        contradictions: 0,
        graph_support: 9,
        known_unknowns: 0.1,
        goal_criticality: 0.2
      }

      assert Coverage.decide(signal) in [:act, :learn, :escalate]
    end

    test "recommend/2 returns concise orchestration payload" do
      now = DateTime.utc_now()

      signal = %{
        retrieved_nodes: [
          node(0.60, 0.75, 0.70, now, 3),
          node(0.57, 0.72, 0.67, now, 3),
          node(0.55, 0.70, 0.65, now, 2)
        ],
        outcomes: [%{status: :partial_success, confidence: 0.8}],
        contradictions: 1,
        graph_support: 4,
        known_unknowns: 0.3,
        goal_criticality: 0.5
      }

      rec = Coverage.recommend(signal)

      assert Map.keys(rec) |> Enum.sort() ==
               [
                 :coverage_score,
                 :decision,
                 :decision_confidence,
                 :rationale,
                 :risk_score,
                 :uncertainty_score
               ]
               |> Enum.sort()

      assert rec.decision in [:act, :learn, :escalate]
      assert is_float(rec.coverage_score)
      assert is_float(rec.uncertainty_score)
      assert is_float(rec.risk_score)
      assert is_list(rec.rationale)
    end

    test "accepts string keys and status strings" do
      now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

      signal = %{
        "retrieved_nodes" => [
          %{
            "score" => 0.93,
            "confidence" => 0.95,
            "similarity" => 0.94,
            "updated_at" => now_iso,
            "edge_count" => 9
          },
          %{
            "score" => 0.91,
            "confidence" => 0.93,
            "similarity" => 0.92,
            "updated_at" => now_iso,
            "edge_count" => 8
          },
          %{
            "score" => 0.89,
            "confidence" => 0.92,
            "similarity" => 0.91,
            "updated_at" => now_iso,
            "edge_count" => 7
          }
        ],
        "outcomes" => [
          %{"status" => "success", "confidence" => 0.95}
        ],
        "contradictions" => 0,
        "graph_support" => 10,
        "known_unknowns" => 0.1,
        "goal_criticality" => 0.2
      }

      result = Coverage.evaluate(signal)

      assert result.decision in [:act, :learn, :escalate]
      assert is_map(result.diagnostics)
      assert result.diagnostics.node_count == 3
      assert result.diagnostics.outcome_count == 1
    end
  end

  defp node(score, confidence, similarity, updated_at, edge_count) do
    %{
      score: score,
      confidence: confidence,
      similarity: similarity,
      updated_at: updated_at,
      edge_count: edge_count
    }
  end
end
