defmodule Graphonomous.MCP.ForgetNode do
  @moduledoc """
  MCP tool for intentional forgetting of a knowledge node.

  Supports three modes:
    - `soft` — set forgotten_at timestamp, exclude from retrieval, keep structure
    - `hard` — delete node + all edges (UtU constant-time unlink)
    - `cascade` — hard delete + propagate to orphaned dependents
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Forgetter

  schema do
    field(:node_id, :string,
      required: true,
      description: "ID of the node to forget"
    )

    field(:mode, :string, description: "Forgetting mode: soft (default), hard, or cascade")

    field(:reason, :string, description: "Optional reason for forgetting")
  end

  @impl true
  def execute(params, frame) do
    node_id = p(params, :node_id)
    mode = parse_mode(p(params, :mode, "soft"))

    case Forgetter.forget(node_id, mode) do
      {:ok, result} ->
        payload = Map.put(result, :status, "ok")

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
  end

  defp parse_mode("soft"), do: :soft
  defp parse_mode("hard"), do: :hard
  defp parse_mode("cascade"), do: :cascade
  defp parse_mode(_), do: :soft

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp format_reason(:not_found), do: "node not found"
  defp format_reason(other), do: inspect(other)
end
