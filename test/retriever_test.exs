defmodule Graphonomous.RetrieverTest do
  use ExUnit.Case, async: false

  setup do
    cleanup_nodes()
    on_exit(&cleanup_nodes/0)
    :ok
  end

  test "retrieves ranked semantic context and returns causal_context in rank order" do
    high =
      store_node!(%{
        content: "I prefer PostgreSQL for OLTP workloads and transactional consistency.",
        node_type: :semantic,
        confidence: 0.92,
        source: "unit-test"
      })

    low =
      store_node!(%{
        content: "PostgreSQL can be a good fit for OLTP, depending on constraints.",
        node_type: :semantic,
        confidence: 0.35,
        source: "unit-test"
      })

    _unrelated =
      store_node!(%{
        content: "Redis is great for caching and pub/sub fanout.",
        node_type: :semantic,
        confidence: 0.99,
        source: "unit-test"
      })

    retrieval =
      Graphonomous.retrieve_context(
        "Which database do I prefer for OLTP workloads?",
        similarity_limit: 10,
        final_limit: 10
      )

    results = retrieval.results
    causal_context = retrieval.causal_context

    assert is_list(results)
    assert length(results) >= 2
    assert is_list(causal_context)
    assert causal_context == Enum.map(results, & &1.node_id)

    ids_by_rank = Enum.map(results, & &1.node_id)

    assert high.id in ids_by_rank
    assert low.id in ids_by_rank

    high_rank = Enum.find_index(ids_by_rank, &(&1 == high.id))
    low_rank = Enum.find_index(ids_by_rank, &(&1 == low.id))

    assert is_integer(high_rank)
    assert is_integer(low_rank)
    assert high_rank <= low_rank
  end

  test "expands graph neighborhood so connected nodes appear in retrieval results" do
    seed =
      store_node!(%{
        content: "Tune PostgreSQL for write-heavy transactional traffic.",
        node_type: :procedural,
        confidence: 0.88,
        source: "unit-test"
      })

    neighbor =
      store_node!(%{
        content: "PgBouncer reduces connection churn and stabilizes pool usage.",
        node_type: :procedural,
        confidence: 0.8,
        source: "unit-test"
      })

    _edge =
      Graphonomous.link_nodes(seed.id, neighbor.id, %{
        edge_type: :related,
        weight: 0.9,
        metadata: %{reason: "operationally connected"}
      })

    retrieval =
      Graphonomous.retrieve_context(
        "How should I tune PostgreSQL for transactional traffic?",
        similarity_limit: 5,
        final_limit: 10,
        expansion_hops: 1,
        neighbors_per_node: 5
      )

    results = retrieval.results
    ids = MapSet.new(Enum.map(results, & &1.node_id))

    assert MapSet.member?(ids, seed.id)
    assert MapSet.member?(ids, neighbor.id)

    neighbor_result = Enum.find(results, &(&1.node_id == neighbor.id))
    assert neighbor_result.source in [:neighbor, :seed]
  end

  test "returns useful stats for retrieval execution" do
    _a =
      store_node!(%{
        content: "CockroachDB is useful for geo-distributed SQL workloads.",
        node_type: :semantic,
        confidence: 0.7,
        source: "unit-test"
      })

    _b =
      store_node!(%{
        content: "PostgreSQL remains my default for most OLTP applications.",
        node_type: :semantic,
        confidence: 0.9,
        source: "unit-test"
      })

    retrieval =
      Graphonomous.retrieve_context(
        "default database for OLTP applications",
        similarity_limit: 5,
        final_limit: 5
      )

    assert is_map(retrieval.stats)
    assert retrieval.stats.seed_count >= 1
    assert retrieval.stats.returned >= 1
    assert retrieval.stats.returned == length(retrieval.results)
  end

  defp store_node!(attrs) do
    case Graphonomous.store_node(attrs) do
      %{id: id} = node when is_binary(id) ->
        node

      other ->
        flunk("expected stored node, got: #{inspect(other)}")
    end
  end

  defp cleanup_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        Enum.each(nodes, fn node ->
          _ = Graphonomous.delete_node(node.id)
        end)

      _ ->
        :ok
    end
  end
end
