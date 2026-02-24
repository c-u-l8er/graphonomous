defmodule Graphonomous.MCP.Resources.HealthSnapshot do
  @moduledoc """
  Read-only MCP resource exposing runtime health and lightweight counts.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "graphonomous://runtime/health",
    name: "graphonomous_runtime_health",
    mime_type: "application/json"

  alias Anubis.Server.Response

  @impl true
  def description do
    "Runtime health snapshot for supervised services and high-level object counts."
  end

  @impl true
  def read(_params, frame) do
    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      health: Graphonomous.health(),
      counts: %{
        nodes: safe_count_nodes(),
        goals: safe_count_goals()
      }
    }

    response =
      Response.resource()
      |> Response.text(Jason.encode!(payload))

    {:reply, response, frame}
  end

  defp safe_count_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) -> length(nodes)
      _ -> 0
    end
  end

  defp safe_count_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: 10_000}) do
      goals when is_list(goals) -> length(goals)
      _ -> 0
    end
  end
end
