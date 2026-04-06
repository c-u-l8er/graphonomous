defmodule Graphonomous.Algorithms.DAGTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.DAG

  # ── toposort/1 ───────────────────────────────────────────────

  describe "toposort/1" do
    test "empty graph returns empty list" do
      assert {:ok, []} = DAG.toposort(%{})
    end

    test "single node with no edges" do
      assert {:ok, ["a"]} = DAG.toposort(%{"a" => []})
    end

    test "linear chain preserves order" do
      adj = %{"a" => ["b"], "b" => ["c"], "c" => ["d"]}
      assert {:ok, order} = DAG.toposort(adj)
      assert order == ["a", "b", "c", "d"]
    end

    test "diamond DAG produces valid ordering" do
      # a → b, a → c, b → d, c → d
      adj = %{"a" => ["b", "c"], "b" => ["d"], "c" => ["d"]}
      assert {:ok, order} = DAG.toposort(adj)

      # a must come before b, c; b and c must come before d
      assert hd(order) == "a"
      assert List.last(order) == "d"
      assert Enum.find_index(order, &(&1 == "b")) < Enum.find_index(order, &(&1 == "d"))
      assert Enum.find_index(order, &(&1 == "c")) < Enum.find_index(order, &(&1 == "d"))
    end

    test "detects simple cycle" do
      adj = %{"a" => ["b"], "b" => ["c"], "c" => ["a"]}
      assert {:error, :cycle_detected} = DAG.toposort(adj)
    end

    test "detects self-loop" do
      adj = %{"a" => ["a"]}
      assert {:error, :cycle_detected} = DAG.toposort(adj)
    end

    test "includes nodes that appear only as targets" do
      adj = %{"a" => ["b", "c"]}
      assert {:ok, order} = DAG.toposort(adj)
      assert length(order) == 3
      assert "b" in order
      assert "c" in order
    end

    test "handles MapSet adjacency" do
      adj = %{"a" => MapSet.new(["b"]), "b" => MapSet.new(["c"])}
      assert {:ok, order} = DAG.toposort(adj)
      assert order == ["a", "b", "c"]
    end

    test "multiple sources are all included" do
      adj = %{"a" => ["c"], "b" => ["c"]}
      assert {:ok, order} = DAG.toposort(adj)
      assert length(order) == 3
      assert List.last(order) == "c"
    end
  end

  # ── longest_path/1 ──────────────────────────────────────────

  describe "longest_path/1" do
    test "empty graph returns empty map" do
      assert {:ok, %{}} = DAG.longest_path(%{})
    end

    test "single node has depth 0" do
      assert {:ok, %{"a" => 0}} = DAG.longest_path(%{"a" => []})
    end

    test "linear chain gives increasing depths" do
      adj = %{"a" => ["b"], "b" => ["c"], "c" => ["d"]}
      assert {:ok, depths} = DAG.longest_path(adj)
      assert depths["a"] == 0
      assert depths["b"] == 1
      assert depths["c"] == 2
      assert depths["d"] == 3
    end

    test "diamond DAG: sink gets depth from longest incoming path" do
      # a→b→d and a→c→d — both paths are length 2
      adj = %{"a" => ["b", "c"], "b" => ["d"], "c" => ["d"]}
      assert {:ok, depths} = DAG.longest_path(adj)
      assert depths["a"] == 0
      assert depths["d"] == 2
    end

    test "asymmetric diamond picks longer path" do
      # a→b→c→d (length 3) and a→d (length 1)
      adj = %{"a" => ["b", "d"], "b" => ["c"], "c" => ["d"]}
      assert {:ok, depths} = DAG.longest_path(adj)
      assert depths["d"] == 3
    end

    test "cycle returns error" do
      adj = %{"a" => ["b"], "b" => ["a"]}
      assert {:error, :cycle_detected} = DAG.longest_path(adj)
    end
  end

  # ── critical_path_depth/1 ───────────────────────────────────

  describe "critical_path_depth/1" do
    test "empty graph has depth 0" do
      assert {:ok, 0} = DAG.critical_path_depth(%{})
    end

    test "linear chain depth equals edge count" do
      adj = %{"a" => ["b"], "b" => ["c"], "c" => ["d"]}
      assert {:ok, 3} = DAG.critical_path_depth(adj)
    end

    test "wide graph has depth 1" do
      adj = %{"a" => ["b", "c", "d", "e"]}
      assert {:ok, 1} = DAG.critical_path_depth(adj)
    end
  end

  # ── sources/1 and sinks/1 ──────────────────────────────────

  describe "sources/1" do
    test "single source" do
      adj = %{"a" => ["b"], "b" => ["c"]}
      assert DAG.sources(adj) == ["a"]
    end

    test "multiple sources" do
      adj = %{"a" => ["c"], "b" => ["c"]}
      assert DAG.sources(adj) == ["a", "b"]
    end
  end

  describe "sinks/1" do
    test "single sink" do
      adj = %{"a" => ["b"], "b" => ["c"]}
      assert DAG.sinks(adj) == ["c"]
    end

    test "multiple sinks" do
      adj = %{"a" => ["b", "c"]}
      assert DAG.sinks(adj) == ["b", "c"]
    end
  end
end
