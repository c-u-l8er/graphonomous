defmodule Graphonomous.Algorithms.Triangles do
  @moduledoc """
  Triangle counting and clustering coefficient computation.

  Counts the number of triangles (3-cliques) in an undirected graph and
  computes local/global clustering coefficients.

  ### Portfolio Reuse

  - **graphonomous**: instrumentation — high clustering indicates well-connected
    knowledge neighborhoods; low clustering may signal isolated knowledge
  - General graph quality metric for consolidation decisions

  ### Complexity

  O(E · sqrt(E)) with the node-iterator approach on sorted-degree adjacency.
  For sparse knowledge graphs this is typically fast.

  ### Usage

      adj = %{"a" => MapSet.new(["b", "c"]), "b" => MapSet.new(["a", "c"]), "c" => MapSet.new(["a", "b"])}
      Triangles.count(adj)           #=> 1
      Triangles.clustering(adj, "a") #=> 1.0
      Triangles.global_clustering(adj) #=> 1.0
  """

  @type node_id :: binary()
  @type adjacency :: %{optional(node_id()) => MapSet.t(node_id())}

  # ── Public API ─────────────────────────────────────────────

  @doc """
  Count the total number of triangles in an undirected graph.

  Adjacency should be symmetric (both directions present).
  Each triangle is counted once.
  """
  @spec count(adjacency()) :: non_neg_integer()
  def count(adjacency) when is_map(adjacency) do
    adj = normalize(adjacency)
    nodes = Map.keys(adj) |> Enum.sort_by(&MapSet.size(Map.get(adj, &1, MapSet.new())))

    # For each edge (u, v) where u < v, count common neighbors w > v.
    # This ensures each triangle {u, v, w} is counted exactly once.
    Enum.reduce(nodes, 0, fn u, total ->
      u_nbrs = Map.get(adj, u, MapSet.new())

      Enum.reduce(u_nbrs, total, fn v, acc ->
        if u < v do
          v_nbrs = Map.get(adj, v, MapSet.new())

          common_gt_v =
            MapSet.intersection(u_nbrs, v_nbrs)
            |> Enum.count(fn w -> w > v end)

          acc + common_gt_v
        else
          acc
        end
      end)
    end)
  end

  @doc """
  Local clustering coefficient for a specific node.

  C(v) = 2T(v) / (k_v * (k_v - 1))

  where T(v) is the number of triangles containing v, and k_v is its degree.
  Returns 0.0 for nodes with degree < 2.
  """
  @spec clustering(adjacency(), node_id()) :: float()
  def clustering(adjacency, node_id) do
    adj = normalize(adjacency)
    nbrs = Map.get(adj, node_id, MapSet.new())
    k = MapSet.size(nbrs)

    if k < 2 do
      0.0
    else
      # Count triangles at this node: pairs of neighbors that are connected
      nbr_list = MapSet.to_list(nbrs)

      triangles =
        for u <- nbr_list, v <- nbr_list, u < v, reduce: 0 do
          acc ->
            if MapSet.member?(Map.get(adj, u, MapSet.new()), v), do: acc + 1, else: acc
        end

      2.0 * triangles / (k * (k - 1))
    end
  end

  @doc """
  Global clustering coefficient (transitivity).

  C = 3 * (number of triangles) / (number of connected triples)

  Returns 0.0 for graphs with no connected triples.
  """
  @spec global_clustering(adjacency()) :: float()
  def global_clustering(adjacency) do
    adj = normalize(adjacency)
    triangles = count(adj)

    triples =
      Enum.reduce(adj, 0, fn {_node, nbrs}, acc ->
        k = MapSet.size(nbrs)
        acc + div(k * (k - 1), 2)
      end)

    if triples == 0, do: 0.0, else: 3.0 * triangles / triples
  end

  @doc """
  Per-node triangle counts.

  Returns `%{node_id => triangle_count}`.
  """
  @spec per_node(adjacency()) :: %{optional(node_id()) => non_neg_integer()}
  def per_node(adjacency) do
    adj = normalize(adjacency)

    Map.new(adj, fn {node, nbrs} ->
      nbr_list = MapSet.to_list(nbrs)

      t =
        for u <- nbr_list, v <- nbr_list, u < v, reduce: 0 do
          acc ->
            if MapSet.member?(Map.get(adj, u, MapSet.new()), v), do: acc + 1, else: acc
        end

      {node, t}
    end)
  end

  # ── Helpers ────────────────────────────────────────────────

  defp normalize(adj) do
    Map.new(adj, fn {k, v} ->
      {k, if(is_list(v), do: MapSet.new(v), else: v)}
    end)
  end
end
