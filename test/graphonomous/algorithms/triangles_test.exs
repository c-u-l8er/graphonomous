defmodule Graphonomous.Algorithms.TrianglesTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.Triangles

  defp undirected(edges) do
    Enum.reduce(edges, %{}, fn {u, v}, acc ->
      acc
      |> Map.update(u, MapSet.new([v]), &MapSet.put(&1, v))
      |> Map.update(v, MapSet.new([u]), &MapSet.put(&1, u))
    end)
  end

  describe "count/1" do
    test "empty graph has 0 triangles" do
      assert Triangles.count(%{}) == 0
    end

    test "single edge has 0 triangles" do
      adj = undirected([{"a", "b"}])
      assert Triangles.count(adj) == 0
    end

    test "single triangle has 1 triangle" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"a", "c"}])
      assert Triangles.count(adj) == 1
    end

    test "K4 (complete graph on 4 nodes) has 4 triangles" do
      adj = undirected([{"a", "b"}, {"a", "c"}, {"a", "d"}, {"b", "c"}, {"b", "d"}, {"c", "d"}])
      assert Triangles.count(adj) == 4
    end

    test "path graph has 0 triangles" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"c", "d"}])
      assert Triangles.count(adj) == 0
    end

    test "two separate triangles" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"a", "c"}, {"x", "y"}, {"y", "z"}, {"x", "z"}])
      assert Triangles.count(adj) == 2
    end
  end

  describe "clustering/2" do
    test "node in triangle has clustering 1.0" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"a", "c"}])
      assert_in_delta Triangles.clustering(adj, "a"), 1.0, 0.001
    end

    test "center of star has clustering 0.0" do
      adj = undirected([{"a", "b"}, {"a", "c"}, {"a", "d"}])
      assert_in_delta Triangles.clustering(adj, "a"), 0.0, 0.001
    end

    test "node with degree < 2 returns 0.0" do
      adj = undirected([{"a", "b"}])
      assert Triangles.clustering(adj, "a") == 0.0
    end

    test "node not in graph returns 0.0" do
      assert Triangles.clustering(%{}, "z") == 0.0
    end
  end

  describe "global_clustering/1" do
    test "complete graph has global clustering 1.0" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"a", "c"}])
      assert_in_delta Triangles.global_clustering(adj), 1.0, 0.001
    end

    test "star graph has global clustering 0.0" do
      adj = undirected([{"a", "b"}, {"a", "c"}, {"a", "d"}])
      assert_in_delta Triangles.global_clustering(adj), 0.0, 0.001
    end

    test "empty graph has global clustering 0.0" do
      assert Triangles.global_clustering(%{}) == 0.0
    end
  end

  describe "per_node/1" do
    test "returns triangle count per node" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"a", "c"}])
      counts = Triangles.per_node(adj)
      assert counts["a"] == 1
      assert counts["b"] == 1
      assert counts["c"] == 1
    end

    test "node outside triangle has 0" do
      adj = undirected([{"a", "b"}, {"b", "c"}, {"a", "c"}, {"c", "d"}])
      counts = Triangles.per_node(adj)
      assert counts["d"] == 0
      assert counts["c"] == 1
    end
  end
end
