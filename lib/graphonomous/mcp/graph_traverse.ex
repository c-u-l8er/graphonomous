defmodule Graphonomous.MCP.GraphTraverse do
  @moduledoc """
  MCP tool for walking the knowledge graph from a starting node.

  Traverses outward from a given node ID to a specified depth,
  optionally filtering by relationship types.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:node_id, :string,
      required: true,
      description: "Starting node ID for traversal"
    )

    field(:depth, :number, description: "Max traversal depth (default: 2, max: 5)")

    field(:relationships, :string,
      description:
        "JSON array of relationship types to follow (e.g. [\"causal\",\"supports\"]). Default: all."
    )

    field(:limit, :number, description: "Max total nodes to return (default: 50)")
  end

  @max_depth 5
  @default_depth 2
  @default_limit 50

  @impl true
  def execute(params, frame) do
    node_id = p(params, :node_id)

    if not is_binary(node_id) or String.trim(node_id) == "" do
      {:reply, error_response("node_id is required"), frame}
    else
      depth =
        p(params, :depth, @default_depth) |> parse_pos_int(@default_depth) |> min(@max_depth)

      limit = p(params, :limit, @default_limit) |> parse_pos_int(@default_limit)
      relationships = parse_relationships(p(params, :relationships))

      case do_traverse(node_id, depth, relationships, limit) do
        {:ok, subgraph} ->
          {:reply, ok_response(subgraph), frame}

        {:error, reason} ->
          {:reply, error_response(format_reason(reason)), frame}
      end
    end
  end

  defp do_traverse(start_id, max_depth, rel_filter, limit) do
    case Graphonomous.get_node(start_id) do
      %{} = root_node ->
        {visited_nodes, collected_edges} =
          bfs(start_id, max_depth, rel_filter, limit)

        all_nodes =
          [root_node | fetch_nodes(visited_nodes -- [start_id])]
          |> Enum.take(limit)

        {:ok,
         %{
           root_id: start_id,
           depth: max_depth,
           node_count: length(all_nodes),
           edge_count: length(collected_edges),
           nodes: Enum.map(all_nodes, &serialize_node/1),
           edges: Enum.map(collected_edges, &serialize_edge/1)
         }}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, _} = err ->
        err
    end
  end

  defp bfs(start_id, max_depth, rel_filter, limit) do
    bfs_loop(
      [{start_id, 0}],
      MapSet.new([start_id]),
      [],
      max_depth,
      rel_filter,
      limit
    )
  end

  defp bfs_loop([], visited, edges, _max_depth, _rel_filter, _limit) do
    {MapSet.to_list(visited), Enum.uniq_by(edges, & &1.id)}
  end

  defp bfs_loop(_queue, visited, edges, _max_depth, _rel_filter, limit)
       when map_size(visited) >= limit do
    {MapSet.to_list(visited) |> Enum.take(limit), Enum.uniq_by(edges, & &1.id)}
  end

  defp bfs_loop([{_node_id, current_depth} | rest], visited, edges, max_depth, rel_filter, limit)
       when current_depth >= max_depth do
    bfs_loop(rest, visited, edges, max_depth, rel_filter, limit)
  end

  defp bfs_loop([{node_id, current_depth} | rest], visited, edges, max_depth, rel_filter, limit) do
    node_edges =
      case Graphonomous.query_graph(%{operation: "get_edges", node_id: node_id}) do
        edge_list when is_list(edge_list) -> edge_list
        {:ok, edge_list} when is_list(edge_list) -> edge_list
        _ -> []
      end

    filtered_edges = filter_by_relationship(node_edges, rel_filter)

    {new_queue, new_visited} =
      Enum.reduce(filtered_edges, {[], visited}, fn edge, {q_acc, v_acc} ->
        neighbor_id = neighbor_of(edge, node_id)

        if neighbor_id && not MapSet.member?(v_acc, neighbor_id) do
          {[{neighbor_id, current_depth + 1} | q_acc], MapSet.put(v_acc, neighbor_id)}
        else
          {q_acc, v_acc}
        end
      end)

    bfs_loop(
      rest ++ Enum.reverse(new_queue),
      new_visited,
      edges ++ filtered_edges,
      max_depth,
      rel_filter,
      limit
    )
  end

  defp neighbor_of(edge, node_id) do
    source = Map.get(edge, :source_id) || Map.get(edge, "source_id")
    target = Map.get(edge, :target_id) || Map.get(edge, "target_id")

    cond do
      source == node_id -> target
      target == node_id -> source
      true -> nil
    end
  end

  defp filter_by_relationship(edges, nil), do: edges

  defp filter_by_relationship(edges, allowed) when is_list(allowed) do
    Enum.filter(edges, fn edge ->
      rel =
        (Map.get(edge, :relationship) || Map.get(edge, :edge_type) ||
           Map.get(edge, "relationship") || Map.get(edge, "edge_type") || "")
        |> to_string()
        |> String.downcase()

      rel in allowed
    end)
  end

  defp fetch_nodes(node_ids) do
    Enum.flat_map(node_ids, fn id ->
      case Graphonomous.get_node(id) do
        %{} = node -> [node]
        _ -> []
      end
    end)
  end

  defp parse_relationships(nil), do: nil

  defp parse_relationships(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) ->
        normalized = Enum.map(list, &String.downcase(String.trim(to_string(&1))))

        if normalized == [], do: nil, else: normalized

      _ ->
        # Try comma-separated
        parts =
          value
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.downcase/1)
          |> Enum.reject(&(&1 == ""))

        if parts == [], do: nil, else: parts
    end
  end

  defp parse_relationships(_), do: nil

  defp serialize_node(node) when is_map(node) do
    node =
      if Map.has_key?(node, :__struct__), do: Map.from_struct(node), else: node

    node
    |> Map.drop([:embedding])
    |> Enum.into(%{}, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, v} -> {k, v}
    end)
  end

  defp serialize_edge(edge) when is_map(edge) do
    edge =
      if Map.has_key?(edge, :__struct__), do: Map.from_struct(edge), else: edge

    edge
    |> Map.drop([:embedding])
    |> Enum.into(%{}, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, v} -> {k, v}
    end)
  end

  defp ok_response(data) do
    payload = Map.put(data, :status, "ok")

    Response.tool()
    |> Response.text(Jason.encode!(payload))
  end

  defp error_response(message) do
    payload = %{status: "error", error: message}

    Response.tool()
    |> Response.text(Jason.encode!(payload))
    |> Map.put(:isError, true)
  end

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
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

  defp format_reason(:not_found), do: "node not found"
  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(other), do: inspect(other)
end
