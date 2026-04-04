defmodule Graphonomous.Topology do
  @moduledoc """
  κ-aware topology analysis for directed knowledge subgraphs.

  This module provides:

    * Tarjan SCC decomposition (`tarjan_scc/1`)
    * κ computation for SCCs (`compute_kappa/2`)
    * Full routing analysis (`analyze/1`)
    * Deliberation budget mapping (`deliberation_budget/1`)
    * Adjacency construction from node universe + edges (`build_adjacency/2`)
    * Edge-impact preview (`preview_edge_impact/3`)

  Canonical output keys follow the product spec:

    * `:sccs`
    * `:dag_nodes`
    * `:routing`
    * `:max_kappa`
    * `:scc_count`
  """

  import Bitwise

  alias Graphonomous.Types.Edge

  @max_exact_scc_size 10

  @type node_id :: binary()
  @type adjacency :: %{optional(node_id()) => MapSet.t(node_id())}
  @type edge_tuple :: {node_id(), node_id()}

  @type kappa_result :: %{
          kappa: non_neg_integer(),
          approximate: boolean(),
          fault_line_edges: list(edge_tuple())
        }

  @type scc_result :: %{
          id: binary(),
          nodes: list(node_id()),
          kappa: non_neg_integer(),
          approximate: boolean(),
          fault_line_edges: list(%{source: node_id(), target: node_id()}),
          routing: :fast | :deliberate,
          deliberation_budget: map()
        }

  @type analysis_result :: %{
          sccs: list(scc_result()),
          dag_nodes: list(node_id()),
          routing: :fast | :deliberate,
          max_kappa: non_neg_integer(),
          scc_count: non_neg_integer()
        }

  @doc """
  Build directed adjacency from an explicit node universe and edge structs.

  Self-loops are excluded and only edges whose source and target are both in the
  provided `node_ids` set are retained.
  """
  @spec build_adjacency(node_ids :: [binary()], edges :: [Edge.t() | map()]) :: adjacency()
  def build_adjacency(node_ids, edges) when is_list(node_ids) and is_list(edges) do
    node_set = MapSet.new(Enum.filter(node_ids, &is_binary/1))

    base =
      Enum.reduce(node_set, %{}, fn node, acc ->
        Map.put(acc, node, MapSet.new())
      end)

    Enum.reduce(edges, base, fn edge, acc ->
      source_id = map_get(edge, :source_id)
      target_id = map_get(edge, :target_id)

      cond do
        not is_binary(source_id) or not is_binary(target_id) ->
          acc

        source_id == target_id ->
          acc

        not MapSet.member?(node_set, source_id) or not MapSet.member?(node_set, target_id) ->
          acc

        true ->
          Map.update(acc, source_id, MapSet.new([target_id]), &MapSet.put(&1, target_id))
      end
    end)
  end

  @doc """
  Iterative Tarjan SCC decomposition over adjacency map.

  Returns only nontrivial SCCs (size > 1).
  """
  @spec tarjan_scc(adjacency()) :: [MapSet.t(node_id())]
  def tarjan_scc(adjacency) when is_map(adjacency) do
    adjacency = normalize_adjacency(adjacency)
    nodes = adjacency |> Map.keys() |> Enum.sort()

    initial = %{
      index_counter: 0,
      index: %{},
      lowlink: %{},
      stack: [],
      on_stack: MapSet.new(),
      frames: [],
      sccs: []
    }

    {state, _visited_roots} =
      Enum.reduce(nodes, {initial, MapSet.new()}, fn node, {state, visited_roots} ->
        if Map.has_key?(state.index, node) do
          {state, visited_roots}
        else
          state = state |> push_new_frame(node, nil, adjacency) |> process_frames(adjacency)
          {state, MapSet.put(visited_roots, node)}
        end
      end)

    state.sccs
    |> Enum.reverse()
    |> Enum.filter(&(MapSet.size(&1) > 1))
  end

  @doc """
  Compute κ for one SCC in the given adjacency.

  For SCC size > #{@max_exact_scc_size}, returns an approximation:
  `kappa = scc_size`, `approximate = true`, empty fault lines.
  """
  @spec compute_kappa(adjacency(), MapSet.t(node_id())) :: kappa_result()
  def compute_kappa(adjacency, scc_nodes)
      when is_map(adjacency) and is_struct(scc_nodes, MapSet) do
    nodes =
      scc_nodes
      |> MapSet.to_list()
      |> Enum.filter(&is_binary/1)
      |> Enum.sort()

    size = length(nodes)

    cond do
      size <= 1 ->
        %{
          kappa: 0,
          approximate: false,
          fault_line_edges: []
        }

      size > @max_exact_scc_size ->
        %{
          kappa: size,
          approximate: true,
          fault_line_edges: []
        }

      true ->
        exact_kappa(adjacency, nodes)
    end
  end

  @doc """
  Full topology analysis for either:

    * adjacency map (`%{node_id => MapSet.new([...])}`), or
    * edge list (`[{source, target}, ...]`), or
    * edge structs/maps with `source_id`/`target_id`.
  """
  @spec analyze(adjacency() | [edge_tuple() | map()]) :: analysis_result()
  def analyze(edges_or_adjacency) do
    {duration_us, {result, stats}} =
      :timer.tc(fn ->
        adjacency = to_adjacency(edges_or_adjacency)
        result = do_analyze(adjacency)
        {result, graph_stats(adjacency)}
      end)

    emit_analyze_telemetry(result, duration_us, stats.node_count, stats.edge_count)
    emit_route_telemetry(result, :analyze_topology)
    result
  end

  @doc """
  Emit route telemetry for retrieval-triggered topology routing.
  """
  @spec emit_retrieve_route_telemetry(map()) :: :ok
  def emit_retrieve_route_telemetry(result) when is_map(result) do
    emit_route_telemetry(result, :retrieve_context)
    :ok
  end

  @doc """
  Map κ to deliberation parameters (capped heuristic).
  """
  @spec deliberation_budget(non_neg_integer()) :: %{
          max_iterations: pos_integer(),
          agent_count: non_neg_integer(),
          timeout_multiplier: float(),
          confidence_threshold: float()
        }
  def deliberation_budget(kappa) when is_integer(kappa) and kappa >= 0 do
    %{
      max_iterations: min(kappa + 1, 4),
      agent_count: min(kappa, 3),
      timeout_multiplier: min(1.0 + 0.5 * kappa, 3.5),
      confidence_threshold: Float.round(min(0.7 + 0.05 * kappa, 0.95), 2)
    }
  end

  @doc """
  Preview topology impact of adding a directed edge to an adjacency map.
  """
  @spec preview_edge_impact(adjacency(), node_id(), node_id()) :: %{
          creates_new_scc: boolean(),
          kappa_before: non_neg_integer(),
          kappa_after: non_neg_integer(),
          kappa_delta: integer(),
          description: binary()
        }
  def preview_edge_impact(adjacency, source_id, target_id)
      when is_map(adjacency) and is_binary(source_id) and is_binary(target_id) do
    base = normalize_adjacency(adjacency)

    before = do_analyze(base)
    before_scc_nodes = scc_node_union(before.sccs)

    after_adj =
      base
      |> ensure_node(source_id)
      |> ensure_node(target_id)
      |> maybe_add_edge(source_id, target_id)

    after_result = do_analyze(after_adj)
    after_scc_nodes = scc_node_union(after_result.sccs)

    created_new_scc =
      MapSet.size(after_scc_nodes) > MapSet.size(before_scc_nodes) and
        after_result.scc_count >= before.scc_count

    delta = after_result.max_kappa - before.max_kappa

    description =
      cond do
        created_new_scc and after_result.max_kappa > 0 ->
          "This edge creates a feedback loop and increases deliberation pressure."

        delta > 0 ->
          "This edge strengthens an existing feedback loop (higher κ)."

        delta == 0 ->
          "This edge has no κ impact on the analyzed topology."

        true ->
          "This edge reduces feedback complexity (lower κ)."
      end

    %{
      creates_new_scc: created_new_scc,
      kappa_before: before.max_kappa,
      kappa_after: after_result.max_kappa,
      kappa_delta: delta,
      description: description
    }
  end

  # ---- Core analysis ----

  @spec do_analyze(adjacency()) :: analysis_result()
  defp do_analyze(adjacency) do
    adjacency = normalize_adjacency(adjacency)
    all_nodes = adjacency |> Map.keys() |> MapSet.new()

    nontrivial_sccs =
      adjacency
      |> tarjan_scc()
      |> Enum.map(fn scc ->
        scc
        |> MapSet.to_list()
        |> Enum.sort()
        |> MapSet.new()
      end)
      |> Enum.sort_by(fn scc ->
        scc |> MapSet.to_list() |> Enum.sort() |> List.first()
      end)

    sccs =
      nontrivial_sccs
      |> Enum.with_index()
      |> Enum.map(fn {scc_set, idx} ->
        kappa = compute_kappa(adjacency, scc_set)
        k = kappa.kappa

        %{
          id: "scc-#{idx}",
          nodes: scc_set |> MapSet.to_list() |> Enum.sort(),
          kappa: k,
          approximate: kappa.approximate,
          fault_line_edges: Enum.map(kappa.fault_line_edges, &to_fault_line/1),
          routing: if(k > 0, do: :deliberate, else: :fast),
          deliberation_budget: deliberation_budget(k)
        }
      end)

    scc_node_ids =
      sccs
      |> Enum.flat_map(& &1.nodes)
      |> MapSet.new()

    dag_nodes =
      all_nodes
      |> MapSet.difference(scc_node_ids)
      |> MapSet.to_list()
      |> Enum.sort()

    max_kappa =
      sccs
      |> Enum.map(& &1.kappa)
      |> Enum.max(fn -> 0 end)

    routing = if(max_kappa > 0, do: :deliberate, else: :fast)

    %{
      sccs: sccs,
      dag_nodes: dag_nodes,
      routing: routing,
      max_kappa: max_kappa,
      scc_count: length(sccs)
    }
  end

  @spec exact_kappa(adjacency(), [node_id()]) :: kappa_result()
  defp exact_kappa(adjacency, nodes) do
    n = length(nodes)
    max_mask = (1 <<< n) - 1

    initial = %{
      kappa: :infinity,
      partition: nil,
      fault_line_edges: []
    }

    best =
      1..(max_mask - 1)
      |> Enum.reduce_while(initial, fn mask, best ->
        {a_nodes, b_nodes} = partition_from_mask(nodes, mask)

        if a_nodes == [] or b_nodes == [] do
          {:cont, best}
        else
          ab_edges = crossing_edges(adjacency, a_nodes, b_nodes)
          ba_edges = crossing_edges(adjacency, b_nodes, a_nodes)

          ab = length(ab_edges)
          ba = length(ba_edges)
          cut = min(ab, ba)

          {fault_lines, _direction} =
            if ab <= ba do
              {ab_edges, :ab}
            else
              {ba_edges, :ba}
            end

          better? =
            case best.kappa do
              :infinity -> true
              current when is_integer(current) -> cut < current
            end

          next =
            if better? do
              %{
                kappa: cut,
                partition: {a_nodes, b_nodes},
                fault_line_edges: fault_lines
              }
            else
              best
            end

          if cut == 0 do
            {:halt, next}
          else
            {:cont, next}
          end
        end
      end)

    %{
      kappa: normalize_kappa(best.kappa),
      approximate: false,
      fault_line_edges: best.fault_line_edges
    }
  end

  @spec partition_from_mask([node_id()], non_neg_integer()) :: {[node_id()], [node_id()]}
  defp partition_from_mask(nodes, mask) do
    Enum.with_index(nodes)
    |> Enum.reduce({[], []}, fn {node, idx}, {left, right} ->
      if (mask &&& 1 <<< idx) != 0 do
        {[node | left], right}
      else
        {left, [node | right]}
      end
    end)
    |> then(fn {a, b} -> {Enum.reverse(a), Enum.reverse(b)} end)
  end

  @spec crossing_edges(adjacency(), [node_id()], [node_id()]) :: [edge_tuple()]
  defp crossing_edges(adjacency, from_nodes, to_nodes) do
    to_set = MapSet.new(to_nodes)

    from_nodes
    |> Enum.flat_map(fn src ->
      targets = Map.get(adjacency, src, MapSet.new())

      targets
      |> Enum.filter(&MapSet.member?(to_set, &1))
      |> Enum.map(fn dst -> {src, dst} end)
    end)
  end

  @spec to_fault_line(edge_tuple()) :: %{source: node_id(), target: node_id()}
  defp to_fault_line({source, target}), do: %{source: source, target: target}

  @spec normalize_kappa(:infinity | integer()) :: non_neg_integer()
  defp normalize_kappa(:infinity), do: 0
  defp normalize_kappa(k) when is_integer(k) and k >= 0, do: k
  defp normalize_kappa(_), do: 0

  # ---- Iterative Tarjan internals ----

  @type frame :: %{node: node_id(), parent: node_id() | nil, neighbors: [node_id()]}

  @spec push_new_frame(map(), node_id(), node_id() | nil, adjacency()) :: map()
  defp push_new_frame(state, node, parent, adjacency) do
    idx = state.index_counter
    neighbors = adjacency |> Map.get(node, MapSet.new()) |> Enum.sort()

    frame = %{
      node: node,
      parent: parent,
      neighbors: neighbors
    }

    %{
      state
      | index_counter: idx + 1,
        index: Map.put(state.index, node, idx),
        lowlink: Map.put(state.lowlink, node, idx),
        stack: [node | state.stack],
        on_stack: MapSet.put(state.on_stack, node),
        frames: [frame | Map.get(state, :frames, [])]
    }
  end

  @spec process_frames(map(), adjacency()) :: map()
  defp process_frames(%{frames: []} = state, _adjacency), do: %{state | frames: []}

  defp process_frames(%{frames: [frame | rest]} = state, adjacency) do
    node = frame.node

    case frame.neighbors do
      [next | tail] ->
        frame = %{frame | neighbors: tail}
        state = %{state | frames: [frame | rest]}

        cond do
          not Map.has_key?(state.index, next) ->
            state
            |> push_new_frame(next, node, adjacency)
            |> process_frames(adjacency)

          MapSet.member?(state.on_stack, next) ->
            node_low = Map.fetch!(state.lowlink, node)
            next_idx = Map.fetch!(state.index, next)

            lowlink = Map.put(state.lowlink, node, min(node_low, next_idx))
            %{state | lowlink: lowlink} |> process_frames(adjacency)

          true ->
            process_frames(state, adjacency)
        end

      [] ->
        state = finalize_node(frame, %{state | frames: rest})
        process_frames(state, adjacency)
    end
  end

  @spec finalize_node(frame(), map()) :: map()
  defp finalize_node(frame, state) do
    node = frame.node
    parent = frame.parent

    node_low = Map.fetch!(state.lowlink, node)
    node_idx = Map.fetch!(state.index, node)

    state =
      if node_low == node_idx do
        {component, stack, on_stack} = pop_component(node, state.stack, state.on_stack)
        %{state | sccs: [component | state.sccs], stack: stack, on_stack: on_stack}
      else
        state
      end

    if is_binary(parent) do
      parent_low = Map.fetch!(state.lowlink, parent)
      node_low = Map.fetch!(state.lowlink, node)
      lowlink = Map.put(state.lowlink, parent, min(parent_low, node_low))
      %{state | lowlink: lowlink}
    else
      state
    end
  end

  @spec pop_component(node_id(), [node_id()], MapSet.t(node_id())) ::
          {MapSet.t(node_id()), [node_id()], MapSet.t(node_id())}
  defp pop_component(root, stack, on_stack) do
    do_pop_component(root, stack, on_stack, MapSet.new())
  end

  @spec do_pop_component(node_id(), [node_id()], MapSet.t(node_id()), MapSet.t(node_id())) ::
          {MapSet.t(node_id()), [node_id()], MapSet.t(node_id())}
  defp do_pop_component(_root, [], on_stack, acc), do: {acc, [], on_stack}

  defp do_pop_component(root, [node | rest], on_stack, acc) do
    acc = MapSet.put(acc, node)
    on_stack = MapSet.delete(on_stack, node)

    if node == root do
      {acc, rest, on_stack}
    else
      do_pop_component(root, rest, on_stack, acc)
    end
  end

  # ---- Input normalization ----

  @spec to_adjacency(adjacency() | [edge_tuple() | map()]) :: adjacency()
  defp to_adjacency(input) when is_map(input), do: normalize_adjacency(input)

  defp to_adjacency(input) when is_list(input) do
    {nodes, edges} =
      Enum.reduce(input, {MapSet.new(), []}, fn
        {source, target}, {nodes, edges} when is_binary(source) and is_binary(target) ->
          nodes = nodes |> MapSet.put(source) |> MapSet.put(target)
          {nodes, [{source, target} | edges]}

        edge, {nodes, edges} when is_map(edge) ->
          source = map_get(edge, :source_id)
          target = map_get(edge, :target_id)

          if is_binary(source) and is_binary(target) do
            nodes = nodes |> MapSet.put(source) |> MapSet.put(target)
            {nodes, [{source, target} | edges]}
          else
            {nodes, edges}
          end

        _, acc ->
          acc
      end)

    base =
      Enum.reduce(nodes, %{}, fn node, acc ->
        Map.put(acc, node, MapSet.new())
      end)

    Enum.reduce(edges, base, fn {source, target}, acc ->
      if source == target do
        acc
      else
        Map.update(acc, source, MapSet.new([target]), &MapSet.put(&1, target))
      end
    end)
  end

  defp to_adjacency(_), do: %{}

  @spec normalize_adjacency(map()) :: adjacency()
  defp normalize_adjacency(adjacency) do
    all_nodes =
      adjacency
      |> Enum.reduce(MapSet.new(), fn {node, neighbors}, acc ->
        acc =
          if is_binary(node) do
            MapSet.put(acc, node)
          else
            acc
          end

        Enum.reduce(normalize_neighbors(neighbors), acc, fn n, a ->
          if is_binary(n), do: MapSet.put(a, n), else: a
        end)
      end)

    base =
      Enum.reduce(all_nodes, %{}, fn node, acc ->
        Map.put(acc, node, MapSet.new())
      end)

    Enum.reduce(adjacency, base, fn {node, neighbors}, acc ->
      if is_binary(node) do
        cleaned =
          neighbors
          |> normalize_neighbors()
          |> Enum.filter(fn n -> is_binary(n) and n != node and MapSet.member?(all_nodes, n) end)
          |> MapSet.new()

        Map.put(acc, node, cleaned)
      else
        acc
      end
    end)
  end

  @spec normalize_neighbors(term()) :: [term()]
  defp normalize_neighbors(%MapSet{} = neighbors), do: MapSet.to_list(neighbors)
  defp normalize_neighbors(neighbors) when is_list(neighbors), do: neighbors
  defp normalize_neighbors(_), do: []

  @spec ensure_node(adjacency(), node_id()) :: adjacency()
  defp ensure_node(adjacency, node) do
    Map.put_new(adjacency, node, MapSet.new())
  end

  @spec maybe_add_edge(adjacency(), node_id(), node_id()) :: adjacency()
  defp maybe_add_edge(adjacency, source, target) do
    if source == target do
      adjacency
    else
      Map.update(adjacency, source, MapSet.new([target]), &MapSet.put(&1, target))
    end
  end

  @spec scc_node_union([scc_result()]) :: MapSet.t(node_id())
  defp scc_node_union(sccs) do
    sccs
    |> Enum.flat_map(&Map.get(&1, :nodes, []))
    |> MapSet.new()
  end

  @spec graph_stats(adjacency()) :: %{
          node_count: non_neg_integer(),
          edge_count: non_neg_integer()
        }
  defp graph_stats(adjacency) do
    node_count = map_size(adjacency)

    edge_count =
      adjacency
      |> Map.values()
      |> Enum.reduce(0, fn neighbors, acc -> acc + MapSet.size(neighbors) end)

    %{node_count: node_count, edge_count: edge_count}
  end

  # ---- Telemetry ----

  @spec emit_analyze_telemetry(analysis_result(), integer(), non_neg_integer(), non_neg_integer()) ::
          :ok
  defp emit_analyze_telemetry(result, duration_us, node_count, edge_count) do
    :telemetry.execute(
      [:graphonomous, :topology, :analyze],
      %{
        duration_ms: duration_us / 1000.0,
        node_count: node_count,
        edge_count: edge_count
      },
      %{
        scc_count: Map.get(result, :scc_count, 0),
        max_kappa: Map.get(result, :max_kappa, 0),
        routing: Map.get(result, :routing, :fast)
      }
    )

    :ok
  end

  @spec emit_route_telemetry(map(), :retrieve_context | :analyze_topology) :: :ok
  defp emit_route_telemetry(result, trigger) do
    :telemetry.execute(
      [:graphonomous, :topology, :route],
      %{},
      %{
        decision: Map.get(result, :routing, :fast),
        max_kappa: Map.get(result, :max_kappa, 0),
        trigger: trigger
      }
    )

    :ok
  end

  # ---- Generic helpers ----

  @spec map_get(map() | struct(), atom()) :: term()
  defp map_get(%_{} = struct, key), do: struct |> Map.from_struct() |> map_get(key)

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
