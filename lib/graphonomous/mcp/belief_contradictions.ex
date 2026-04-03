defmodule Graphonomous.MCP.BeliefContradictions do
  @moduledoc """
  MCP tool for detecting contradictions in the knowledge graph.

  Given a node ID or content string, finds nodes that potentially
  contradict it based on semantic similarity and confidence signals.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.BeliefRevision

  schema do
    field(:node_id, :string,
      description: "ID of a node to check for contradictions"
    )

    field(:content, :string,
      description: "Content string to check for contradictions (alternative to node_id)"
    )
  end

  @impl true
  def execute(params, frame) do
    node_id = p(params, :node_id)
    content = p(params, :content)

    cond do
      is_binary(node_id) and String.trim(node_id) != "" ->
        contradictions = BeliefRevision.detect_contradictions_for_node(String.trim(node_id))

        {:reply,
         ok_response(%{
           node_id: String.trim(node_id),
           contradictions: contradictions,
           count: length(contradictions)
         }), frame}

      is_binary(content) and String.trim(content) != "" ->
        contradictions = BeliefRevision.detect_contradictions(String.trim(content))

        {:reply,
         ok_response(%{
           query: String.slice(String.trim(content), 0..200),
           contradictions: contradictions,
           count: length(contradictions)
         }), frame}

      true ->
        {:reply, error_response("Either node_id or content is required"), frame}
    end
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

  defp p(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
