defmodule Graphonomous.Algorithms.IncrementalSCCTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.IncrementalSCC

  describe "basic operations" do
    test "new state is empty" do
      state = IncrementalSCC.new()
      assert IncrementalSCC.node_count(state) == 0
      assert IncrementalSCC.sccs(state) == []
    end

    test "add_node creates singleton SCC" do
      state = IncrementalSCC.new() |> IncrementalSCC.add_node("a")
      assert IncrementalSCC.node_count(state) == 1
      assert IncrementalSCC.get_scc(state, "a") == MapSet.new(["a"])
    end

    test "add_node is idempotent" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_node("a")
        |> IncrementalSCC.add_node("a")

      assert IncrementalSCC.node_count(state) == 1
    end
  end

  describe "forward edges (no cycles)" do
    test "chain a→b→c creates no multi-node SCCs" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("b", "c")

      assert IncrementalSCC.sccs(state) == []
      assert IncrementalSCC.max_kappa(state) == 0
    end

    test "DAG a→b, a→c, b→c creates no cycles" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("a", "c")
        |> IncrementalSCC.add_edge("b", "c")

      assert IncrementalSCC.sccs(state) == []
    end
  end

  describe "cycle detection and merging" do
    test "simple 2-cycle a→b→a" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("b", "a")

      sccs = IncrementalSCC.sccs(state)
      assert length(sccs) == 1
      assert MapSet.new(["a", "b"]) in sccs
      assert IncrementalSCC.max_kappa(state) == 1
    end

    test "simple 3-cycle a→b→c→a" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("b", "c")
        |> IncrementalSCC.add_edge("c", "a")

      sccs = IncrementalSCC.sccs(state)
      assert length(sccs) == 1
      assert hd(sccs) == MapSet.new(["a", "b", "c"])
      assert IncrementalSCC.max_kappa(state) == 2
    end

    test "get_scc returns same SCC for all cycle members" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("b", "c")
        |> IncrementalSCC.add_edge("c", "a")

      scc_a = IncrementalSCC.get_scc(state, "a")
      scc_b = IncrementalSCC.get_scc(state, "b")
      scc_c = IncrementalSCC.get_scc(state, "c")

      assert scc_a == scc_b
      assert scc_b == scc_c
    end

    test "two separate cycles" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("b", "a")
        |> IncrementalSCC.add_edge("x", "y")
        |> IncrementalSCC.add_edge("y", "x")

      sccs = IncrementalSCC.sccs(state)
      assert length(sccs) == 2
      assert IncrementalSCC.get_scc(state, "a") != IncrementalSCC.get_scc(state, "x")
    end

    test "merging two cycles into one" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")
        |> IncrementalSCC.add_edge("b", "a")
        |> IncrementalSCC.add_edge("c", "d")
        |> IncrementalSCC.add_edge("d", "c")

      # Now connect them into one big cycle: b→c and d→a
      state =
        state
        |> IncrementalSCC.add_edge("b", "c")
        |> IncrementalSCC.add_edge("d", "a")

      sccs = IncrementalSCC.sccs(state)
      assert length(sccs) == 1
      assert hd(sccs) == MapSet.new(["a", "b", "c", "d"])
      assert IncrementalSCC.max_kappa(state) == 3
    end
  end

  describe "edge cases" do
    test "self-loop creates 1-node SCC (kappa 0)" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "a")

      # Self-loops are in the same SCC by definition, but kappa = size - 1 = 0
      assert IncrementalSCC.max_kappa(state) == 0
    end

    test "get_scc for unknown node returns nil" do
      state = IncrementalSCC.new()
      assert IncrementalSCC.get_scc(state, "unknown") == nil
    end

    test "all_sccs includes singletons" do
      state =
        IncrementalSCC.new()
        |> IncrementalSCC.add_edge("a", "b")

      all = IncrementalSCC.all_sccs(state)
      assert length(all) == 2
    end
  end
end
