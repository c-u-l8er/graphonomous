defmodule Graphonomous.MCP.Resources.NodeDetail do
  @moduledoc """
  Read-only MCP resource template exposing individual node details.

  URI template: `graphonomous://graph/node/{id}`
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "graphonomous://graph/node/{id}",
    name: "graphonomous_graph_node",
    mime_type: "application/json"

  alias Anubis.Server.Response

  @uri_prefix "graphonomous://graph/node/"

  @impl true
  def description do
    "Individual node details by ID, including content, confidence, metadata, and edges."
  end

  @impl true
  def read(params, frame) do
    uri = Map.get(params, "uri", "")

    case extract_node_id(uri) do
      nil ->
        error = Anubis.MCP.Error.resource(:not_found, %{message: "No node ID in URI: #{uri}"})
        {:error, error, frame}

      node_id ->
        case Graphonomous.get_node(node_id) do
          %{} = node ->
            edges = fetch_edges(node_id)

            payload = %{
              generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
              node: serialize_node(node),
              edge_count: length(edges),
              edges: Enum.map(edges, &serialize_edge/1)
            }

            response =
              Response.resource()
              |> Response.text(Jason.encode!(payload))

            {:reply, response, frame}

          {:error, :not_found} ->
            error =
              Anubis.MCP.Error.resource(:not_found, %{message: "Node not found: #{node_id}"})

            {:error, error, frame}

          {:error, _reason} ->
            error =
              Anubis.MCP.Error.resource(:not_found, %{message: "Node not found: #{node_id}"})

            {:error, error, frame}
        end
    end
  end

  defp extract_node_id(uri) when is_binary(uri) do
    case String.split(uri, @uri_prefix, parts: 2) do
      [_, id] when id != "" -> String.trim(id)
      _ -> nil
    end
  end

  defp extract_node_id(_), do: nil

  defp fetch_edges(node_id) do
    case Graphonomous.query_graph(%{operation: "get_edges", node_id: node_id}) do
      edges when is_list(edges) -> edges
      {:ok, edges} when is_list(edges) -> edges
      _ -> []
    end
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
end
