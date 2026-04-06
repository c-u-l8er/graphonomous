defmodule Graphonomous.Algorithms.IncrementalSCC do
  @moduledoc """
  Incremental SCC maintenance under edge insertions.

  Maintains a topological ordering of the condensation DAG. When a new edge
  is inserted, checks if it creates a cycle (i.e., goes backward in the
  topological order). If so, merges the affected SCCs.

  Based on Bender, Fineman, Gilbert, Tarjan (2016): amortized O(m^{1/2})
  per edge insertion for maintaining SCCs.

  Does NOT support edge deletion efficiently (decremental SCC is harder).
  Graphonomous has near-monotonic edge growth, so insert-only is acceptable.

  ### Motivation

  T3 benchmark showed ~10s cold topology_analyze latency. Incremental
  maintenance avoids full Tarjan re-run on every edge insert.

  ### Usage

      state = IncrementalSCC.new()
      state = IncrementalSCC.add_node(state, "a")
      state = IncrementalSCC.add_node(state, "b")
      state = IncrementalSCC.add_edge(state, "a", "b")
      state = IncrementalSCC.add_edge(state, "b", "a")  # creates cycle!
      IncrementalSCC.get_scc(state, "a")  #=> MapSet<["a", "b"]>
      IncrementalSCC.sccs(state)          #=> [MapSet<["a", "b"]>]
  """

  @type node_id :: binary()
  @type t :: %__MODULE__{
          # node → SCC representative
          rep: %{optional(node_id()) => node_id()},
          # rep → MapSet of nodes in that SCC
          members: %{optional(node_id()) => MapSet.t(node_id())},
          # rep → topological order position (lower = earlier)
          topo_order: %{optional(node_id()) => non_neg_integer()},
          # rep → [rep] forward edges in condensation DAG
          dag_adj: %{optional(node_id()) => MapSet.t(node_id())},
          # full graph adjacency for reachability (node → MapSet<node>)
          adj: %{optional(node_id()) => MapSet.t(node_id())},
          # next topo position counter
          next_pos: non_neg_integer()
        }

  defstruct rep: %{},
            members: %{},
            topo_order: %{},
            dag_adj: %{},
            adj: %{},
            next_pos: 0

  # ── Public API ─────────────────────────────────────────────

  @doc "Create a new empty incremental SCC state."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Add a node (idempotent)."
  @spec add_node(t(), node_id()) :: t()
  def add_node(%__MODULE__{} = state, node_id) do
    if Map.has_key?(state.rep, node_id) do
      state
    else
      %{
        state
        | rep: Map.put(state.rep, node_id, node_id),
          members: Map.put(state.members, node_id, MapSet.new([node_id])),
          topo_order: Map.put(state.topo_order, node_id, state.next_pos),
          adj: Map.put_new(state.adj, node_id, MapSet.new()),
          next_pos: state.next_pos + 1
      }
    end
  end

  @doc """
  Add a directed edge. Creates nodes if they don't exist.
  If the edge creates a cycle, merges the affected SCCs.
  """
  @spec add_edge(t(), node_id(), node_id()) :: t()
  def add_edge(%__MODULE__{} = state, from, to) do
    state = state |> add_node(from) |> add_node(to)

    # Record in full adjacency
    state =
      update_in(state.adj[from], fn existing -> MapSet.put(existing || MapSet.new(), to) end)

    rep_from = find_rep(state, from)
    rep_to = find_rep(state, to)

    cond do
      rep_from == rep_to ->
        # Already in same SCC, no structural change
        state

      topo_pos(state, rep_from) < topo_pos(state, rep_to) ->
        # Forward edge in condensation DAG — no cycle
        dag_adj =
          Map.update(state.dag_adj, rep_from, MapSet.new([rep_to]), &MapSet.put(&1, rep_to))

        %{state | dag_adj: dag_adj}

      true ->
        # Backward edge — find all reps reachable between rep_to and rep_from
        # in the condensation DAG that form the new cycle
        to_merge = find_reps_in_range(state, rep_to, rep_from)
        merge_sccs(state, to_merge)
    end
  end

  @doc "Get the SCC containing a given node."
  @spec get_scc(t(), node_id()) :: MapSet.t(node_id()) | nil
  def get_scc(%__MODULE__{} = state, node_id) do
    case Map.get(state.rep, node_id) do
      nil -> nil
      rep -> Map.get(state.members, rep, MapSet.new())
    end
  end

  @doc "List all SCCs (only those with more than one member, i.e., actual cycles)."
  @spec sccs(t()) :: [MapSet.t(node_id())]
  def sccs(%__MODULE__{} = state) do
    state.members
    |> Map.values()
    |> Enum.filter(&(MapSet.size(&1) > 1))
  end

  @doc "List all SCCs including singletons."
  @spec all_sccs(t()) :: [MapSet.t(node_id())]
  def all_sccs(%__MODULE__{} = state) do
    Map.values(state.members)
  end

  @doc "Number of nodes tracked."
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{} = state), do: map_size(state.rep)

  @doc "Maximum κ (largest SCC size minus 1, or 0 if no cycles)."
  @spec max_kappa(t()) :: non_neg_integer()
  def max_kappa(%__MODULE__{} = state) do
    case sccs(state) do
      [] -> 0
      scc_list -> (scc_list |> Enum.map(&MapSet.size/1) |> Enum.max()) - 1
    end
  end

  # ── Internals ──────────────────────────────────────────────

  defp find_rep(state, node_id) do
    Map.get(state.rep, node_id, node_id)
  end

  defp topo_pos(state, rep) do
    Map.get(state.topo_order, rep, 0)
  end

  # BFS forward from rep_to in the condensation DAG, collecting all reps
  # with topo_order <= topo_pos(rep_from). These are the reps that form
  # the cycle and need to be merged.
  defp find_reps_in_range(state, rep_to, rep_from) do
    max_pos = topo_pos(state, rep_from)

    bfs_dag(
      :queue.from_list([rep_to]),
      MapSet.new([rep_to, rep_from]),
      state,
      max_pos
    )
  end

  defp bfs_dag(queue, visited, state, max_pos) do
    case :queue.out(queue) do
      {:empty, _} ->
        visited

      {{:value, rep}, queue} ->
        neighbors = Map.get(state.dag_adj, rep, MapSet.new())

        {queue, visited} =
          Enum.reduce(neighbors, {queue, visited}, fn nbr, {q, v} ->
            if MapSet.member?(v, nbr) or topo_pos(state, nbr) > max_pos do
              {q, v}
            else
              {:queue.in(nbr, q), MapSet.put(v, nbr)}
            end
          end)

        bfs_dag(queue, visited, state, max_pos)
    end
  end

  # Merge a set of SCC reps into one. The rep with the lowest topo_order wins.
  defp merge_sccs(state, reps_to_merge) do
    reps_list = MapSet.to_list(reps_to_merge)

    # Pick the rep with lowest topo order as the new representative
    new_rep = Enum.min_by(reps_list, &topo_pos(state, &1))
    others = Enum.reject(reps_list, &(&1 == new_rep))

    # Merge members
    merged_members =
      Enum.reduce(reps_list, MapSet.new(), fn rep, acc ->
        MapSet.union(acc, Map.get(state.members, rep, MapSet.new()))
      end)

    # Update rep pointers for all merged nodes
    new_rep_map =
      Enum.reduce(merged_members, state.rep, fn node, acc ->
        Map.put(acc, node, new_rep)
      end)

    # Update members map
    new_members =
      state.members
      |> Map.drop(others)
      |> Map.put(new_rep, merged_members)

    # Merge DAG adjacency: collect all outgoing edges, remove self-references
    merged_dag =
      Enum.reduce(reps_list, MapSet.new(), fn rep, acc ->
        MapSet.union(acc, Map.get(state.dag_adj, rep, MapSet.new()))
      end)
      |> MapSet.difference(reps_to_merge)

    new_dag_adj =
      state.dag_adj
      |> Map.drop(others)
      |> Map.put(new_rep, merged_dag)
      # Also update any incoming edges pointing to merged reps
      |> Map.new(fn {rep, targets} ->
        new_targets =
          targets
          |> MapSet.to_list()
          |> Enum.map(fn t -> if MapSet.member?(reps_to_merge, t), do: new_rep, else: t end)
          |> MapSet.new()
          |> MapSet.delete(rep)

        {rep, new_targets}
      end)

    # Remove topo_order for merged reps (keep new_rep's)
    new_topo = Map.drop(state.topo_order, others)

    %{
      state
      | rep: new_rep_map,
        members: new_members,
        topo_order: new_topo,
        dag_adj: new_dag_adj
    }
  end
end
