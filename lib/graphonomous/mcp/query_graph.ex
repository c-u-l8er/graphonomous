defmodule Graphonomous.MCP.QueryGraph do
  @moduledoc """
  Query graph state for inspection and retrieval workflows.

  Supported operations:
    - `list_nodes`
    - `get_node`
    - `get_edges`
    - `similarity_search`
  """

  use Anubis.Server.Component, type: :tool

  schema do
    field :operation, :string, required: true,
      description: "list_nodes, get_node, get_edges, or similarity_search"

    field :node_id, :string,
      description: "Required for get_node/get_edges"

    field :node_type, :string,
      description: "Optional filter for list_nodes (episodic|semantic|procedural)"

    field :min_confidence, :number,
      description: "Optional filter for list_nodes (0.0-1.0)"

    field :limit, :number,
      description: "Optional max results for list_nodes/similarity_search"

    field :query, :string,
      description: "Natural-language query for similarity_search"
  end

  @impl true
  def execute(params, frame) do
    operation =
      params
      |> p(:operation, "list_nodes")
      |> normalize_operation()

    result =
      case operation do
        :list_nodes -> do_list_nodes(params)
        :get_node -> do_get_node(params)
        :get_edges -> do_get_edges(params)
        :similarity_search -> do_similarity_search(params)
      end

    payload =
      case result do
        {:ok, data} ->
          %{
            operation: Atom.to_string(operation),
            status: "ok",
            result: data
          }

        {:error, reason} ->
          %{
            operation: Atom.to_string(operation),
            status: "error",
            error: format_reason(reason)
          }
      end

    {:ok, Jason.encode!(payload), frame}
  end

  defp do_list_nodes(params) do
    filters = %{
      operation: "list_nodes",
      node_type: p(params, :node_type),
      min_confidence: p(params, :min_confidence),
      limit: p(params, :limit)
    }

    filters =
      filters
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Graphonomous.query_graph(filters)
    |> normalize_nodes_response()
  end

  defp do_get_node(params) do
    case p(params, :node_id) do
      node_id when is_binary(node_id) and node_id != "" ->
        Graphonomous.get_node(node_id)
        |> normalize_single_node_response()

      _ ->
        {:error, {:invalid_params, "node_id is required for get_node"}}
    end
  end

  defp do_get_edges(params) do
    case p(params, :node_id) do
      node_id when is_binary(node_id) and node_id != "" ->
        Graphonomous.query_graph(%{operation: "get_edges", node_id: node_id})
        |> normalize_edges_response()

      _ ->
        {:error, {:invalid_params, "node_id is required for get_edges"}}
    end
  end

  defp do_similarity_search(params) do
    query = p(params, :query, "")

    if is_binary(query) and String.trim(query) != "" do
      Graphonomous.query_graph(%{
        operation: "similarity_search",
        query: query,
        limit: p(params, :limit, 10)
      })
      |> normalize_similarity_response()
    else
      {:error, {:invalid_params, "query is required for similarity_search"}}
    end
  end

  defp normalize_nodes_response({:error, _} = err), do: err

  defp normalize_nodes_response(nodes) when is_list(nodes) do
    {:ok, %{count: length(nodes), nodes: Enum.map(nodes, &serialize_node/1)}}
  end

  defp normalize_nodes_response(other), do: {:error, {:unexpected_response, other}}

  defp normalize_single_node_response({:error, _} = err), do: err

  defp normalize_single_node_response(node) when is_map(node) do
    {:ok, %{node: serialize_node(node)}}
  end

  defp normalize_single_node_response(other), do: {:error, {:unexpected_response, other}}

  defp normalize_edges_response({:error, _} = err), do: err

  defp normalize_edges_response(edges) when is_list(edges) do
    {:ok, %{count: length(edges), edges: Enum.map(edges, &serialize_edge/1)}}
  end

  defp normalize_edges_response(other), do: {:error, {:unexpected_response, other}}

  defp normalize_similarity_response({:error, _} = err), do: err

  defp normalize_similarity_response(results) when is_list(results) do
    {:ok, %{count: length(results), matches: Enum.map(results, &serialize_match/1)}}
  end

  defp normalize_similarity_response(other), do: {:error, {:unexpected_response, other}}

  defp serialize_node(node) when is_map(node) do
    node =
      if Map.has_key?(node, :__struct__) do
        Map.from_struct(node)
      else
        node
      end

    Enum.into(node, %{}, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, v} -> {k, v}
    end)
  end

  defp serialize_edge(edge) when is_map(edge) do
    edge =
      if Map.has_key?(edge, :__struct__) do
        Map.from_struct(edge)
      else
        edge
      end

    Enum.into(edge, %{}, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, v} -> {k, v}
    end)
  end

  defp serialize_match(match) when is_map(match) do
    %{
      node_id: Map.get(match, :node_id),
      content: Map.get(match, :content),
      node_type: Map.get(match, :node_type),
      confidence: Map.get(match, :confidence),
      similarity: Map.get(match, :similarity),
      score: Map.get(match, :score)
    }
  end

  defp normalize_operation(op) when is_binary(op) do
    case String.downcase(String.trim(op)) do
      "get_node" -> :get_node
      "get" -> :get_node
      "get_edges" -> :get_edges
      "edges" -> :get_edges
      "similarity_search" -> :similarity_search
      "retrieve_context" -> :similarity_search
      _ -> :list_nodes
    end
  end

  defp normalize_operation(_), do: :list_nodes

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:not_found), do: "not found"
  defp format_reason(other), do: inspect(other)
end
