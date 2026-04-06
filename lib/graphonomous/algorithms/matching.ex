defmodule Graphonomous.Algorithms.Matching do
  @moduledoc """
  Bipartite matching algorithms for assignment problems.

  ### Hungarian Algorithm (Kuhn-Munkres)

  Computes a minimum-cost perfect or maximum-weight matching on a bipartite
  graph. Suitable for weighted assignment problems.

  O(n^3) time where n = max(|left|, |right|).

  ### Hopcroft-Karp

  Computes maximum cardinality matching on an unweighted bipartite graph.
  O(E * sqrt(V)) time.

  ### Portfolio Reuse

  - **FleetPrompt**: agent → task assignment (skill match + load + SLA cost)
  - **GeoFleetic**: vehicle → job assignment (distance + capacity)
  - **AgenTroMatic**: orchestrator → subtask routing

  ### Usage

      # Weighted: Hungarian
      cost_matrix = %{
        {"agent1", "task1"} => 3.0,
        {"agent1", "task2"} => 5.0,
        {"agent2", "task1"} => 7.0,
        {"agent2", "task2"} => 1.0,
      }
      {:ok, assignment} = Matching.hungarian(cost_matrix)
      #=> [{"agent2", "task2"}, {"agent1", "task1"}]

      # Unweighted: Hopcroft-Karp
      adj = %{"a1" => ["t1", "t2"], "a2" => ["t2", "t3"]}
      {:ok, matching} = Matching.hopcroft_karp(adj)
      #=> [{"a1", "t1"}, {"a2", "t2"}]
  """

  @type node_id :: binary()
  @type assignment :: [{node_id(), node_id()}]

  @infinity 1.0e18

  # ── Hopcroft-Karp (unweighted max cardinality) ────────────

  @doc """
  Maximum cardinality matching on an unweighted bipartite graph.

  `adjacency` maps left-side nodes to their list of right-side neighbors.
  Returns `{:ok, [{left, right}]}`.
  """
  @spec hopcroft_karp(%{node_id() => [node_id()]}) :: {:ok, assignment()}
  def hopcroft_karp(adjacency) when is_map(adjacency) do
    adj = normalize_adj(adjacency)
    # match_l: left → right, match_r: right → left
    match_l = %{}
    match_r = %{}

    {match_l, _match_r} = hk_loop(adj, match_l, match_r)
    {:ok, Enum.map(match_l, fn {l, r} -> {l, r} end)}
  end

  defp hk_loop(adj, match_l, match_r) do
    # BFS to find layered graph of augmenting paths
    left_free = Map.keys(adj) |> Enum.reject(&Map.has_key?(match_l, &1))

    case hk_bfs(left_free, adj, match_l, match_r) do
      {false, _layers} ->
        {match_l, match_r}

      {true, layers} ->
        {match_l, match_r} =
          Enum.reduce(left_free, {match_l, match_r}, fn u, {ml, mr} ->
            case hk_dfs(u, adj, ml, mr, layers) do
              {:ok, ml2, mr2} -> {ml2, mr2}
              :fail -> {ml, mr}
            end
          end)

        hk_loop(adj, match_l, match_r)
    end
  end

  defp hk_bfs(left_free, adj, match_l, match_r) do
    # BFS from free left nodes, alternating matched/unmatched edges
    layers = Map.new(left_free, fn u -> {u, 0} end)
    queue = :queue.from_list(left_free)
    found_augmenting = false

    bfs_step(queue, adj, match_l, match_r, layers, found_augmenting)
  end

  defp bfs_step(queue, adj, match_l, match_r, layers, found) do
    case :queue.out(queue) do
      {:empty, _} ->
        {found, layers}

      {{:value, u}, queue} ->
        u_layer = Map.fetch!(layers, u)

        Map.get(adj, u, [])
        |> Enum.reduce({queue, layers, found}, fn v, {q, lay, f} ->
          case Map.get(match_r, v) do
            nil ->
              # v is free on right side — augmenting path found
              {q, lay, true}

            matched_left when matched_left != u ->
              if Map.has_key?(lay, matched_left) do
                {q, lay, f}
              else
                lay = Map.put(lay, matched_left, u_layer + 1)
                q = :queue.in(matched_left, q)
                {q, lay, f}
              end

            _ ->
              {q, lay, f}
          end
        end)
        |> then(fn {q, lay, f} -> bfs_step(q, adj, match_l, match_r, lay, f) end)
    end
  end

  defp hk_dfs(u, adj, match_l, match_r, layers) do
    u_layer = Map.get(layers, u, 0)

    Map.get(adj, u, [])
    |> Enum.reduce_while(:fail, fn v, _acc ->
      case Map.get(match_r, v) do
        nil ->
          # Augment: match u-v
          {:halt, {:ok, Map.put(match_l, u, v), Map.put(match_r, v, u)}}

        matched_left ->
          if Map.get(layers, matched_left, -1) == u_layer + 1 do
            case hk_dfs(matched_left, adj, match_l, match_r, layers) do
              {:ok, ml2, mr2} ->
                {:halt, {:ok, Map.put(ml2, u, v), Map.put(mr2, v, u)}}

              :fail ->
                {:cont, :fail}
            end
          else
            {:cont, :fail}
          end
      end
    end)
  end

  # ── Hungarian Algorithm (weighted min-cost) ────────────────

  @doc """
  Minimum-cost assignment on a weighted bipartite graph.

  `cost_matrix` maps `{left, right}` pairs to costs (floats).
  Missing pairs are treated as infinite cost.

  Returns `{:ok, [{left, right}]}` with the minimum total cost assignment,
  or `{:ok, []}` if no valid assignment exists.

  For maximum-weight matching, negate the costs.
  """
  @spec hungarian(%{{node_id(), node_id()} => float()}) :: {:ok, assignment()}
  def hungarian(cost_matrix) when is_map(cost_matrix) do
    {left_nodes, right_nodes} = extract_sides(cost_matrix)
    n = max(length(left_nodes), length(right_nodes))

    if n == 0 do
      {:ok, []}
    else
      # Pad to square matrix, build indexed arrays
      left_idx = Enum.with_index(left_nodes) |> Map.new()
      right_idx = Enum.with_index(right_nodes) |> Map.new()
      left_by_idx = Map.new(left_idx, fn {k, v} -> {v, k} end)
      right_by_idx = Map.new(right_idx, fn {k, v} -> {v, k} end)

      # Build n×n cost matrix (0-indexed)
      matrix =
        for i <- 0..(n - 1), into: %{} do
          row =
            for j <- 0..(n - 1), into: %{} do
              l = Map.get(left_by_idx, i)
              r = Map.get(right_by_idx, j)
              cost = if l && r, do: Map.get(cost_matrix, {l, r}, @infinity), else: @infinity
              {j, cost}
            end

          {i, row}
        end

      assignment = do_hungarian(matrix, n)

      pairs =
        assignment
        |> Enum.filter(fn {i, j} ->
          Map.has_key?(left_by_idx, i) and Map.has_key?(right_by_idx, j) and
            Map.get(cost_matrix, {Map.get(left_by_idx, i), Map.get(right_by_idx, j)}) != nil
        end)
        |> Enum.map(fn {i, j} -> {Map.get(left_by_idx, i), Map.get(right_by_idx, j)} end)

      {:ok, pairs}
    end
  end

  # Standard O(n^3) Hungarian algorithm with potentials (Kuhn-Munkres).
  # Faithful translation of the textbook imperative version.
  # 1-indexed: rows 1..n, cols 1..n. p[j] = row assigned to col j (0 = free).
  defp do_hungarian(cost, n) do
    u = :array.new(n + 1, default: 0.0)
    v = :array.new(n + 1, default: 0.0)
    p = :array.new(n + 1, default: 0)

    {_u, _v, p} =
      Enum.reduce(1..n, {u, v, p}, fn i, {u_acc, v_acc, p_acc} ->
        assign_row(cost, n, i, u_acc, v_acc, p_acc)
      end)

    for j <- 1..n, :array.get(j, p) > 0 do
      {:array.get(j, p) - 1, j - 1}
    end
  end

  defp assign_row(cost, n, i, u, v, p) do
    p = :array.set(0, i, p)
    min_v = :array.new(n + 1, default: @infinity)
    used = :array.new(n + 1, default: false)
    way = :array.new(n + 1, default: 0)

    # Shortest augmenting path loop: iterate until we land on a free column
    {u, v, p, _min_v, _used, way, j0} =
      shortest_aug_path(cost, n, 0, u, v, p, min_v, used, way)

    # Trace back the augmenting path updating assignments
    p = trace_back(p, way, j0)
    {u, v, p}
  end

  defp shortest_aug_path(cost, n, j0, u, v, p, min_v, used, way) do
    used = :array.set(j0, true, used)
    i0 = :array.get(j0, p)

    {delta, j1, min_v, way} =
      Enum.reduce(1..n, {@infinity, 0, min_v, way}, fn j, {d, j1, mv, w} ->
        if :array.get(j, used) do
          {d, j1, mv, w}
        else
          c = get_cost(cost, i0, j)
          cur = c - :array.get(i0, u) - :array.get(j, v)

          {mv, w} =
            if cur < :array.get(j, mv) do
              {:array.set(j, cur, mv), :array.set(j, j0, w)}
            else
              {mv, w}
            end

          if :array.get(j, mv) < d do
            {:array.get(j, mv), j, mv, w}
          else
            {d, j1, mv, w}
          end
        end
      end)

    # Update potentials
    {u, v, min_v} =
      Enum.reduce(0..n, {u, v, min_v}, fn j, {ua, va, mva} ->
        if :array.get(j, used) do
          row = :array.get(j, p)
          ua = :array.set(row, :array.get(row, ua) + delta, ua)
          va = :array.set(j, :array.get(j, va) - delta, va)
          {ua, va, mva}
        else
          mva = :array.set(j, :array.get(j, mva) - delta, mva)
          {ua, va, mva}
        end
      end)

    if :array.get(j1, p) != 0 do
      # Column j1 is occupied — continue from j1
      shortest_aug_path(cost, n, j1, u, v, p, min_v, used, way)
    else
      # Column j1 is free — done
      {u, v, p, min_v, used, way, j1}
    end
  end

  # Walk way[] backwards from j0 to col 0, shifting assignments
  defp trace_back(p, way, j0) do
    prev = :array.get(j0, way)
    p = :array.set(j0, :array.get(prev, p), p)
    if prev == 0, do: p, else: trace_back(p, way, prev)
  end

  # 1-indexed cost lookup into 0-indexed matrix map
  defp get_cost(matrix, i, j) do
    Map.get(Map.get(matrix, i - 1, %{}), j - 1, @infinity)
  end

  # ── Helpers ────────────────────────────────────────────────

  defp extract_sides(cost_matrix) do
    {lefts, rights} =
      Enum.reduce(cost_matrix, {MapSet.new(), MapSet.new()}, fn {{l, r}, _cost}, {ls, rs} ->
        {MapSet.put(ls, l), MapSet.put(rs, r)}
      end)

    {MapSet.to_list(lefts) |> Enum.sort(), MapSet.to_list(rights) |> Enum.sort()}
  end

  defp normalize_adj(adjacency) do
    Map.new(adjacency, fn {k, v} ->
      {k, if(is_list(v), do: v, else: MapSet.to_list(v))}
    end)
  end
end
