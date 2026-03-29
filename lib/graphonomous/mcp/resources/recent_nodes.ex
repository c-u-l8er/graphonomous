defmodule Graphonomous.MCP.Resources.RecentNodes do
  @moduledoc """
  Read-only MCP resource exposing recently added or accessed nodes.

  URI: `graphonomous://graph/recent`
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "graphonomous://graph/recent",
    name: "graphonomous_graph_recent",
    mime_type: "application/json"

  alias Anubis.Server.Response

  @default_limit 20

  @impl true
  def description do
    "Recently added or accessed knowledge nodes, sorted by recency."
  end

  @impl true
  def read(_params, frame) do
    nodes = fetch_recent_nodes(@default_limit)

    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      count: length(nodes),
      limit: @default_limit,
      nodes: Enum.map(nodes, &serialize_node/1)
    }

    response =
      Response.resource()
      |> Response.text(Jason.encode!(payload))

    {:reply, response, frame}
  end

  defp fetch_recent_nodes(limit) do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        nodes
        |> Enum.sort_by(&node_recency/1, {:desc, DateTime})
        |> Enum.take(limit)

      _ ->
        []
    end
  end

  defp node_recency(node) do
    # Prefer access_recency, fall back to updated_at, then created_at
    parse_datetime(Map.get(node, :access_recency)) ||
      parse_datetime(Map.get(node, :updated_at)) ||
      parse_datetime(Map.get(node, :created_at)) ||
      ~U[1970-01-01 00:00:00Z]
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
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
end
