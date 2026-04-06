defmodule Graphonomous.Algorithms.Louvain do
  @moduledoc """
  Louvain community detection via greedy modularity optimization.

  Finds topical clusters in the knowledge graph. Orthogonal to SCC analysis:
  SCC detects cyclic dependencies, Louvain detects topical communities
  (which may be acyclic).

  ### Algorithm

  Two-phase iterative:
  1. **Local move**: for each node, try reassigning to each neighbor's community;
     accept the move yielding the largest modularity gain ΔQ > 0.
  2. **Coarsen**: collapse each community into a super-node, sum edge weights.
  3. Repeat until no improvement.

  Modularity Q = (1/2m) Σ [A_ij - k_i·k_j/(2m)] δ(c_i, c_j)

  ### Portfolio Reuse

  - **graphonomous**: consolidation (summarize within community),
    forget_by_policy (prune low-importance communities, preserve bridges)
  - **WebHost.Systems**: workspace clustering
  - **MS GraphRAG**: parallels modularity-community design

  ### Complexity

  O(n·log²n) empirically on sparse graphs.

  ### Usage

      adj = %{"a" => [{"b", 1.0}], "b" => [{"a", 1.0}, {"c", 1.0}], "c" => [{"b", 1.0}]}
      {:ok, communities} = Louvain.detect(adj)
      #=> %{"a" => 0, "b" => 0, "c" => 0}
  """

  @type node_id :: binary()
  @type community_id :: non_neg_integer()
  @type weighted_adj :: %{optional(node_id()) => [{node_id(), float()}]}
  @type communities :: %{optional(node_id()) => community_id()}

  @default_max_passes 20
  @default_min_delta 1.0e-6

  # ── Public API ─────────────────────────────────────────────

  @doc """
  Detect communities using the Louvain method.

  `adjacency` maps node IDs to lists of `{neighbor, weight}` tuples.
  Undirected: include both directions. Directed edges are treated as undirected
  by summing weights.

  Options:
    * `:max_passes` - maximum number of Louvain passes. Default #{@default_max_passes}.
    * `:min_delta`  - minimum modularity improvement to continue. Default #{@default_min_delta}.

  Returns `{:ok, %{node_id => community_id}}`.
  """
  @spec detect(weighted_adj(), keyword()) :: {:ok, communities()}
  def detect(adjacency, opts \\ []) when is_map(adjacency) do
    max_passes = Keyword.get(opts, :max_passes, @default_max_passes)
    min_delta = Keyword.get(opts, :min_delta, @default_min_delta)

    # Symmetrize adjacency and build initial state
    sym_adj = symmetrize(adjacency)
    nodes = Map.keys(sym_adj)

    if nodes == [] do
      {:ok, %{}}
    else
      # Initial: each node in its own community
      initial_comm = Map.new(nodes |> Enum.with_index(), fn {n, i} -> {n, i} end)
      m2 = total_weight(sym_adj)

      if m2 == 0.0 do
        {:ok, initial_comm}
      else
        {final_comm, _q} = louvain_loop(sym_adj, initial_comm, m2, max_passes, min_delta)
        {:ok, renumber(final_comm)}
      end
    end
  end

  @doc """
  Compute modularity Q for a given community assignment.

  Q = (1/2m) Σ_{ij} [A_ij - k_i*k_j/(2m)] δ(c_i, c_j)
  """
  @spec modularity(weighted_adj(), communities()) :: float()
  def modularity(adjacency, communities) do
    sym_adj = symmetrize(adjacency)
    m2 = total_weight(sym_adj)
    if m2 == 0.0, do: 0.0, else: compute_modularity(sym_adj, communities, m2)
  end

  # ── Core loop ──────────────────────────────────────────────

  defp louvain_loop(adj, comm, m2, passes_left, min_delta) when passes_left > 0 do
    q_before = compute_modularity(adj, comm, m2)

    # Phase 1: local moves
    {new_comm, improved} = local_move_phase(adj, comm, m2)

    if not improved do
      {comm, q_before}
    else
      q_after = compute_modularity(adj, new_comm, m2)

      if q_after - q_before < min_delta do
        {new_comm, q_after}
      else
        # Phase 2: coarsen
        {coarse_adj, coarse_comm, node_to_supernode} = coarsen(adj, new_comm)

        {final_coarse_comm, final_q} =
          louvain_loop(coarse_adj, coarse_comm, m2, passes_left - 1, min_delta)

        # Map back to original nodes
        final_comm =
          Map.new(comm, fn {node, _} ->
            supernode = Map.fetch!(node_to_supernode, node)
            {node, Map.fetch!(final_coarse_comm, supernode)}
          end)

        {final_comm, final_q}
      end
    end
  end

  defp louvain_loop(_adj, comm, m2, _passes_left, _min_delta) do
    {comm, compute_modularity_fast(comm, m2)}
  end

  # ── Phase 1: Local moves ───────────────────────────────────

  defp local_move_phase(adj, comm, m2) do
    nodes = Map.keys(adj) |> Enum.shuffle()
    k = node_degrees(adj)

    # Precompute community sums (Σ_tot and Σ_in)
    {sigma_tot, sigma_in} = community_sums(adj, comm, k)

    do_local_moves(nodes, adj, comm, m2, k, sigma_tot, sigma_in, false)
  end

  defp do_local_moves([], _adj, comm, _m2, _k, _sigma_tot, _sigma_in, improved) do
    {comm, improved}
  end

  defp do_local_moves([node | rest], adj, comm, m2, k, sigma_tot, sigma_in, improved) do
    current_c = Map.fetch!(comm, node)
    ki = Map.get(k, node, 0.0)
    neighbors = Map.get(adj, node, [])

    # Compute weight to each neighbor community
    neighbor_weights =
      Enum.reduce(neighbors, %{}, fn {nbr, w}, acc ->
        nbr_c = Map.fetch!(comm, nbr)
        Map.update(acc, nbr_c, w, &(&1 + w))
      end)

    # Weight to own community
    ki_in_current = Map.get(neighbor_weights, current_c, 0.0)

    # Try removing node from its community
    # ΔQ_remove = -[ki_in / m2 - sigma_tot * ki / m2^2]
    st_current = Map.get(sigma_tot, current_c, 0.0)

    best =
      Enum.reduce(neighbor_weights, {current_c, 0.0}, fn {target_c, ki_in_target},
                                                         {best_c, best_gain} ->
        if target_c == current_c do
          {best_c, best_gain}
        else
          st_target = Map.get(sigma_tot, target_c, 0.0)

          # Gain from moving node to target_c
          gain =
            (ki_in_target - ki_in_current) / m2 +
              ki * (st_current - ki - st_target) / (m2 * m2)

          if gain > best_gain do
            {target_c, gain}
          else
            {best_c, best_gain}
          end
        end
      end)

    {best_c, best_gain} = best

    if best_gain > 0.0 and best_c != current_c do
      # Move node
      new_comm = Map.put(comm, node, best_c)

      # Update sigma_tot
      new_sigma_tot =
        sigma_tot
        |> Map.update(current_c, 0.0, &(&1 - ki))
        |> Map.update(best_c, ki, &(&1 + ki))

      do_local_moves(rest, adj, new_comm, m2, k, new_sigma_tot, sigma_in, true)
    else
      do_local_moves(rest, adj, comm, m2, k, sigma_tot, sigma_in, improved)
    end
  end

  # ── Phase 2: Coarsen ──────────────────────────────────────

  defp coarsen(adj, comm) do
    # Map each community to a super-node ID (string)
    community_ids = comm |> Map.values() |> Enum.uniq() |> Enum.sort()
    comm_to_super = Map.new(community_ids |> Enum.with_index(), fn {c, i} -> {c, "s#{i}"} end)
    node_to_super = Map.new(comm, fn {node, c} -> {node, Map.fetch!(comm_to_super, c)} end)

    # Build coarsened adjacency
    coarse_adj =
      Enum.reduce(adj, %{}, fn {node, neighbors}, acc ->
        super_node = Map.fetch!(node_to_super, node)

        Enum.reduce(neighbors, acc, fn {nbr, w}, acc2 ->
          super_nbr = Map.fetch!(node_to_super, nbr)

          if super_node == super_nbr do
            # Self-loop in coarsened graph (internal community edge)
            Map.update(acc2, super_node, [{super_node, w}], fn existing ->
              [{super_node, w} | existing]
            end)
          else
            Map.update(acc2, super_node, [{super_nbr, w}], fn existing ->
              [{super_nbr, w} | existing]
            end)
          end
        end)
      end)

    # Merge duplicate edges by summing weights
    coarse_adj =
      Map.new(coarse_adj, fn {sn, edges} ->
        merged =
          Enum.reduce(edges, %{}, fn {target, w}, acc ->
            Map.update(acc, target, w, &(&1 + w))
          end)

        {sn, Enum.map(merged, fn {t, w} -> {t, w} end)}
      end)

    coarse_comm =
      Map.new(coarse_adj |> Map.keys() |> Enum.with_index(), fn {sn, i} -> {sn, i} end)

    {coarse_adj, coarse_comm, node_to_super}
  end

  # ── Modularity computation ────────────────────────────────

  defp compute_modularity(adj, comm, m2) do
    k = node_degrees(adj)

    Enum.reduce(adj, 0.0, fn {u, neighbors}, q ->
      cu = Map.fetch!(comm, u)
      ku = Map.get(k, u, 0.0)

      Enum.reduce(neighbors, q, fn {v, w}, q2 ->
        cv = Map.fetch!(comm, v)

        if cu == cv do
          q2 + (w - ku * Map.get(k, v, 0.0) / m2)
        else
          q2
        end
      end)
    end) / m2
  end

  defp compute_modularity_fast(_comm, _m2), do: 0.0

  # ── Helpers ────────────────────────────────────────────────

  defp symmetrize(adj) do
    Enum.reduce(adj, adj, fn {u, neighbors}, acc ->
      Enum.reduce(neighbors, acc, fn {v, w}, acc2 ->
        Map.update(acc2, v, [{u, w}], fn existing ->
          if Enum.any?(existing, fn {n, _} -> n == u end) do
            existing
          else
            [{u, w} | existing]
          end
        end)
      end)
    end)
  end

  defp total_weight(adj) do
    Enum.reduce(adj, 0.0, fn {_u, neighbors}, acc ->
      Enum.reduce(neighbors, acc, fn {_v, w}, a -> a + w end)
    end)
  end

  defp node_degrees(adj) do
    Map.new(adj, fn {u, neighbors} ->
      {u, Enum.reduce(neighbors, 0.0, fn {_v, w}, acc -> acc + w end)}
    end)
  end

  defp community_sums(adj, comm, k) do
    sigma_tot =
      Enum.reduce(k, %{}, fn {node, ki}, acc ->
        c = Map.fetch!(comm, node)
        Map.update(acc, c, ki, &(&1 + ki))
      end)

    sigma_in =
      Enum.reduce(adj, %{}, fn {u, neighbors}, acc ->
        cu = Map.fetch!(comm, u)

        Enum.reduce(neighbors, acc, fn {v, w}, acc2 ->
          if Map.get(comm, v) == cu do
            Map.update(acc2, cu, w, &(&1 + w))
          else
            acc2
          end
        end)
      end)

    {sigma_tot, sigma_in}
  end

  defp renumber(comm) do
    id_map =
      comm
      |> Map.values()
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.with_index()
      |> Map.new()

    Map.new(comm, fn {node, c} -> {node, Map.fetch!(id_map, c)} end)
  end
end
