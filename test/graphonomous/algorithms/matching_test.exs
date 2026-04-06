defmodule Graphonomous.Algorithms.MatchingTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.Matching

  # ── Hopcroft-Karp ────────────────────────────────────────────

  describe "hopcroft_karp/1" do
    test "empty graph returns empty matching" do
      assert {:ok, []} = Matching.hopcroft_karp(%{})
    end

    test "single edge returns that edge" do
      adj = %{"a" => ["x"]}
      assert {:ok, matching} = Matching.hopcroft_karp(adj)
      assert matching == [{"a", "x"}]
    end

    test "perfect matching on 2x2" do
      adj = %{"a" => ["x", "y"], "b" => ["x", "y"]}
      assert {:ok, matching} = Matching.hopcroft_karp(adj)
      assert length(matching) == 2

      lefts = Enum.map(matching, &elem(&1, 0)) |> Enum.sort()
      rights = Enum.map(matching, &elem(&1, 1)) |> Enum.sort()
      assert lefts == ["a", "b"]
      assert rights == ["x", "y"]
    end

    test "maximum matching when perfect not possible" do
      # a can only match x, b can only match x — max matching = 1
      adj = %{"a" => ["x"], "b" => ["x"]}
      assert {:ok, matching} = Matching.hopcroft_karp(adj)
      assert length(matching) == 1
    end

    test "3x3 perfect matching" do
      adj = %{
        "a1" => ["t1", "t2"],
        "a2" => ["t2", "t3"],
        "a3" => ["t1", "t3"]
      }

      assert {:ok, matching} = Matching.hopcroft_karp(adj)
      assert length(matching) == 3

      lefts = Enum.map(matching, &elem(&1, 0)) |> MapSet.new()
      rights = Enum.map(matching, &elem(&1, 1)) |> MapSet.new()
      assert MapSet.size(lefts) == 3
      assert MapSet.size(rights) == 3
    end

    test "handles MapSet adjacency" do
      adj = %{"a" => MapSet.new(["x", "y"])}
      assert {:ok, matching} = Matching.hopcroft_karp(adj)
      assert length(matching) == 1
    end
  end

  # ── Hungarian Algorithm ──────────────────────────────────────

  describe "hungarian/1" do
    test "empty cost matrix returns empty assignment" do
      assert {:ok, []} = Matching.hungarian(%{})
    end

    test "single pair returns that pair" do
      costs = %{{"a", "x"} => 5.0}
      assert {:ok, [{"a", "x"}]} = Matching.hungarian(costs)
    end

    test "2x2 finds minimum cost assignment" do
      costs = %{
        {"a", "x"} => 3.0,
        {"a", "y"} => 5.0,
        {"b", "x"} => 7.0,
        {"b", "y"} => 1.0
      }

      assert {:ok, assignment} = Matching.hungarian(costs)
      assert length(assignment) == 2

      total_cost =
        Enum.reduce(assignment, 0.0, fn pair, acc ->
          acc + Map.get(costs, pair)
        end)

      # Optimal: a→x (3) + b→y (1) = 4
      assert_in_delta total_cost, 4.0, 0.001
    end

    test "3x3 finds optimal assignment" do
      costs = %{
        {"a", "x"} => 9.0,
        {"a", "y"} => 2.0,
        {"a", "z"} => 7.0,
        {"b", "x"} => 6.0,
        {"b", "y"} => 4.0,
        {"b", "z"} => 3.0,
        {"c", "x"} => 5.0,
        {"c", "y"} => 8.0,
        {"c", "z"} => 1.0
      }

      assert {:ok, assignment} = Matching.hungarian(costs)
      assert length(assignment) == 3

      total_cost =
        Enum.reduce(assignment, 0.0, fn pair, acc ->
          acc + Map.get(costs, pair)
        end)

      # Optimal: a→y(2) + b→x(6) + c→z(1) = 9
      assert_in_delta total_cost, 9.0, 0.001
    end

    test "assignment has no repeated left or right nodes" do
      costs = %{
        {"a", "x"} => 1.0,
        {"a", "y"} => 2.0,
        {"b", "x"} => 2.0,
        {"b", "y"} => 1.0
      }

      assert {:ok, assignment} = Matching.hungarian(costs)
      lefts = Enum.map(assignment, &elem(&1, 0))
      rights = Enum.map(assignment, &elem(&1, 1))
      assert length(Enum.uniq(lefts)) == length(lefts)
      assert length(Enum.uniq(rights)) == length(rights)
    end

    test "rectangular matrix (more left than right)" do
      costs = %{
        {"a", "x"} => 1.0,
        {"b", "x"} => 2.0,
        {"c", "x"} => 3.0
      }

      assert {:ok, assignment} = Matching.hungarian(costs)
      # Only 1 right node, so at most 1 assignment
      assert length(assignment) <= 1
    end
  end
end
