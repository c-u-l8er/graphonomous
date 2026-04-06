defmodule Graphonomous.Algorithms.PPR do
  @moduledoc """
  Personalized PageRank / Random Walk with Restart (RWR).

  Computes the stationary distribution of a random walker that, at each step,
  either follows an out-edge (prob α) or teleports back to the seed
  distribution (prob 1-α). High stationary probability ≈ "graph-centrality
  close to the seeds" — used as an additive retrieval boost.

  ### Algorithm

  Power-method iteration on column-normalized adjacency:

      p_new[v] = (1-α) * restart[v] + α * (Σ_{u→v} p[u] / out_deg(u)
                                            + dangling_mass * restart[v])

  Dangling nodes (out-degree 0) redistribute their mass via the restart
  distribution, preserving total probability mass.

  Early stops when `||p_new - p||_1 < tol`.

  ### Usage

      adjacency = %{"a" => MapSet.new(["b"]), "b" => MapSet.new(["c"])}
      seeds     = %{"a" => 1.0}  # will be L1-normalized
      probs     = Graphonomous.Algorithms.PPR.compute(adjacency, seeds)

  ### Complexity

  O(iters · E) time, O(V) space. Intended for seed-local subgraphs
  (~200 nodes, ~1-2k edges) built from an already-retrieved candidate set.
  """

  @type node_id :: binary()
  @type adjacency :: %{optional(node_id()) => MapSet.t(node_id())}
  @type seed_weights :: %{optional(node_id()) => float()}
  @type probs :: %{optional(node_id()) => float()}

  @default_alpha 0.85
  @default_max_iters 15
  @default_tol 1.0e-4

  @doc """
  Compute the PPR stationary distribution seeded by `seeds`.

  Options:
    * `:alpha`     - damping factor in (0, 1). Default #{@default_alpha}.
    * `:max_iters` - maximum power-method iterations. Default #{@default_max_iters}.
    * `:tol`       - L1 convergence threshold. Default #{@default_tol}.

  Returns a map from node_id to stationary probability (sums to ~1.0).
  Returns an empty map when the universe or seed set is empty.
  """
  @spec compute(adjacency(), seed_weights(), keyword()) :: probs()
  def compute(adjacency, seeds, opts \\ [])
      when is_map(adjacency) and is_map(seeds) and is_list(opts) do
    alpha = clamp_float(Keyword.get(opts, :alpha, @default_alpha), 0.01, 0.99)
    max_iters = max(1, Keyword.get(opts, :max_iters, @default_max_iters))
    tol = max(1.0e-8, Keyword.get(opts, :tol, @default_tol))

    universe = build_universe(adjacency, seeds)

    cond do
      MapSet.size(universe) == 0 -> %{}
      map_size(seeds) == 0 -> %{}
      true -> do_compute(adjacency, seeds, universe, alpha, max_iters, tol)
    end
  end

  defp do_compute(adjacency, seeds, universe, alpha, max_iters, tol) do
    restart = normalize_restart(seeds, universe)
    {out_deg, danglings} = out_degrees_and_danglings(adjacency, universe)
    in_edges = build_in_edges(adjacency, universe)

    Enum.reduce_while(1..max_iters, restart, fn _iter, p ->
      dangling_mass =
        Enum.reduce(danglings, 0.0, fn v, acc -> acc + Map.fetch!(p, v) end)

      p_new =
        Map.new(universe, fn v ->
          inbound =
            in_edges
            |> Map.get(v, [])
            |> Enum.reduce(0.0, fn u, acc ->
              acc + Map.fetch!(p, u) / Map.fetch!(out_deg, u)
            end)

          teleport = Map.fetch!(restart, v)
          val = (1.0 - alpha) * teleport + alpha * (inbound + dangling_mass * teleport)
          {v, val}
        end)

      if l1_delta(p, p_new) < tol do
        {:halt, p_new}
      else
        {:cont, p_new}
      end
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp build_universe(adjacency, seeds) do
    adjacency
    |> Map.keys()
    |> MapSet.new()
    |> then(fn set ->
      Enum.reduce(adjacency, set, fn {_u, nbrs}, acc -> MapSet.union(acc, nbrs) end)
    end)
    |> then(fn set ->
      Enum.reduce(Map.keys(seeds), set, fn k, acc -> MapSet.put(acc, k) end)
    end)
  end

  # L1-normalize seed weights onto the universe. Non-positive weights zeroed.
  defp normalize_restart(seeds, universe) do
    positive =
      seeds
      |> Enum.filter(fn {k, w} -> MapSet.member?(universe, k) and w > 0.0 end)
      |> Map.new()

    total = positive |> Map.values() |> Enum.sum()

    if total <= 0.0 do
      uniform = 1.0 / MapSet.size(universe)
      Map.new(universe, fn v -> {v, uniform} end)
    else
      Map.new(universe, fn v ->
        {v, Map.get(positive, v, 0.0) / total}
      end)
    end
  end

  # Returns {out_deg_map, dangling_set}. out_deg stores max(deg, 1) so callers
  # can safely divide; dangling_set lists nodes with true out-degree 0.
  defp out_degrees_and_danglings(adjacency, universe) do
    Enum.reduce(universe, {%{}, []}, fn v, {od, dg} ->
      deg =
        case Map.get(adjacency, v) do
          nil -> 0
          %MapSet{} = s -> MapSet.size(s)
        end

      od2 = Map.put(od, v, max(deg, 1))
      dg2 = if deg == 0, do: [v | dg], else: dg
      {od2, dg2}
    end)
  end

  defp build_in_edges(adjacency, universe) do
    base = Map.new(universe, fn v -> {v, []} end)

    Enum.reduce(adjacency, base, fn {u, nbrs}, acc ->
      if MapSet.member?(universe, u) do
        Enum.reduce(nbrs, acc, fn v, acc2 ->
          if MapSet.member?(universe, v) do
            Map.update!(acc2, v, fn xs -> [u | xs] end)
          else
            acc2
          end
        end)
      else
        acc
      end
    end)
  end

  defp l1_delta(p_old, p_new) do
    Enum.reduce(p_new, 0.0, fn {v, new_val}, acc ->
      old_val = Map.get(p_old, v, 0.0)
      acc + abs(new_val - old_val)
    end)
  end

  defp clamp_float(x, lo, hi) when is_number(x) do
    x = x / 1.0

    cond do
      x < lo -> lo
      x > hi -> hi
      true -> x
    end
  end

  defp clamp_float(_, lo, _hi), do: lo
end
