defmodule Graphonomous.MCP.RetrieveEpisodic do
  @moduledoc """
  MCP tool for retrieving recent episodic (interaction/event) memories.

  Filters the graph for episodic nodes, optionally bounded by a time range,
  and returns them sorted by recency.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:limit, :number, description: "Max episodes to return (default: 20)")
    field(:since, :string, description: "ISO8601 datetime — only return episodes after this time")
  end

  @default_limit 20

  @impl true
  def execute(params, frame) do
    limit = p(params, :limit, @default_limit) |> parse_pos_int(@default_limit)
    since = parse_datetime(p(params, :since))

    case do_retrieve_episodic(limit, since) do
      {:ok, result} ->
        {:reply, ok_response(result), frame}

      {:error, reason} ->
        {:reply, error_response(inspect(reason)), frame}
    end
  end

  defp do_retrieve_episodic(limit, since) do
    case Graphonomous.list_nodes(%{node_type: :episodic}) do
      nodes when is_list(nodes) ->
        filtered =
          nodes
          |> maybe_filter_since(since)
          |> Enum.sort_by(&node_timestamp/1, {:desc, DateTime})
          |> Enum.take(limit)

        {:ok,
         %{
           count: length(filtered),
           since: if(since, do: DateTime.to_iso8601(since), else: nil),
           episodes: Enum.map(filtered, &serialize_node/1)
         }}

      {:error, _} = err ->
        err
    end
  end

  defp maybe_filter_since(nodes, nil), do: nodes

  defp maybe_filter_since(nodes, since) do
    Enum.filter(nodes, fn node ->
      ts = node_timestamp(node)
      ts != nil and DateTime.compare(ts, since) in [:gt, :eq]
    end)
  end

  defp node_timestamp(node) do
    raw =
      Map.get(node, :created_at) ||
        Map.get(node, :access_recency) ||
        Map.get(node, :updated_at)

    parse_datetime(raw)
  end

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

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    value = String.trim(value)

    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_datetime(_), do: nil
end
