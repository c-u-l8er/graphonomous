defmodule Graphonomous.StoreTest do
  use ExUnit.Case, async: false

  alias Graphonomous.Store

  setup do
    unless Process.whereis(Store) do
      start_supervised!({Store, db_path: "tmp/graphonomous_test.db"})
    end

    :ok
  end

  test "connectivity: store responds to ping" do
    assert :pong = Store.ping()
  end

  test "node persistence flow: insert, get, list, update, access, delete" do
    node_id = unique_id("node")

    on_exit(fn ->
      _ = Store.delete_node(node_id)
    end)

    attrs = %{
      id: node_id,
      content: "I prefer PostgreSQL over MySQL for OLTP workloads.",
      node_type: :semantic,
      confidence: 0.72,
      source: "unit_test",
      metadata: %{"topic" => "db"}
    }

    assert {:ok, inserted} = Store.insert_node(attrs)
    assert inserted.id == node_id
    assert inserted.content == attrs.content
    assert inserted.node_type == :semantic
    assert_in_delta inserted.confidence, 0.72, 1.0e-6

    assert {:ok, fetched} = Store.get_node(node_id)
    assert fetched.id == node_id
    assert fetched.content == attrs.content

    assert {:ok, listed} =
             Store.list_nodes(%{
               node_type: :semantic,
               min_confidence: 0.5,
               limit: 100
             })

    assert Enum.any?(listed, &(&1.id == node_id))

    assert {:ok, updated} =
             Store.update_node(node_id, %{
               content: "I strongly prefer PostgreSQL for OLTP.",
               confidence: 0.91,
               metadata: %{"topic" => "db", "updated" => true}
             })

    assert updated.id == node_id
    assert updated.content == "I strongly prefer PostgreSQL for OLTP."
    assert_in_delta updated.confidence, 0.91, 1.0e-6
    assert updated.metadata["updated"] == true

    assert {:ok, touched} = Store.increment_access(node_id)
    assert touched.id == node_id
    assert touched.access_count >= 1

    assert :ok = Store.delete_node(node_id)
    assert {:error, :not_found} = Store.get_node(node_id)
  end

  test "edge and outcome persistence flow" do
    source_id = unique_id("source")
    target_id = unique_id("target")
    action_id = unique_id("action")

    on_exit(fn ->
      _ = Store.delete_node(source_id)
      _ = Store.delete_node(target_id)
    end)

    assert {:ok, _} =
             Store.insert_node(%{
               id: source_id,
               content: "CockroachDB performed better in a recent benchmark.",
               node_type: :episodic,
               confidence: 0.65
             })

    assert {:ok, _} =
             Store.insert_node(%{
               id: target_id,
               content: "Distributed SQL can improve resilience.",
               node_type: :semantic,
               confidence: 0.61
             })

    edge_id = unique_id("edge")

    assert {:ok, edge} =
             Store.upsert_edge(%{
               id: edge_id,
               source_id: source_id,
               target_id: target_id,
               edge_type: :causal,
               weight: 0.88,
               metadata: %{"reason" => "benchmark evidence"}
             })

    assert edge.id == edge_id
    assert edge.source_id == source_id
    assert edge.target_id == target_id
    assert edge.edge_type == :causal
    assert_in_delta edge.weight, 0.88, 1.0e-6

    assert {:ok, edges} = Store.list_edges_for_node(source_id)
    assert Enum.any?(edges, &(&1.id == edge_id))

    assert {:ok, outcome} =
             Store.insert_outcome(%{
               action_id: action_id,
               status: :success,
               confidence: 0.8,
               causal_node_ids: [source_id, target_id],
               evidence: %{"latency_ms" => 42}
             })

    assert outcome.action_id == action_id
    assert outcome.status == :success
    assert outcome.causal_node_ids == [source_id, target_id]

    assert {:ok, outcomes} = Store.list_outcomes(200)

    assert Enum.any?(outcomes, fn o ->
             o.action_id == action_id and
               Enum.sort(o.causal_node_ids) == Enum.sort([source_id, target_id])
           end)
  end

  defp unique_id(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
