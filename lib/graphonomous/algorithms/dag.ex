defmodule Graphonomous.Algorithms.DAG do
  @moduledoc """
  Topological sort and longest-path computation for directed acyclic graphs.

  ### Topological Sort (Kahn's algorithm)

  Produces a linear ordering of nodes such that for every directed edge u→v,
  u appears before v. Returns `{:error, :cycle_detected}` if the graph
  contains a cycle (caller should verify with Tarjan SCC first, or use this
  as a cycle check).

  O(V + E) time, O(V) space.

  ### Longest Path (DP on topological order)

  Computes the longest path from any source (zero in-degree) to every
  reachable node. Useful for:
    - Causal-chain depth measurement (deepest reasoning path)
    - Pipeline critical-path analysis (AgenTroMatic, OS-008)
    - Spec dependency resolution ordering (SpecPrompt)

  O(V + E) time, O(V) space.

  ### Usage

      adjacency = %{"a" => ["b", "c"], "b" => ["d"], "c" => ["d"]}
      {:ok, order} = DAG.toposort(adjacency)
      #=> ["a", "b", "c", "d"]  (or ["a", "c", "b", "d"])

      {:ok, depths} = DAG.longest_path(adjacency)
      #=> %{"a" => 0, "b" => 1, "c" => 1, "d" => 2}
  """

  @type node_id :: binary()
  @type adjacency :: %{optional(node_id()) => [node_id()]}

  # ── Public API ─────────────���────────────────────────────────

  @doc """
  Topological sort using Kahn's algorithm.

  Accepts adjacency as `%{node_id => [neighbor_id]}` — lists or MapSets.
  Nodes appearing only as targets (not keys) are included automatically.

  Returns `{:ok, [node_id]}` in topological order, or
  `{:error, :cycle_detected}` if a cycle exists.
  """
  @spec toposort(adjacency()) :: {:ok, [node_id()]} | {:error, :cycle_detected}
  def toposort(adjacency) when is_map(adjacency) do
    {universe, adj, in_deg} = prepare(adjacency)

    queue =
      universe
      |> Enum.filter(fn v -> Map.get(in_deg, v, 0) == 0 end)
      |> :queue.from_list()

    kahn(adj, in_deg, queue, [], MapSet.size(universe))
  end

  @doc """
  Longest path from any source node to every reachable node.

  Returns `{:ok, %{node_id => depth}}` where depth is the longest
  incoming path length (sources have depth 0).

  Returns `{:error, :cycle_detected}` if the graph has a cycle.
  """
  @spec longest_path(adjacency()) ::
          {:ok, %{node_id() => non_neg_integer()}} | {:error, :cycle_detected}
  def longest_path(adjacency) when is_map(adjacency) do
    case toposort(adjacency) do
      {:ok, order} ->
        {_universe, adj, _in_deg} = prepare(adjacency)
        depths = Map.new(order, fn v -> {v, 0} end)

        depths =
          Enum.reduce(order, depths, fn u, acc ->
            u_depth = Map.fetch!(acc, u)

            neighbors(adj, u)
            |> Enum.reduce(acc, fn v, acc2 ->
              Map.update!(acc2, v, fn current -> max(current, u_depth + 1) end)
            end)
          end)

        {:ok, depths}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Longest path length (critical path depth) in the DAG.

  Returns `{:ok, max_depth}` or `{:error, :cycle_detected}`.
  Returns `{:ok, 0}` for empty or single-node graphs.
  """
  @spec critical_path_depth(adjacency()) :: {:ok, non_neg_integer()} | {:error, :cycle_detected}
  def critical_path_depth(adjacency) do
    case longest_path(adjacency) do
      {:ok, depths} when map_size(depths) == 0 -> {:ok, 0}
      {:ok, depths} -> {:ok, depths |> Map.values() |> Enum.max()}
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns all source nodes (zero in-degree) in the DAG.
  """
  @spec sources(adjacency()) :: [node_id()]
  def sources(adjacency) when is_map(adjacency) do
    {universe, _adj, in_deg} = prepare(adjacency)
    Enum.filter(universe, fn v -> Map.get(in_deg, v, 0) == 0 end) |> Enum.sort()
  end

  @doc """
  Returns all sink nodes (zero out-degree) in the DAG.
  """
  @spec sinks(adjacency()) :: [node_id()]
  def sinks(adjacency) when is_map(adjacency) do
    {universe, adj, _in_deg} = prepare(adjacency)

    Enum.filter(universe, fn v -> neighbors(adj, v) == [] end) |> Enum.sort()
  end

  # ── Kahn's algorithm ───────────────��────────────────────────

  defp kahn(_adj, _in_deg, _queue, result, expected_count)
       when length(result) == expected_count do
    {:ok, Enum.reverse(result)}
  end

  defp kahn(adj, in_deg, queue, result, expected_count) do
    case :queue.out(queue) do
      {:empty, _} ->
        # Remaining nodes form a cycle
        {:error, :cycle_detected}

      {{:value, node}, queue} ->
        nbrs = neighbors(adj, node)

        {in_deg, queue} =
          Enum.reduce(nbrs, {in_deg, queue}, fn v, {deg, q} ->
            new_deg = Map.get(deg, v, 0) - 1
            deg = Map.put(deg, v, new_deg)
            q = if new_deg == 0, do: :queue.in(v, q), else: q
            {deg, q}
          end)

        kahn(adj, in_deg, queue, [node | result], expected_count)
    end
  end

  # ── Helpers ────────────────────────────────────────���────────

  defp prepare(adjacency) do
    # Normalize MapSets to lists, collect universe, compute in-degrees
    adj =
      Map.new(adjacency, fn {k, v} ->
        {k, if(is_list(v), do: v, else: MapSet.to_list(v))}
      end)

    universe =
      Enum.reduce(adj, MapSet.new(Map.keys(adj)), fn {_u, nbrs}, acc ->
        Enum.reduce(nbrs, acc, fn v, a -> MapSet.put(a, v) end)
      end)

    in_deg =
      Enum.reduce(adj, %{}, fn {_u, nbrs}, acc ->
        Enum.reduce(nbrs, acc, fn v, a ->
          Map.update(a, v, 1, &(&1 + 1))
        end)
      end)

    {universe, adj, in_deg}
  end

  defp neighbors(adj, node) do
    Map.get(adj, node, [])
  end
end
