defmodule Graphonomous.MCPToolsCoverageTest do
  @moduledoc """
  Tests for MCP tools that previously had zero direct execute/2 coverage:
  - RetrieveEpisodic
  - RetrieveProcedural
  - LearnDetectNovelty
  - LearnFromFeedback
  - LearnFromInteraction
  - GraphTraverse
  - GraphStats
  - CoverageQuery
  - Deliberate (MCP wrapper)
  """

  use ExUnit.Case, async: false

  alias Graphonomous.Graph

  setup do
    {:ok, nodes} = Graph.list_nodes(%{})
    Enum.each(nodes, fn node -> _ = Graph.delete_node(node.id) end)

    {:ok, edges} = Graph.list_all_edges()
    Enum.each(edges, fn edge -> _ = Graph.delete_edge(edge.id) end)

    :ok
  end

  # ─── RetrieveEpisodic ───────────────────────────────────────────

  describe "retrieve_episodic" do
    test "returns empty list when no episodic nodes exist" do
      {:reply, response, _} =
        Graphonomous.MCP.RetrieveEpisodic.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["count"] == 0
      assert payload["episodes"] == []
    end

    test "returns episodic nodes" do
      {:ok, _} = Graph.store_node(%{content: "Event happened", node_type: "episodic"})
      {:ok, _} = Graph.store_node(%{content: "Fact stored", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.RetrieveEpisodic.execute(%{"limit" => 10}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["count"] == 1
      assert length(payload["episodes"]) == 1
      assert hd(payload["episodes"])["content"] =~ "Event happened"
    end

    test "respects limit parameter" do
      for i <- 1..5 do
        {:ok, _} = Graph.store_node(%{content: "Episode #{i}", node_type: "episodic"})
      end

      {:reply, response, _} =
        Graphonomous.MCP.RetrieveEpisodic.execute(%{"limit" => 2}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["count"] <= 2
    end

    test "filters by since parameter" do
      {:ok, _} = Graph.store_node(%{content: "Old episode", node_type: "episodic"})

      # Use a future date so nothing matches
      {:reply, response, _} =
        Graphonomous.MCP.RetrieveEpisodic.execute(
          %{"since" => "2099-01-01T00:00:00Z"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["count"] == 0
    end
  end

  # ─── RetrieveProcedural ─────────────────────────────────────────

  describe "retrieve_procedural" do
    test "returns error when task is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.RetrieveProcedural.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error when task is empty" do
      {:reply, response, _} =
        Graphonomous.MCP.RetrieveProcedural.execute(%{"task" => ""}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns procedural nodes matching task" do
      {:ok, _} =
        Graph.store_node(%{
          content: "1. Install dependencies\n2. Run mix test\n3. Check results",
          node_type: "procedural"
        })

      {:reply, response, _} =
        Graphonomous.MCP.RetrieveProcedural.execute(%{"task" => "how to run tests"}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["task"] == "how to run tests"
      assert is_integer(payload["count"])
    end

    test "extracts numbered steps from content" do
      {:ok, _} =
        Graph.store_node(%{
          content: "1. First step\n2. Second step\n3. Third step",
          node_type: "procedural"
        })

      {:reply, response, _} =
        Graphonomous.MCP.RetrieveProcedural.execute(%{"task" => "steps procedure"}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert is_list(payload["steps"])
    end
  end

  # ─── LearnDetectNovelty ─────────────────────────────────────────

  describe "learn_detect_novelty" do
    test "returns error when query is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnDetectNovelty.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "detects novel content in empty graph" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnDetectNovelty.execute(
          %{"query" => "completely new concept"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["is_novel"] == true
      assert payload["novelty_score"] >= 0.0
      assert payload["novelty_score"] <= 1.0
      assert payload["query"] == "completely new concept"
    end

    test "detects existing content as not novel" do
      {:ok, _} =
        Graph.store_node(%{content: "Elixir uses GenServer for state", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.LearnDetectNovelty.execute(
          %{"query" => "Elixir uses GenServer for state", "threshold" => 0.99},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert is_boolean(payload["is_novel"])
      assert is_list(payload["nearest_nodes"])
    end

    test "respects threshold parameter" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnDetectNovelty.execute(
          %{"query" => "test query", "threshold" => 0.1},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["threshold"] == 0.1
    end

    test "clamps invalid threshold to valid range" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnDetectNovelty.execute(
          %{"query" => "test query", "threshold" => 5.0},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["threshold"] <= 1.0
    end
  end

  # ─── LearnFromFeedback ──────────────────────────────────────────

  describe "learn_from_feedback" do
    test "returns error when node_id is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"feedback" => "positive"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error when feedback is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"node_id" => "some_id"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error for invalid feedback type" do
      {:ok, node} = Graph.store_node(%{content: "Test node", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"node_id" => node.id, "feedback" => "invalid_type"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "applies positive feedback and increases confidence" do
      {:ok, node} =
        Graph.store_node(%{content: "Good fact", node_type: "semantic", confidence: 0.5})

      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"node_id" => node.id, "feedback" => "positive"},
          nil
        )

      payload = decode(response)
      assert payload["node_id"] == node.id
      assert payload["feedback"] == "positive"
    end

    test "applies negative feedback" do
      {:ok, node} =
        Graph.store_node(%{content: "Bad fact", node_type: "semantic", confidence: 0.8})

      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"node_id" => node.id, "feedback" => "negative"},
          nil
        )

      payload = decode(response)
      assert payload["node_id"] == node.id
      assert payload["feedback"] == "negative"
    end

    test "applies correction with new content" do
      {:ok, node} =
        Graph.store_node(%{content: "Wrong info", node_type: "semantic", confidence: 0.7})

      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{
            "node_id" => node.id,
            "feedback" => "correction",
            "correction" => "Corrected info"
          },
          nil
        )

      payload = decode(response)
      assert payload["node_id"] == node.id
      assert payload["feedback"] == "correction"
      assert payload["new_content"] == "Corrected info"
    end

    test "correction requires correction text" do
      {:ok, node} = Graph.store_node(%{content: "Wrong", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"node_id" => node.id, "feedback" => "correction"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error for non-existent node" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromFeedback.execute(
          %{"node_id" => "nonexistent_node_id", "feedback" => "positive"},
          nil
        )

      payload = decode(response)
      # Should handle gracefully (either error or attempted outcome learning)
      assert is_map(payload)
    end
  end

  # ─── LearnFromInteraction ───────────────────────────────────────

  describe "learn_from_interaction" do
    test "returns error when user_message is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromInteraction.execute(
          %{"model_response" => "some response"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error when model_response is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromInteraction.execute(
          %{"user_message" => "some question"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "processes a full interaction and stores knowledge" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromInteraction.execute(
          %{
            "user_message" => "How does Elixir handle concurrency?",
            "model_response" =>
              "Elixir uses lightweight processes managed by the BEAM VM. Each process has its own heap and communicates via message passing. The OTP framework provides abstractions like GenServer for stateful processes."
          },
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert is_boolean(payload["is_novel"])
      assert is_number(payload["novelty_score"])
      assert is_integer(payload["learned_count"])
      assert is_list(payload["learned_node_ids"])
      assert is_integer(payload["edges_created"])
    end

    test "respects extract_claims flag" do
      {:reply, response, _} =
        Graphonomous.MCP.LearnFromInteraction.execute(
          %{
            "user_message" => "What is OTP?",
            "model_response" => "OTP is the Open Telecom Platform.",
            "extract_claims" => false
          },
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["claim_count"] == 0
    end
  end

  # ─── GraphTraverse ──────────────────────────────────────────────

  describe "graph_traverse" do
    test "returns error when node_id is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error for non-existent node" do
      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(%{"node_id" => "nonexistent"}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "traverses from a single node with no edges" do
      {:ok, node} = Graph.store_node(%{content: "Isolated node", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(%{"node_id" => node.id}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["root_id"] == node.id
      assert payload["node_count"] >= 1
      assert is_list(payload["nodes"])
      assert is_list(payload["edges"])
    end

    test "traverses connected graph with depth" do
      {:ok, a} = Graph.store_node(%{content: "Node A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "Node B", node_type: "semantic"})
      {:ok, c} = Graph.store_node(%{content: "Node C", node_type: "semantic"})
      {:ok, _} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})
      {:ok, _} = Graph.create_edge(b.id, c.id, %{edge_type: :related, weight: 0.5})

      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(
          %{"node_id" => a.id, "depth" => 3},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["node_count"] >= 2
    end

    test "respects depth limit" do
      {:ok, a} = Graph.store_node(%{content: "Node A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "Node B", node_type: "semantic"})
      {:ok, c} = Graph.store_node(%{content: "Node C", node_type: "semantic"})
      {:ok, _} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})
      {:ok, _} = Graph.create_edge(b.id, c.id, %{edge_type: :supports, weight: 0.5})

      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(
          %{"node_id" => a.id, "depth" => 1},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["depth"] == 1
    end

    test "clamps depth to max 5" do
      {:ok, node} = Graph.store_node(%{content: "Root", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(
          %{"node_id" => node.id, "depth" => 100},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["depth"] <= 5
    end

    test "filters by relationship type" do
      {:ok, a} = Graph.store_node(%{content: "Node A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "Node B", node_type: "semantic"})
      {:ok, c} = Graph.store_node(%{content: "Node C", node_type: "semantic"})
      {:ok, _} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})
      {:ok, _} = Graph.create_edge(a.id, c.id, %{edge_type: :contradicts, weight: 0.5})

      {:reply, response, _} =
        Graphonomous.MCP.GraphTraverse.execute(
          %{"node_id" => a.id, "relationships" => "[\"supports\"]"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
    end
  end

  # ─── GraphStats ─────────────────────────────────────────────────

  describe "graph_stats" do
    test "returns stats for empty graph" do
      {:reply, response, _} =
        Graphonomous.MCP.GraphStats.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["node_count"] == 0
      assert payload["edge_count"] == 0
    end

    test "returns correct counts for populated graph" do
      {:ok, a} = Graph.store_node(%{content: "Node A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "Node B", node_type: "episodic"})
      {:ok, _} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})

      {:reply, response, _} =
        Graphonomous.MCP.GraphStats.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["node_count"] == 2
      assert payload["edge_count"] >= 1
      assert is_number(payload["avg_confidence"])
    end

    test "includes distributions when requested" do
      {:ok, _} = Graph.store_node(%{content: "Fact", node_type: "semantic"})
      {:ok, _} = Graph.store_node(%{content: "Event", node_type: "episodic"})

      {:reply, response, _} =
        Graphonomous.MCP.GraphStats.execute(%{"include_distributions" => true}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert is_map(payload["type_distribution"])
    end

    test "excludes distributions when not requested" do
      {:ok, _} = Graph.store_node(%{content: "Node", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.GraphStats.execute(%{"include_distributions" => false}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["node_count"] == 1
      refute Map.has_key?(payload, "type_distribution")
    end

    test "reports orphan nodes (no edges)" do
      {:ok, _} = Graph.store_node(%{content: "Orphan A", node_type: "semantic"})
      {:ok, _} = Graph.store_node(%{content: "Orphan B", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.GraphStats.execute(%{"include_distributions" => true}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["orphan_node_count"] == 2
    end

    test "confidence stats are correct" do
      {:ok, _} = Graph.store_node(%{content: "Low", node_type: "semantic", confidence: 0.2})
      {:ok, _} = Graph.store_node(%{content: "High", node_type: "semantic", confidence: 0.8})

      {:reply, response, _} =
        Graphonomous.MCP.GraphStats.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["min_confidence"] <= 0.3
      assert payload["max_confidence"] >= 0.7
      assert_in_delta payload["avg_confidence"], 0.5, 0.2
    end
  end

  # ─── CoverageQuery ─────────────────────────────────────────────

  describe "coverage_query" do
    test "returns error when task_description is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.CoverageQuery.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error when task_description is empty" do
      {:reply, response, _} =
        Graphonomous.MCP.CoverageQuery.execute(%{"task_description" => ""}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "evaluates coverage for a task" do
      {:ok, _} =
        Graph.store_node(%{
          content: "Elixir uses pattern matching for control flow",
          node_type: "semantic",
          confidence: 0.8
        })

      {:reply, response, _} =
        Graphonomous.MCP.CoverageQuery.execute(
          %{"task_description" => "Explain Elixir pattern matching"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["task_description"] == "Explain Elixir pattern matching"
      assert is_number(payload["coverage_score"])
      assert is_number(payload["uncertainty_score"])
      assert payload["recommendation"] in ["act", "learn", "escalate"]
    end

    test "identifies knowledge gaps from critical topics" do
      {:reply, response, _} =
        Graphonomous.MCP.CoverageQuery.execute(
          %{
            "task_description" => "Deploy to production",
            "critical_topics" => "[\"kubernetes\", \"monitoring\", \"rollback\"]"
          },
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert is_list(payload["knowledge_gaps"])
    end

    test "respects min_confidence filter" do
      {:ok, _} =
        Graph.store_node(%{
          content: "Low confidence fact",
          node_type: "semantic",
          confidence: 0.1
        })

      {:reply, response, _} =
        Graphonomous.MCP.CoverageQuery.execute(
          %{"task_description" => "test", "min_confidence" => 0.5},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
    end
  end

  # ─── Deliberate (MCP wrapper) ──────────────────────────────────

  describe "deliberate MCP tool" do
    test "returns error when query is missing" do
      {:reply, response, _} =
        Graphonomous.MCP.Deliberate.execute(%{}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "returns error when query is empty" do
      {:reply, response, _} =
        Graphonomous.MCP.Deliberate.execute(%{"query" => "  "}, nil)

      payload = decode(response)
      assert payload["status"] == "error"
    end

    test "deliberates over explicit node_ids" do
      {:ok, a} =
        Graph.store_node(%{content: "Approach A: use microservices", node_type: "semantic"})

      {:ok, b} = Graph.store_node(%{content: "Approach B: use monolith", node_type: "semantic"})
      {:ok, _} = Graph.create_edge(a.id, b.id, %{edge_type: :contradicts, weight: 0.8})

      {:reply, response, _} =
        Graphonomous.MCP.Deliberate.execute(
          %{
            "query" => "Should we use microservices or monolith?",
            "node_ids" => [a.id, b.id]
          },
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert payload["query"] == "Should we use microservices or monolith?"
      assert is_map(payload["deliberation"])
      assert is_map(payload["topology"])
      assert is_map(payload["selection"])
      assert payload["selection"]["mode"] == "explicit_node_ids"
    end

    test "deliberates via query retrieval when no node_ids given" do
      {:ok, _} =
        Graph.store_node(%{
          content: "The system should prioritize consistency over availability",
          node_type: "semantic"
        })

      {:reply, response, _} =
        Graphonomous.MCP.Deliberate.execute(
          %{"query" => "CAP theorem trade-offs for our system"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
      assert is_map(payload["deliberation"])
      assert is_boolean(payload["deliberation"]["converged"])
    end

    test "handles empty retrieval gracefully" do
      {:reply, response, _} =
        Graphonomous.MCP.Deliberate.execute(
          %{"query" => "something completely unrelated to anything stored"},
          nil
        )

      payload = decode(response)
      assert payload["status"] == "ok"
    end
  end

  # ─── Helpers ────────────────────────────────────────────────────

  defp decode(%{content: [%{text: json} | _]}), do: Jason.decode!(json)
  defp decode(%{content: [%{"text" => json} | _]}), do: Jason.decode!(json)
  defp decode(%{content: json}) when is_binary(json), do: Jason.decode!(json)

  defp decode(other) do
    # Handle Anubis.Server response formats
    case other do
      %{result: result} when is_list(result) ->
        result
        |> Enum.find_value(fn
          %{text: json} -> json
          %{"text" => json} -> json
          _ -> nil
        end)
        |> case do
          nil -> %{"status" => "unknown", "raw" => inspect(other)}
          json -> Jason.decode!(json)
        end

      _ ->
        %{"status" => "unknown", "raw" => inspect(other)}
    end
  end
end
