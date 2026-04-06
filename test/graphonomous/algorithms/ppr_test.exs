defmodule Graphonomous.Algorithms.PPRTest do
  use ExUnit.Case, async: true

  alias Graphonomous.Algorithms.PPR

  describe "compute/3" do
    test "empty adjacency and empty seeds → empty result" do
      assert PPR.compute(%{}, %{}) == %{}
    end

    test "empty seeds on non-empty graph → empty result" do
      adj = %{"a" => MapSet.new(["b"])}
      assert PPR.compute(adj, %{}) == %{}
    end

    test "single-node self-loop → seed gets all mass" do
      adj = %{"a" => MapSet.new()}
      seeds = %{"a" => 1.0}
      probs = PPR.compute(adj, seeds)

      assert Map.keys(probs) == ["a"]
      assert_in_delta probs["a"], 1.0, 1.0e-6
    end

    test "probabilities sum to approximately 1.0" do
      adj = %{
        "a" => MapSet.new(["b", "c"]),
        "b" => MapSet.new(["c"]),
        "c" => MapSet.new(["a"])
      }

      probs = PPR.compute(adj, %{"a" => 1.0})
      total = probs |> Map.values() |> Enum.sum()
      assert_in_delta total, 1.0, 1.0e-3
    end

    test "seed node has highest probability in a small cycle" do
      adj = %{
        "a" => MapSet.new(["b"]),
        "b" => MapSet.new(["c"]),
        "c" => MapSet.new(["a"])
      }

      probs = PPR.compute(adj, %{"a" => 1.0})

      # With α=0.85 and seed=a, node "a" should dominate at convergence.
      assert probs["a"] > probs["b"]
      assert probs["a"] > probs["c"]
    end

    test "distant nodes receive less mass than close ones (chain)" do
      # a → b → c → d; seed on a. Mass should decay along the chain.
      adj = %{
        "a" => MapSet.new(["b"]),
        "b" => MapSet.new(["c"]),
        "c" => MapSet.new(["d"]),
        "d" => MapSet.new()
      }

      # Dangling terminal + single seed causes traveling-wave oscillation;
      # run to convergence rather than relying on default iters.
      probs = PPR.compute(adj, %{"a" => 1.0}, max_iters: 200, tol: 1.0e-8)

      assert probs["a"] > probs["b"]
      assert probs["b"] > probs["c"]
      assert probs["c"] > probs["d"]
    end

    test "dangling nodes conserve probability mass" do
      # "b" is dangling (out-deg 0). Its mass must be redistributed via restart.
      adj = %{
        "a" => MapSet.new(["b"]),
        "b" => MapSet.new()
      }

      probs = PPR.compute(adj, %{"a" => 1.0})
      total = probs |> Map.values() |> Enum.sum()
      assert_in_delta total, 1.0, 1.0e-3
    end

    test "seed weights are L1-normalized internally" do
      adj = %{"a" => MapSet.new(["b"]), "b" => MapSet.new()}
      probs1 = PPR.compute(adj, %{"a" => 1.0, "b" => 1.0})
      probs2 = PPR.compute(adj, %{"a" => 10.0, "b" => 10.0})

      for k <- Map.keys(probs1) do
        assert_in_delta probs1[k], probs2[k], 1.0e-6
      end
    end

    test "alpha=0 gives pure restart distribution" do
      adj = %{
        "a" => MapSet.new(["b"]),
        "b" => MapSet.new(["c"]),
        "c" => MapSet.new()
      }

      probs = PPR.compute(adj, %{"a" => 1.0}, alpha: 0.01)
      # With α→0, p[v] → restart[v]. Seed is "a" alone, so p[a] ≈ 1.
      assert probs["a"] > 0.95
    end

    test "higher alpha spreads mass farther from seed" do
      adj = %{
        "a" => MapSet.new(["b"]),
        "b" => MapSet.new(["c"]),
        "c" => MapSet.new()
      }

      low = PPR.compute(adj, %{"a" => 1.0}, alpha: 0.3)
      high = PPR.compute(adj, %{"a" => 1.0}, alpha: 0.9)

      # Higher damping moves more mass to downstream neighbors.
      assert high["b"] > low["b"]
    end

    test "seed outside adjacency still appears in universe" do
      adj = %{"a" => MapSet.new(["b"])}
      probs = PPR.compute(adj, %{"z" => 1.0})

      assert Map.has_key?(probs, "z")
      assert probs["z"] > 0.0
    end

    test "converges within max_iters on a small graph" do
      adj = %{
        "a" => MapSet.new(["b", "c"]),
        "b" => MapSet.new(["c"]),
        "c" => MapSet.new(["a"])
      }

      # Tight tol should still converge for this small graph.
      probs = PPR.compute(adj, %{"a" => 1.0}, max_iters: 50, tol: 1.0e-8)
      total = probs |> Map.values() |> Enum.sum()
      assert_in_delta total, 1.0, 1.0e-6
    end
  end
end
