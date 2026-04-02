defmodule Graphonomous.MCP.DeleteNode do
  @moduledoc """
  MCP tool for removing a knowledge node and its connected edges.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:node_id, :string,
      required: true,
      description: "ID of the node to delete"
    )
  end

  @impl true
  def execute(params, frame) do
    case p(params, :node_id) do
      node_id when is_binary(node_id) and node_id != "" ->
        case Graphonomous.Graph.delete_node(node_id) do
          :ok ->
            payload = %{status: "deleted", node_id: node_id}

            {:reply,
             Response.tool()
             |> Response.text(Jason.encode!(payload)), frame}

          {:error, reason} ->
            payload = %{status: "error", error: format_reason(reason)}

            {:reply,
             Response.tool()
             |> Response.text(Jason.encode!(payload))
             |> Map.put(:isError, true), frame}
        end

      _ ->
        payload = %{status: "error", error: "node_id is required"}

        {:reply,
         Response.tool()
         |> Response.text(Jason.encode!(payload))
         |> Map.put(:isError, true), frame}
    end
  end

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp format_reason(:not_found), do: "node not found"
  defp format_reason(other), do: inspect(other)
end
