defmodule Graphonomous.MCP.GdprErase do
  @moduledoc """
  MCP tool for GDPR-compliant hard deletion of a knowledge node.

  Permanently removes the node, all connected edges, and embedding data.
  No recovery possible. Audit-logged.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Forgetter

  schema do
    field(:node_id, :string,
      required: true,
      description: "ID of the node to permanently erase"
    )
  end

  @impl true
  def execute(params, frame) do
    case p(params, :node_id) do
      node_id when is_binary(node_id) and node_id != "" ->
        case Forgetter.gdpr_erase(node_id) do
          {:ok, result} ->
            payload = %{status: "erased", node_id: node_id, audit: result.audit}

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
