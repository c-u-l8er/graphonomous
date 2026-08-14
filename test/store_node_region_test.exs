defmodule Graphonomous.StoreNodeRegionTest do
  @moduledoc """
  SCOPE (OS-012) blocker #2 regression suite: the optional N-dimensional `region`
  field on knowledge nodes, plus its first real consumer
  (`Graphonomous.nodes_in_region/3` — an N-D Euclidean ball query).
  """
  use ExUnit.Case, async: false

  alias Graphonomous.Store

  setup do
    unless Process.whereis(Store) do
      start_supervised!({Store, db_path: "tmp/graphonomous_test.db"})
    end

    :ok
  end

  test "a node persists, round-trips, and updates its N-D region" do
    node_id = unique_id("node")
    on_exit(fn -> _ = Store.delete_node(node_id) end)

    assert {:ok, inserted} =
             Store.insert_node(%{
               id: node_id,
               content: "Landmark anchored in a 2-D region.",
               node_type: :semantic,
               region: [40.7128, -74.0060]
             })

    assert inserted.region == [40.7128, -74.0060]

    # round-trips through the ETS cache + struct
    assert {:ok, fetched} = Store.get_node(node_id)
    assert fetched.region == [40.7128, -74.0060]

    # update replaces the region; an N-D (here 3-D) vector is fine
    assert {:ok, updated} = Store.update_node(node_id, %{region: [1.0, 2.0, 3.0]})
    assert updated.region == [1.0, 2.0, 3.0]
  end

  test "region defaults to nil and rejects ill-shaped coordinates" do
    bare = store_node!(%{content: "No spatial position."})
    assert is_nil(bare.region)

    # non-numeric / empty coordinates normalize to nil, never a partial vector
    junk = store_node!(%{content: "Bad region.", region: ["x", 2]})
    assert is_nil(junk.region)

    empty = store_node!(%{content: "Empty region.", region: []})
    assert is_nil(empty.region)
  end

  test "nodes_in_region is a real consumer: N-D ball membership, nearest-first" do
    near = store_node!(%{content: "near origin", region: [0.0, 0.0]})
    mid = store_node!(%{content: "one unit east", region: [1.0, 0.0]})
    far = store_node!(%{content: "far away", region: [10.0, 10.0]})
    _none = store_node!(%{content: "no region at all"})
    # wrong dimensionality must be excluded (fail-closed shape check)
    _three_d = store_node!(%{content: "3-D point", region: [0.0, 0.0, 0.0]})

    on_exit(fn ->
      Enum.each([near, mid, far], fn n -> _ = Store.delete_node(n.id) end)
    end)

    results = Graphonomous.nodes_in_region([0.0, 0.0], 2.0)
    ids = Enum.map(results, fn {node, _d} -> node.id end)

    # the near (d=0) and mid (d=1) nodes are inside radius 2.0; far/none/3-D are not
    assert near.id in ids
    assert mid.id in ids
    refute far.id in ids

    # sorted nearest-first, with correct Euclidean distances
    assert [{first, d0}, {second, d1} | _] = results
    assert first.id == near.id
    assert second.id == mid.id
    assert_in_delta d0, 0.0, 1.0e-9
    assert_in_delta d1, 1.0, 1.0e-9
  end

  test "nodes_in_region honors the :limit option" do
    a = store_node!(%{content: "a", region: [0.0]})
    b = store_node!(%{content: "b", region: [0.5]})
    c = store_node!(%{content: "c", region: [1.0]})

    on_exit(fn -> Enum.each([a, b, c], fn n -> _ = Store.delete_node(n.id) end) end)

    results = Graphonomous.nodes_in_region([0.0], 5.0, limit: 2)
    assert length(results) == 2
    # nearest two are a (0.0) then b (0.5)
    assert [{first, _}, {second, _}] = results
    assert first.id == a.id
    assert second.id == b.id
  end

  defp store_node!(attrs) do
    attrs = Map.put_new(attrs, :id, unique_id("node"))
    {:ok, node} = Store.insert_node(attrs)
    on_exit(fn -> _ = Store.delete_node(node.id) end)
    node
  end

  defp unique_id(prefix) do
    "#{prefix}_#{System.unique_integer([:positive])}"
  end
end
