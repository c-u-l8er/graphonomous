defmodule Graphonomous.Algorithms.Dijkstra do
  @moduledoc """
  Weighted shortest-path algorithms for evidence-path tracing.

  Computes the minimum-cost path between two nodes in the knowledge graph
  using a pluggable cost function. Default cost:

      cost(edge, target_node) = -log(confidence) + recency_decay + type_cost

  where:
    - confidence = edge.weight (clamped to [0.01, 1.0])
    - recency_decay = age_hours / half_life_hours
    - type_cost = per-edge-type penalty (causal/supports cheap, contradicts expensive)

  Min-cost path ≈ most confident, recent, and direct evidence chain.

  Also implements Yen's K-shortest paths for alternate evidence routes.

  ### Complexity

  Dijkstra: O((V + E) log V) with binary heap (Erlang `:gb_trees`).
  Yen's K-shortest: O(K · V · (V + E) log V) worst case.
  Intended for subgraphs up to ~100K nodes.

  ### Usage

      # Single shortest path
      Dijkstra.shortest_path(graph, "node_a", "node_b")
      #=> {:ok, %{path: ["node_a", "node_x", "node_b"], cost: 2.34, edges: [...]}}

      # K-shortest paths
      Dijkstra.k_shortest_paths(graph, "node_a", "node_b", k: 3)
      #=> {:ok, [%{path: [...], cost: 2.34}, %{path: [...], cost: 3.01}, ...]}
  """

  @type node_id :: binary()
  @type cost :: float()

  @type graph :: %{
          nodes: %{optional(node_id()) => node_info()},
          adjacency: %{optional(node_id()) => [{node_id(), edge_info()}]}
        }

  @type node_info :: %{
          optional(:confidence) => float(),
          optional(:created_at) => DateTime.t() | nil,
          optional(:last_accessed_at) => DateTime.t() | nil
        }

  @type edge_info :: %{
          optional(:weight) => float(),
          optional(:edge_type) => atom() | binary(),
          optional(:created_at) => DateTime.t() | nil,
          optional(:last_activated_at) => DateTime.t() | nil,
          optional(:id) => binary()
        }

  @type path_result :: %{
          path: [node_id()],
          cost: cost(),
          edges: [edge_info()]
        }

  @type cost_fn :: (edge_info(), node_info(), keyword() -> cost())

  # Default cost parameters
  @default_half_life_hours 168.0
  @default_k 1
  @infinity 1.0e18

  # Per-edge-type costs (lower = preferred for evidence chains)
  @type_costs %{
    causal: 0.0,
    causes: 0.0,
    supports: 0.1,
    derived_from: 0.1,
    resolves: 0.2,
    follows: 0.2,
    temporal_before: 0.3,
    temporal_after: 0.3,
    co_occurs: 0.3,
    related: 0.5,
    related_to: 0.5,
    part_of: 0.5,
    similar_to: 0.6,
    depends_on: 0.4,
    supersedes: 0.8,
    contradicts: 2.0
  }

  # ── Public API ──────────────────────────────────────────────────

  @doc """
  Find the shortest (minimum-cost) path from `source` to `target`.

  Options:
    * `:cost_fn`          - custom `(edge_info, target_node_info, opts) -> float()`.
                            Default uses confidence + recency + type cost.
    * `:half_life_hours`  - recency decay half-life. Default #{@default_half_life_hours}.
    * `:now`              - reference time for recency. Default `DateTime.utc_now()`.

  Returns `{:ok, path_result}` or `{:error, :no_path}` / `{:error, :not_found}`.
  """
  @spec shortest_path(graph(), node_id(), node_id(), keyword()) ::
          {:ok, path_result()} | {:error, atom()}
  def shortest_path(graph, source, target, opts \\ []) do
    cond do
      not Map.has_key?(graph.nodes, source) -> {:error, :source_not_found}
      not Map.has_key?(graph.nodes, target) -> {:error, :target_not_found}
      source == target -> {:ok, %{path: [source], cost: 0.0, edges: []}}
      true -> dijkstra(graph, source, target, opts)
    end
  end

  @doc """
  Find up to `k` shortest paths using Yen's algorithm.

  Options: same as `shortest_path/4` plus:
    * `:k` - number of paths to find. Default #{@default_k}.

  Returns `{:ok, [path_result]}` (may return fewer than k if not enough paths exist).
  """
  @spec k_shortest_paths(graph(), node_id(), node_id(), keyword()) ::
          {:ok, [path_result()]} | {:error, atom()}
  def k_shortest_paths(graph, source, target, opts \\ []) do
    k = max(1, Keyword.get(opts, :k, @default_k))

    case shortest_path(graph, source, target, opts) do
      {:error, _} = err ->
        err

      {:ok, first_path} when k == 1 ->
        {:ok, [first_path]}

      {:ok, first_path} ->
        {:ok, yens_algorithm(graph, source, target, first_path, k, opts)}
    end
  end

  @doc """
  Default edge cost function.

  cost = -log(confidence) + age_hours/half_life + type_penalty

  All components are non-negative, so Dijkstra invariant holds.
  """
  @spec default_cost(edge_info(), node_info(), keyword()) :: cost()
  def default_cost(edge, _target_node, opts \\ []) do
    confidence = edge |> Map.get(:weight, 0.5) |> clamp(0.01, 1.0)
    confidence_cost = -:math.log(confidence)

    half_life = Keyword.get(opts, :half_life_hours, @default_half_life_hours)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    edge_time = Map.get(edge, :last_activated_at) || Map.get(edge, :created_at)
    recency_cost = recency_decay(edge_time, now, half_life)

    edge_type = normalize_edge_type(Map.get(edge, :edge_type, :related))
    type_cost = Map.get(@type_costs, edge_type, 0.5)

    confidence_cost + recency_cost + type_cost
  end

  @doc "Returns the built-in type cost map for inspection/testing."
  @spec type_costs() :: %{atom() => float()}
  def type_costs, do: @type_costs

  # ── Dijkstra core ──────────────────────────────────────────────

  defp dijkstra(graph, source, target, opts) do
    cost_fn = Keyword.get(opts, :cost_fn, &default_cost/3)

    # Priority queue: :gb_trees keyed by {cost, unique_counter} → node_id
    # dist: node_id → best known cost
    # prev: node_id → {prev_node_id, edge_info}
    init_heap = :gb_trees.insert({0.0, 0}, source, :gb_trees.empty())
    init_dist = %{source => 0.0}
    init_prev = %{}

    do_dijkstra(graph, target, cost_fn, opts, init_heap, init_dist, init_prev, 1)
  end

  defp do_dijkstra(_graph, _target, _cost_fn, _opts, heap, _dist, _prev, _counter)
       when map_size(heap) == 0 do
    # :gb_trees uses a tuple internally, check emptiness differently
    {:error, :no_path}
  end

  defp do_dijkstra(graph, target, cost_fn, opts, heap, dist, prev, counter) do
    if :gb_trees.is_empty(heap) do
      {:error, :no_path}
    else
      {{cost_key, _uid}, current, heap} = :gb_trees.take_smallest(heap)

      cond do
        current == target ->
          {:ok, reconstruct_path(prev, target, cost_key)}

        cost_key > Map.get(dist, current, @infinity) ->
          # Stale entry, skip
          do_dijkstra(graph, target, cost_fn, opts, heap, dist, prev, counter)

        true ->
          neighbors = Map.get(graph.adjacency, current, [])

          {heap, dist, prev, counter} =
            Enum.reduce(neighbors, {heap, dist, prev, counter}, fn {neighbor, edge},
                                                                   {h, d, p, c} ->
              target_node = Map.get(graph.nodes, neighbor, %{})
              edge_cost = cost_fn.(edge, target_node, opts)
              new_cost = cost_key + edge_cost

              if new_cost < Map.get(d, neighbor, @infinity) do
                h = :gb_trees.insert({new_cost, c}, neighbor, h)
                d = Map.put(d, neighbor, new_cost)
                p = Map.put(p, neighbor, {current, edge})
                {h, d, p, c + 1}
              else
                {h, d, p, c}
              end
            end)

          do_dijkstra(graph, target, cost_fn, opts, heap, dist, prev, counter)
      end
    end
  end

  defp reconstruct_path(prev, target, total_cost) do
    {path, edges} = trace_back(prev, target, [], [])

    %{
      path: path,
      cost: total_cost,
      edges: edges
    }
  end

  defp trace_back(prev, current, path_acc, edge_acc) do
    case Map.get(prev, current) do
      nil ->
        {[current | path_acc], edge_acc}

      {parent, edge} ->
        trace_back(prev, parent, [current | path_acc], [edge | edge_acc])
    end
  end

  # ── Yen's K-shortest paths ────────────────────────────────────

  defp yens_algorithm(graph, _source, target, first_path, k, opts) do
    # A = confirmed shortest paths, B = candidate pool (sorted by cost)
    a = [first_path]
    b = []

    Enum.reduce_while(1..(k - 1), {a, b}, fn _i, {a_paths, candidates} ->
      last_path = List.last(a_paths)
      path_nodes = last_path.path

      new_candidates =
        Enum.reduce(0..(length(path_nodes) - 2), candidates, fn j, cands ->
          spur_node = Enum.at(path_nodes, j)
          root_path = Enum.take(path_nodes, j + 1)

          # Block edges used by existing paths at this spur point
          blocked_edges = blocked_edges_at_spur(a_paths, root_path, j)
          # Block nodes in root path (except spur node) to avoid loops
          blocked_nodes = MapSet.new(Enum.take(root_path, j))

          modified_graph = remove_edges_and_nodes(graph, blocked_edges, blocked_nodes)

          case dijkstra(modified_graph, spur_node, target, opts) do
            {:ok, spur_result} ->
              # Combine root path + spur path
              full_path = Enum.take(root_path, j) ++ spur_result.path
              root_cost = root_path_cost(graph, root_path, opts)
              full_cost = root_cost + spur_result.cost

              full_edges =
                root_path_edges(graph, Enum.take(root_path, j + 1), opts) ++
                  spur_result.edges

              candidate = %{path: full_path, cost: full_cost, edges: full_edges}

              if not path_in_list?(candidate, a_paths) and not path_in_list?(candidate, cands) do
                insert_sorted(cands, candidate)
              else
                cands
              end

            {:error, _} ->
              cands
          end
        end)

      case new_candidates do
        [] ->
          {:halt, {a_paths, []}}

        [best | rest] ->
          {:cont, {a_paths ++ [best], rest}}
      end
    end)
    |> case do
      {a_paths, _} -> a_paths
      other -> other
    end
  end

  defp blocked_edges_at_spur(a_paths, root_path, spur_index) do
    spur_node = Enum.at(root_path, spur_index)

    Enum.flat_map(a_paths, fn %{path: p} ->
      if Enum.take(p, spur_index + 1) == Enum.take(root_path, spur_index + 1) and
           length(p) > spur_index + 1 do
        [{spur_node, Enum.at(p, spur_index + 1)}]
      else
        []
      end
    end)
  end

  defp remove_edges_and_nodes(graph, blocked_edges, blocked_nodes) do
    blocked_edge_set = MapSet.new(blocked_edges)

    new_adj =
      graph.adjacency
      |> Enum.reject(fn {node_id, _} -> MapSet.member?(blocked_nodes, node_id) end)
      |> Enum.map(fn {node_id, neighbors} ->
        filtered =
          Enum.reject(neighbors, fn {target_id, _edge} ->
            MapSet.member?(blocked_nodes, target_id) or
              MapSet.member?(blocked_edge_set, {node_id, target_id})
          end)

        {node_id, filtered}
      end)
      |> Map.new()

    new_nodes = Map.drop(graph.nodes, MapSet.to_list(blocked_nodes))

    %{graph | adjacency: new_adj, nodes: new_nodes}
  end

  defp root_path_cost(_graph, path, _opts) when length(path) <= 1, do: 0.0

  defp root_path_cost(graph, path, opts) do
    cost_fn = Keyword.get(opts, :cost_fn, &default_cost/3)

    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [from, to], acc ->
      edge = find_edge(graph, from, to)
      target_node = Map.get(graph.nodes, to, %{})
      acc + cost_fn.(edge, target_node, opts)
    end)
  end

  defp root_path_edges(_graph, path, _opts) when length(path) <= 1, do: []

  defp root_path_edges(graph, path, _opts) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] -> find_edge(graph, from, to) end)
  end

  defp find_edge(graph, from, to) do
    graph.adjacency
    |> Map.get(from, [])
    |> Enum.find_value(%{}, fn {target, edge} ->
      if target == to, do: edge
    end)
  end

  defp path_in_list?(%{path: path}, list) do
    Enum.any?(list, fn %{path: p} -> p == path end)
  end

  defp insert_sorted(list, item) do
    {before, after_} = Enum.split_while(list, fn %{cost: c} -> c <= item.cost end)
    before ++ [item | after_]
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp recency_decay(nil, _now, _half_life), do: 0.0

  defp recency_decay(%DateTime{} = timestamp, %DateTime{} = now, half_life) do
    age_seconds = max(0, DateTime.diff(now, timestamp, :second))
    age_hours = age_seconds / 3600.0
    age_hours / max(half_life, 1.0)
  end

  defp recency_decay(_, _, _), do: 0.0

  defp normalize_edge_type(type) when is_atom(type), do: type

  defp normalize_edge_type(type) when is_binary(type) do
    type
    |> String.downcase()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :related
  end

  defp normalize_edge_type(_), do: :related

  defp clamp(x, lo, hi) when is_number(x) do
    cond do
      x < lo -> lo
      x > hi -> hi
      true -> x / 1.0
    end
  end

  defp clamp(_, lo, _), do: lo / 1.0

  # ── Graph Builder (convenience for MCP integration) ───────────

  @doc """
  Build a graph structure from raw nodes and edges suitable for pathfinding.

  Accepts:
    - `nodes` - list of node maps/structs with at minimum `:id`, `:confidence`
    - `edges` - list of edge maps/structs with `:source_id`, `:target_id`, `:weight`, `:edge_type`

  Returns a `graph()` map with `:nodes` and `:adjacency` keys.
  Edges are treated as directed (source → target).
  """
  @spec build_graph([map()], [map()]) :: graph()
  def build_graph(nodes, edges) do
    node_map =
      Map.new(nodes, fn node ->
        id = Map.get(node, :id) || Map.get(node, "id")

        info = %{
          confidence: Map.get(node, :confidence) || Map.get(node, "confidence") || 0.5,
          created_at: Map.get(node, :created_at) || Map.get(node, "created_at"),
          last_accessed_at: Map.get(node, :last_accessed_at) || Map.get(node, "last_accessed_at")
        }

        {id, info}
      end)

    adjacency =
      Enum.reduce(edges, %{}, fn edge, acc ->
        source = Map.get(edge, :source_id) || Map.get(edge, "source_id")
        target = Map.get(edge, :target_id) || Map.get(edge, "target_id")

        edge_info = %{
          id: Map.get(edge, :id) || Map.get(edge, "id"),
          weight: Map.get(edge, :weight) || Map.get(edge, "weight") || 0.3,
          edge_type: Map.get(edge, :edge_type) || Map.get(edge, "edge_type") || :related,
          created_at: Map.get(edge, :created_at) || Map.get(edge, "created_at"),
          last_activated_at:
            Map.get(edge, :last_activated_at) || Map.get(edge, "last_activated_at")
        }

        Map.update(acc, source, [{target, edge_info}], fn existing ->
          [{target, edge_info} | existing]
        end)
      end)

    %{nodes: node_map, adjacency: adjacency}
  end
end
