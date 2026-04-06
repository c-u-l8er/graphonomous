defmodule Graphonomous.Algorithms.DijkstraTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.Dijkstra

  # ── Test helpers ──────────────────────────────────────────────

  # Build a simple graph from a list of {from, to, weight} tuples.
  # All nodes get default confidence 0.5.
  defp simple_graph(edges) do
    node_ids =
      Enum.flat_map(edges, fn {from, to, _w} -> [from, to] end)
      |> Enum.uniq()

    nodes = Map.new(node_ids, fn id -> {id, %{confidence: 0.5}} end)

    adjacency =
      Enum.reduce(edges, %{}, fn {from, to, weight}, acc ->
        edge_info = %{weight: weight, edge_type: :causal, id: "#{from}->#{to}"}
        Map.update(acc, from, [{to, edge_info}], fn existing -> [{to, edge_info} | existing] end)
      end)

    %{nodes: nodes, adjacency: adjacency}
  end

  # Fixed cost function for deterministic tests: cost = 1/weight
  defp unit_cost(edge, _target_node, _opts) do
    w = Map.get(edge, :weight, 0.5)
    if w > 0, do: 1.0 / w, else: 1000.0
  end

  # ── shortest_path/4 ──────────────────────────────────────────

  describe "shortest_path/4" do
    test "source == target returns zero-cost trivial path" do
      graph = simple_graph([{"a", "b", 0.8}])
      assert {:ok, %{path: ["a"], cost: 0.0, edges: []}} = Dijkstra.shortest_path(graph, "a", "a")
    end

    test "source not in graph returns error" do
      graph = simple_graph([{"a", "b", 0.8}])
      assert {:error, :source_not_found} = Dijkstra.shortest_path(graph, "z", "b")
    end

    test "target not in graph returns error" do
      graph = simple_graph([{"a", "b", 0.8}])
      assert {:error, :target_not_found} = Dijkstra.shortest_path(graph, "a", "z")
    end

    test "no path returns error" do
      # b has no outgoing edges to c
      graph = simple_graph([{"a", "b", 0.8}, {"c", "d", 0.5}])
      assert {:error, :no_path} = Dijkstra.shortest_path(graph, "a", "d")
    end

    test "direct edge finds single-hop path" do
      graph = simple_graph([{"a", "b", 0.9}])

      assert {:ok, result} =
               Dijkstra.shortest_path(graph, "a", "b", cost_fn: &unit_cost/3)

      assert result.path == ["a", "b"]
      assert length(result.edges) == 1
      assert_in_delta result.cost, 1.0 / 0.9, 0.001
    end

    test "chooses lower-cost path over higher-cost" do
      # a→b→d (via high-weight edges) vs a→c→d (via low-weight edges)
      graph =
        simple_graph([
          {"a", "b", 0.9},
          {"b", "d", 0.9},
          {"a", "c", 0.1},
          {"c", "d", 0.1}
        ])

      assert {:ok, result} =
               Dijkstra.shortest_path(graph, "a", "d", cost_fn: &unit_cost/3)

      # High-weight path: cost = 1/0.9 + 1/0.9 ≈ 2.22
      # Low-weight path: cost = 1/0.1 + 1/0.1 = 20.0
      assert result.path == ["a", "b", "d"]
    end

    test "multi-hop chain finds correct path" do
      graph =
        simple_graph([
          {"a", "b", 0.8},
          {"b", "c", 0.7},
          {"c", "d", 0.6},
          {"d", "e", 0.5}
        ])

      assert {:ok, result} =
               Dijkstra.shortest_path(graph, "a", "e", cost_fn: &unit_cost/3)

      assert result.path == ["a", "b", "c", "d", "e"]
      assert length(result.edges) == 4
    end

    test "diamond graph picks cheaper path" do
      #   a
      #  / \
      # b   c
      #  \ /
      #   d
      graph =
        simple_graph([
          {"a", "b", 0.5},
          {"a", "c", 0.9},
          {"b", "d", 0.5},
          {"c", "d", 0.9}
        ])

      assert {:ok, result} =
               Dijkstra.shortest_path(graph, "a", "d", cost_fn: &unit_cost/3)

      # a→c→d: 1/0.9 + 1/0.9 ≈ 2.22
      # a→b→d: 1/0.5 + 1/0.5 = 4.0
      assert result.path == ["a", "c", "d"]
    end
  end

  # ── default_cost/3 ───────────────────────────────────────────

  describe "default_cost/3" do
    test "higher confidence edge has lower cost" do
      high = %{weight: 0.9, edge_type: :causal}
      low = %{weight: 0.1, edge_type: :causal}
      node = %{confidence: 0.5}
      opts = [now: ~U[2026-01-01 00:00:00Z]]

      cost_high = Dijkstra.default_cost(high, node, opts)
      cost_low = Dijkstra.default_cost(low, node, opts)

      assert cost_high < cost_low
    end

    test "causal edge is cheaper than contradicts edge" do
      causal = %{weight: 0.5, edge_type: :causal}
      contradicts = %{weight: 0.5, edge_type: :contradicts}
      node = %{confidence: 0.5}
      opts = [now: ~U[2026-01-01 00:00:00Z]]

      assert Dijkstra.default_cost(causal, node, opts) <
               Dijkstra.default_cost(contradicts, node, opts)
    end

    test "recent edge is cheaper than old edge" do
      now = ~U[2026-04-06 00:00:00Z]
      recent = %{weight: 0.5, edge_type: :causal, last_activated_at: ~U[2026-04-05 00:00:00Z]}
      old = %{weight: 0.5, edge_type: :causal, last_activated_at: ~U[2025-01-01 00:00:00Z]}
      node = %{confidence: 0.5}
      opts = [now: now, half_life_hours: 168.0]

      assert Dijkstra.default_cost(recent, node, opts) <
               Dijkstra.default_cost(old, node, opts)
    end

    test "nil timestamp contributes zero recency cost" do
      edge = %{weight: 0.5, edge_type: :causal, last_activated_at: nil}
      node = %{}
      opts = [now: ~U[2026-01-01 00:00:00Z]]

      cost = Dijkstra.default_cost(edge, node, opts)
      # -log(0.5) + 0 (recency) + 0 (causal type cost)
      expected = -:math.log(0.5) + 0.0 + 0.0
      assert_in_delta cost, expected, 0.001
    end

    test "all costs are non-negative (Dijkstra invariant)" do
      for weight <- [0.01, 0.1, 0.5, 0.9, 1.0],
          type <- [:causal, :contradicts, :related, :supports, :derived_from] do
        edge = %{weight: weight, edge_type: type}
        cost = Dijkstra.default_cost(edge, %{}, now: ~U[2026-01-01 00:00:00Z])
        assert cost >= 0.0, "cost should be non-negative for weight=#{weight}, type=#{type}"
      end
    end
  end

  # ── k_shortest_paths/4 ──────────────────────────────────────

  describe "k_shortest_paths/4" do
    test "k=1 returns same result as shortest_path" do
      graph = simple_graph([{"a", "b", 0.9}, {"b", "c", 0.8}])

      assert {:ok, [single]} =
               Dijkstra.k_shortest_paths(graph, "a", "c", k: 1, cost_fn: &unit_cost/3)

      assert {:ok, direct} =
               Dijkstra.shortest_path(graph, "a", "c", cost_fn: &unit_cost/3)

      assert single.path == direct.path
      assert_in_delta single.cost, direct.cost, 0.001
    end

    test "finds multiple distinct paths" do
      # Two paths: a→b→d and a→c→d
      graph =
        simple_graph([
          {"a", "b", 0.9},
          {"a", "c", 0.8},
          {"b", "d", 0.9},
          {"c", "d", 0.8}
        ])

      assert {:ok, paths} =
               Dijkstra.k_shortest_paths(graph, "a", "d", k: 2, cost_fn: &unit_cost/3)

      assert length(paths) == 2
      [first, second] = paths
      assert first.cost <= second.cost
      assert first.path != second.path
    end

    test "returns fewer than k when not enough paths exist" do
      graph = simple_graph([{"a", "b", 0.9}])

      assert {:ok, paths} =
               Dijkstra.k_shortest_paths(graph, "a", "b", k: 5, cost_fn: &unit_cost/3)

      assert length(paths) >= 1
      assert length(paths) <= 5
    end

    test "paths are sorted by ascending cost" do
      graph =
        simple_graph([
          {"a", "b", 0.9},
          {"a", "c", 0.5},
          {"a", "d", 0.3},
          {"b", "e", 0.9},
          {"c", "e", 0.5},
          {"d", "e", 0.3}
        ])

      assert {:ok, paths} =
               Dijkstra.k_shortest_paths(graph, "a", "e", k: 3, cost_fn: &unit_cost/3)

      costs = Enum.map(paths, & &1.cost)
      assert costs == Enum.sort(costs)
    end

    test "no path returns error" do
      graph = simple_graph([{"a", "b", 0.8}])
      assert {:error, :no_path} = Dijkstra.k_shortest_paths(graph, "b", "a", k: 3)
    end
  end

  # ── build_graph/2 ────────────────────────────────────────────

  describe "build_graph/2" do
    test "builds from node and edge lists" do
      nodes = [
        %{id: "a", confidence: 0.9},
        %{id: "b", confidence: 0.7}
      ]

      edges = [
        %{source_id: "a", target_id: "b", weight: 0.8, edge_type: :causal}
      ]

      graph = Dijkstra.build_graph(nodes, edges)

      assert Map.has_key?(graph.nodes, "a")
      assert Map.has_key?(graph.nodes, "b")
      assert graph.nodes["a"].confidence == 0.9
      assert [{_target, _edge}] = graph.adjacency["a"]
    end

    test "handles string keys" do
      nodes = [%{"id" => "x", "confidence" => 0.6}]
      edges = [%{"source_id" => "x", "target_id" => "y", "weight" => 0.5}]

      graph = Dijkstra.build_graph(nodes, edges)
      assert Map.has_key?(graph.nodes, "x")
    end
  end

  # ── type_costs/0 ─────────────────────────────────────────────

  describe "type_costs/0" do
    test "causal has zero cost" do
      assert Dijkstra.type_costs()[:causal] == 0.0
    end

    test "contradicts has highest cost" do
      costs = Dijkstra.type_costs()
      max_cost = costs |> Map.values() |> Enum.max()
      assert costs[:contradicts] == max_cost
    end
  end
end
