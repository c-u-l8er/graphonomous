defmodule Graphonomous.Algorithms.LouvainTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.Louvain

  # Helper: build undirected weighted adjacency from edge list
  defp undirected_adj(edges) do
    Enum.reduce(edges, %{}, fn {u, v, w}, acc ->
      acc
      |> Map.update(u, [{v, w}], fn existing -> [{v, w} | existing] end)
      |> Map.update(v, [{u, w}], fn existing -> [{u, w} | existing] end)
    end)
  end

  describe "detect/2" do
    test "empty graph returns empty communities" do
      assert {:ok, %{}} = Louvain.detect(%{})
    end

    test "single node gets community 0" do
      adj = %{"a" => []}
      assert {:ok, %{"a" => 0}} = Louvain.detect(adj)
    end

    test "two connected nodes end up in same community" do
      adj = undirected_adj([{"a", "b", 1.0}])
      assert {:ok, comm} = Louvain.detect(adj)
      assert comm["a"] == comm["b"]
    end

    test "two disconnected cliques get different communities" do
      # Clique 1: a-b-c fully connected
      # Clique 2: x-y-z fully connected
      adj =
        undirected_adj([
          {"a", "b", 1.0},
          {"a", "c", 1.0},
          {"b", "c", 1.0},
          {"x", "y", 1.0},
          {"x", "z", 1.0},
          {"y", "z", 1.0}
        ])

      assert {:ok, comm} = Louvain.detect(adj)

      # Within clique: same community
      assert comm["a"] == comm["b"]
      assert comm["a"] == comm["c"]
      assert comm["x"] == comm["y"]
      assert comm["x"] == comm["z"]

      # Between cliques: different communities
      assert comm["a"] != comm["x"]
    end

    test "weakly connected cliques separate into communities" do
      # Two cliques connected by a single weak edge
      adj =
        undirected_adj([
          {"a", "b", 5.0},
          {"a", "c", 5.0},
          {"b", "c", 5.0},
          {"x", "y", 5.0},
          {"x", "z", 5.0},
          {"y", "z", 5.0},
          {"c", "x", 0.1}
        ])

      assert {:ok, comm} = Louvain.detect(adj)

      # Strong intra-clique ties should dominate
      assert comm["a"] == comm["b"]
      assert comm["a"] == comm["c"]
      assert comm["x"] == comm["y"]
      assert comm["x"] == comm["z"]
      assert comm["a"] != comm["x"]
    end

    test "all nodes assigned a community" do
      adj =
        undirected_adj([
          {"a", "b", 1.0},
          {"b", "c", 1.0},
          {"c", "d", 1.0}
        ])

      assert {:ok, comm} = Louvain.detect(adj)
      assert Map.has_key?(comm, "a")
      assert Map.has_key?(comm, "b")
      assert Map.has_key?(comm, "c")
      assert Map.has_key?(comm, "d")
    end

    test "community IDs are contiguous from 0" do
      adj =
        undirected_adj([
          {"a", "b", 1.0},
          {"x", "y", 1.0}
        ])

      assert {:ok, comm} = Louvain.detect(adj)
      ids = Map.values(comm) |> Enum.uniq() |> Enum.sort()
      assert ids == Enum.to_list(0..(length(ids) - 1))
    end
  end

  describe "modularity/2" do
    test "all-in-one community on complete graph has positive Q" do
      adj =
        undirected_adj([
          {"a", "b", 1.0},
          {"a", "c", 1.0},
          {"b", "c", 1.0}
        ])

      comm = %{"a" => 0, "b" => 0, "c" => 0}
      q = Louvain.modularity(adj, comm)
      assert q >= 0.0
    end

    test "each-in-own community has Q=0 or negative" do
      adj =
        undirected_adj([
          {"a", "b", 1.0},
          {"b", "c", 1.0}
        ])

      comm = %{"a" => 0, "b" => 1, "c" => 2}
      q = Louvain.modularity(adj, comm)
      assert q <= 0.0
    end

    test "modularity is higher for correct partition than wrong one" do
      adj =
        undirected_adj([
          {"a", "b", 5.0},
          {"a", "c", 5.0},
          {"b", "c", 5.0},
          {"x", "y", 5.0},
          {"x", "z", 5.0},
          {"y", "z", 5.0},
          {"c", "x", 0.1}
        ])

      correct = %{"a" => 0, "b" => 0, "c" => 0, "x" => 1, "y" => 1, "z" => 1}
      wrong = %{"a" => 0, "b" => 1, "c" => 0, "x" => 1, "y" => 0, "z" => 1}

      q_correct = Louvain.modularity(adj, correct)
      q_wrong = Louvain.modularity(adj, wrong)

      assert q_correct > q_wrong
    end
  end
end
