defmodule Graphonomous.MCP.ManageEdge do
  @moduledoc """
  MCP tool for edge lifecycle management: list, update, and delete edges.

  Supported operations:
    - `list_all` — list all edges in the graph
    - `list_for_node` — list edges connected to a specific node
    - `update` — modify edge weight, co_activation_count, or decay_rate
    - `delete` — remove an edge by ID
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:operation, :string,
      required: true,
      description: "list_all, list_for_node, update, or delete"
    )

    field(:edge_id, :string, description: "Required for update/delete")
    field(:node_id, :string, description: "Required for list_for_node")
    field(:weight, :number, description: "New weight (0.0–1.0) for update")

    field(:co_activation_count, :number, description: "New co-activation count for update")

    field(:decay_rate, :number, description: "New decay rate for update")
  end

  @impl true
  def execute(params, frame) do
    operation = p(params, :operation, "list_all") |> normalize_operation()

    result =
      case operation do
        :list_all -> do_list_all()
        :list_for_node -> do_list_for_node(params)
        :update -> do_update(params)
        :delete -> do_delete(params)
      end

    {payload, is_error} =
      case result do
        {:ok, data} ->
          {Map.merge(data, %{operation: Atom.to_string(operation), status: "ok"}), false}

        {:error, reason} ->
          {%{
             operation: Atom.to_string(operation),
             status: "error",
             error: format_reason(reason)
           }, true}
      end

    {:reply, tool_response(payload, is_error), frame}
  end

  defp do_list_all do
    case Graphonomous.Graph.list_all_edges() do
      {:ok, edges} ->
        {:ok, %{count: length(edges), edges: Enum.map(edges, &serialize_edge/1)}}

      {:error, _} = err ->
        err
    end
  end

  defp do_list_for_node(params) do
    case p(params, :node_id) do
      node_id when is_binary(node_id) and node_id != "" ->
        case Graphonomous.Graph.get_edges_for_node(node_id) do
          {:ok, edges} ->
            {:ok,
             %{
               node_id: node_id,
               count: length(edges),
               edges: Enum.map(edges, &serialize_edge/1)
             }}

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:invalid_params, "node_id is required for list_for_node"}}
    end
  end

  defp do_update(params) do
    case p(params, :edge_id) do
      edge_id when is_binary(edge_id) and edge_id != "" ->
        attrs =
          %{}
          |> maybe_put(:weight, p(params, :weight))
          |> maybe_put(:co_activation_count, p(params, :co_activation_count))
          |> maybe_put(:decay_rate, p(params, :decay_rate))

        case Graphonomous.Graph.update_edge(edge_id, attrs) do
          {:ok, edge} ->
            {:ok, %{edge: serialize_edge(edge)}}

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:invalid_params, "edge_id is required for update"}}
    end
  end

  defp do_delete(params) do
    case p(params, :edge_id) do
      edge_id when is_binary(edge_id) and edge_id != "" ->
        case Graphonomous.Graph.delete_edge(edge_id) do
          :ok ->
            {:ok, %{deleted: edge_id}}

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:invalid_params, "edge_id is required for delete"}}
    end
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

  defp normalize_operation(op) when is_binary(op) do
    case String.downcase(String.trim(op)) do
      "list_all" -> :list_all
      "list" -> :list_all
      "list_for_node" -> :list_for_node
      "for_node" -> :list_for_node
      "update" -> :update
      "delete" -> :delete
      "remove" -> :delete
      _ -> :list_all
    end
  end

  defp normalize_operation(_), do: :list_all

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp tool_response(payload, is_error) when is_map(payload) do
    response =
      Response.tool()
      |> Response.text(Jason.encode!(payload))

    if is_error, do: %{response | isError: true}, else: response
  end

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:not_found), do: "edge not found"
  defp format_reason(other), do: inspect(other)
end
