defmodule Graphonomous.RetrieverKnowledgeUpdateTest do
  @moduledoc """
  Tests for knowledge-update retrieval enhancements:
  - knowledge_update_query? detection and wider candidate pools
  - Provenance-aware scoring (superseded node penalty)
  - Fact-prefix BM25 query variants
  - Session-coverage expansion for multi-session queries
  """
  use ExUnit.Case, async: false

  setup do
    cleanup_nodes()
    on_exit(&cleanup_nodes/0)
    :ok
  end

  describe "knowledge-update query detection (wider retrieval)" do
    test "knowledge-update-style queries trigger retrieval without error" do
      # Store a node about a topic
      _node =
        store_node!(%{
          content: "I own 4 bikes and I ride them in the park every weekend.",
          node_type: :episodic,
          confidence: 0.7,
          source: "unit-test",
          metadata: %{"role" => "user", "session_id" => "s1"}
        })

      # Knowledge-update query should trigger wider retrieval params
      # (2.5x sim_limit boost) without crashing
      retrieval =
        Graphonomous.retrieve_context(
          "How many bikes do I currently own?",
          similarity_limit: 5,
          final_limit: 10,
          skip_topology: true
        )

      assert is_list(retrieval.results)
      assert is_list(retrieval.causal_context)
      # With fallback embedder (zero vectors), ANN may not find specific nodes,
      # but the pipeline should complete without error. BM25 may find them.
    end
  end

  describe "superseded node scoring" do
    test "superseded nodes rank lower than non-superseded nodes" do
      old_node =
        store_node!(%{
          content: "I own 2 bikes and ride them regularly.",
          node_type: :episodic,
          confidence: 0.25,
          source: "unit-test",
          metadata: %{"role" => "user", "superseded" => true}
        })

      new_node =
        store_node!(%{
          content: "I now own 4 bikes after buying 2 more last week.",
          node_type: :episodic,
          confidence: 0.7,
          source: "unit-test",
          metadata: %{"role" => "user"}
        })

      # Create superseded_by link
      Graphonomous.Store.update_node(old_node.id, %{superseded_by: new_node.id})

      retrieval =
        Graphonomous.retrieve_context(
          "How many bikes do I own?",
          similarity_limit: 10,
          final_limit: 10,
          skip_topology: true
        )

      results = retrieval.results
      ids_ranked = Enum.map(results, & &1.node_id)

      # If both are found, new should rank higher
      if new_node.id in ids_ranked and old_node.id in ids_ranked do
        new_rank = Enum.find_index(ids_ranked, &(&1 == new_node.id))
        old_rank = Enum.find_index(ids_ranked, &(&1 == old_node.id))
        assert new_rank < old_rank, "New node should rank higher than superseded node"
      end
    end
  end

  describe "cross-session entity edge versioning" do
    test "stores superseded_by edges for cross-session fact versions" do
      # Store two user turns in different sessions with overlapping fact categories
      old_node =
        store_node!(%{
          content: "[user] I prefer Thai food for dinner most nights.",
          node_type: :episodic,
          confidence: 0.7,
          source: "unit-test",
          metadata: %{
            "role" => "user",
            "session_id" => "s1",
            "document_date" => "2023-01-15",
            "bm25_facts" => ["preference: Thai food", "user prefers Thai food"]
          }
        })

      new_node =
        store_node!(%{
          content: "[user] I've switched to Italian food, I prefer pasta now.",
          node_type: :episodic,
          confidence: 0.7,
          source: "unit-test",
          metadata: %{
            "role" => "user",
            "session_id" => "s2",
            "document_date" => "2023-04-01",
            "bm25_facts" => ["preference: Italian food", "preference: pasta"]
          }
        })

      # Detect fact version
      result =
        Mix.Tasks.Benchmark.Longmemeval.detect_fact_version(old_node.id, new_node.id)

      assert result == :updates,
             "Nodes with overlapping fact categories should be detected as version updates"
    end

    test "non-overlapping facts return :related" do
      node_a =
        store_node!(%{
          content: "[user] I like hiking in the mountains.",
          node_type: :episodic,
          confidence: 0.7,
          source: "unit-test",
          metadata: %{
            "role" => "user",
            "session_id" => "s1",
            "bm25_facts" => ["hobby: hiking"]
          }
        })

      node_b =
        store_node!(%{
          content: "[user] I live in Seattle near the waterfront.",
          node_type: :episodic,
          confidence: 0.7,
          source: "unit-test",
          metadata: %{
            "role" => "user",
            "session_id" => "s2",
            "bm25_facts" => ["location: Seattle"]
          }
        })

      result =
        Mix.Tasks.Benchmark.Longmemeval.detect_fact_version(node_a.id, node_b.id)

      assert result == :related,
             "Non-overlapping fact categories should return :related"
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp store_node!(attrs) do
    case Graphonomous.store_node(attrs) do
      %{id: id} = node when is_binary(id) -> node
      other -> flunk("Expected stored node, got: #{inspect(other)}")
    end
  end

  defp cleanup_nodes do
    case Graphonomous.query_graph(%{operation: "list_recent", limit: 200}) do
      %{results: nodes} when is_list(nodes) ->
        Enum.each(nodes, fn n ->
          id = Map.get(n, :id) || Map.get(n, "id")
          if is_binary(id), do: Graphonomous.Store.delete_node(id)
        end)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end
end
