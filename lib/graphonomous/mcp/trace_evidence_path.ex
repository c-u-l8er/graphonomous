defmodule Graphonomous.MCP.TraceEvidencePath do
  @moduledoc """
  MCP tool for finding the lowest-cost evidence path between two knowledge nodes.

  Uses weighted Dijkstra with cost = -log(confidence) + recency_decay + type_cost.
  Optionally returns K alternate paths via Yen's algorithm.

  Portfolio reuse: explainability ("why did you conclude X?"), Delegatic delegation
  chains, Deliberatic reasoning plans, GeoFleetic spatial routing, AgenTroMatic
  orchestration planning.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Algorithms.Dijkstra

  schema do
    field(:from, :string,
      required: true,
      description: "Source node ID"
    )

    field(:to, :string,
      required: true,
      description: "Target node ID"
    )

    field(:k, :number, description: "Number of alternate paths to return (default: 1, max: 10)")

    field(:half_life_hours, :number,
      description: "Recency decay half-life in hours (default: 168 = 1 week)"
    )

    field(:bidirectional, :string,
      description:
        "If \"true\", also search target→source and return the cheaper direction (default: false)"
    )

    field(:max_hops, :number, description: "Maximum path length in hops (default: 20)")
  end

  @default_k 1
  @max_k 10
  @default_max_hops 20
  @max_hops 50

  @impl true
  def execute(params, frame) do
    from = p(params, :from)
    to = p(params, :to)

    with :ok <- validate_ids(from, to),
         opts <- build_opts(params),
         {:ok, graph} <- build_graph_for_pair(from, to, opts),
         {:ok, results} <- find_paths(graph, from, to, opts) do
      payload = %{
        status: "ok",
        from: from,
        to: to,
        path_count: length(results),
        paths: Enum.map(results, &format_path/1)
      }

      payload =
        if p_bool(params, :bidirectional) do
          case find_paths(graph, to, from, opts) do
            {:ok, reverse_results} ->
              Map.put(payload, :reverse_paths, Enum.map(reverse_results, &format_path/1))

            {:error, _} ->
              Map.put(payload, :reverse_paths, [])
          end
        else
          payload
        end

      {:reply, ok_response(payload), frame}
    else
      {:error, :no_path} ->
        {:reply,
         ok_response(%{
           status: "ok",
           from: from,
           to: to,
           path_count: 0,
           paths: [],
           message: "No evidence path exists between these nodes"
         }), frame}

      {:error, reason} ->
        {:reply, error_response(format_reason(reason)), frame}
    end
  end

  # ── Graph construction ─────────────────────────────────────────

  defp build_graph_for_pair(from, to, opts) do
    max_hops = Keyword.get(opts, :max_hops, @default_max_hops)

    # Collect nodes reachable from both endpoints up to max_hops depth
    # Use BFS from both ends to build a relevant subgraph
    from_nodes = bfs_collect(from, max_hops)
    to_nodes = bfs_collect(to, max_hops)

    # Union of reachable nodes — if disjoint, Dijkstra will return :no_path
    all_node_ids = MapSet.union(from_nodes, to_nodes)

    if MapSet.size(all_node_ids) == 0 do
      {:error, :source_not_found}
    else
      {nodes, edges} = fetch_subgraph(all_node_ids)
      {:ok, Dijkstra.build_graph(nodes, edges)}
    end
  end

  defp bfs_collect(start_id, max_depth) do
    case Graphonomous.get_node(start_id) do
      %{} ->
        do_bfs([{start_id, 0}], MapSet.new([start_id]), max_depth)

      {:error, _} ->
        MapSet.new()
    end
  end

  defp do_bfs([], visited, _max_depth), do: visited

  defp do_bfs([{_id, depth} | rest], visited, max_depth) when depth >= max_depth do
    do_bfs(rest, visited, max_depth)
  end

  defp do_bfs([{node_id, depth} | rest], visited, max_depth) do
    edges = get_edges(node_id)

    {new_queue, new_visited} =
      Enum.reduce(edges, {[], visited}, fn edge, {q, v} ->
        source = Map.get(edge, :source_id) || Map.get(edge, "source_id")
        target = Map.get(edge, :target_id) || Map.get(edge, "target_id")

        neighbors =
          [source, target]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == node_id))

        Enum.reduce(neighbors, {q, v}, fn n, {q2, v2} ->
          if MapSet.member?(v2, n) do
            {q2, v2}
          else
            {[{n, depth + 1} | q2], MapSet.put(v2, n)}
          end
        end)
      end)

    do_bfs(rest ++ Enum.reverse(new_queue), new_visited, max_depth)
  end

  defp get_edges(node_id) do
    case Graphonomous.query_graph(%{operation: "get_edges", node_id: node_id}) do
      edge_list when is_list(edge_list) -> edge_list
      {:ok, edge_list} when is_list(edge_list) -> edge_list
      _ -> []
    end
  end

  defp fetch_subgraph(node_ids) do
    nodes =
      Enum.flat_map(node_ids, fn id ->
        case Graphonomous.get_node(id) do
          %{} = node -> [node]
          _ -> []
        end
      end)

    edge_set =
      Enum.reduce(node_ids, MapSet.new(), fn id, acc ->
        edges = get_edges(id)

        edges
        |> Enum.filter(fn edge ->
          source = Map.get(edge, :source_id) || Map.get(edge, "source_id")
          target = Map.get(edge, :target_id) || Map.get(edge, "target_id")
          MapSet.member?(node_ids, source) and MapSet.member?(node_ids, target)
        end)
        |> Enum.reduce(acc, fn edge, acc2 ->
          edge_id = Map.get(edge, :id) || Map.get(edge, "id") || :erlang.phash2(edge)
          MapSet.put(acc2, {edge_id, edge})
        end)
      end)

    edges = Enum.map(edge_set, fn {_id, edge} -> edge end)
    {nodes, edges}
  end

  # ── Path finding ───────────────────────────────────────────────

  defp find_paths(graph, from, to, opts) do
    k = Keyword.get(opts, :k, @default_k)

    if k <= 1 do
      case Dijkstra.shortest_path(graph, from, to, opts) do
        {:ok, result} -> {:ok, [result]}
        error -> error
      end
    else
      Dijkstra.k_shortest_paths(graph, from, to, opts)
    end
  end

  # ── Parameter handling ─────────────────────────────────────────

  defp validate_ids(from, to) do
    cond do
      not is_binary(from) or String.trim(from) == "" ->
        {:error, {:invalid_params, "from node ID is required"}}

      not is_binary(to) or String.trim(to) == "" ->
        {:error, {:invalid_params, "to node ID is required"}}

      from == to ->
        {:error, {:invalid_params, "from and to must be different node IDs"}}

      true ->
        :ok
    end
  end

  defp build_opts(params) do
    k =
      p(params, :k, @default_k)
      |> parse_pos_int(@default_k)
      |> min(@max_k)

    half_life =
      p(params, :half_life_hours, 168.0)
      |> parse_pos_float(168.0)

    max_hops =
      p(params, :max_hops, @default_max_hops)
      |> parse_pos_int(@default_max_hops)
      |> min(@max_hops)

    [k: k, half_life_hours: half_life, max_hops: max_hops, now: DateTime.utc_now()]
  end

  # ── Formatting ─────────────────────────────────────────────────

  defp format_path(%{path: path, cost: cost, edges: edges}) do
    %{
      nodes: path,
      hop_count: max(0, length(path) - 1),
      total_cost: Float.round(cost, 4),
      edges:
        Enum.map(edges, fn edge ->
          %{
            id: Map.get(edge, :id),
            edge_type: to_string(Map.get(edge, :edge_type, "related")),
            weight: Map.get(edge, :weight, 0.3)
          }
        end)
    }
  end

  # ── Response helpers ───────────────────────────────────────────

  defp ok_response(data) do
    Response.tool()
    |> Response.text(Jason.encode!(data))
  end

  defp error_response(message) do
    payload = %{status: "error", error: message}

    Response.tool()
    |> Response.text(Jason.encode!(payload))
    |> Map.put(:isError, true)
  end

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:source_not_found), do: "source node not found"
  defp format_reason(:target_not_found), do: "target node not found"
  defp format_reason(:no_path), do: "no evidence path exists"
  defp format_reason(other), do: inspect(other)

  # ── Generic param helpers ──────────────────────────────────────

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp p_bool(params, key) do
    case p(params, key) do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp parse_pos_int(value, _default) when is_integer(value) and value > 0, do: value
  defp parse_pos_int(value, _default) when is_float(value) and value > 0, do: trunc(value)

  defp parse_pos_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_pos_int(_, default), do: default

  defp parse_pos_float(value, _default) when is_number(value) and value > 0, do: value / 1.0

  defp parse_pos_float(value, default) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} when f > 0 -> f
      _ -> default
    end
  end

  defp parse_pos_float(_, default), do: default
end
