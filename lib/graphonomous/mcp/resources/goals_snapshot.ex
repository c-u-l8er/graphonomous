defmodule Graphonomous.MCP.Resources.GoalsSnapshot do
  @moduledoc """
  Read-only MCP resource exposing a durable snapshot of GoalGraph state.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "graphonomous://goals/snapshot",
    name: "graphonomous_goals_snapshot",
    mime_type: "application/json"

  alias Anubis.Server.Response

  @default_limit 10_000

  @impl true
  def description do
    "Durable GoalGraph snapshot with totals, status breakdown, and serialized goal records."
  end

  @impl true
  def read(_params, frame) do
    goals = fetch_goals()

    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total: length(goals),
      by_status: count_by_status(goals),
      goals: Enum.map(goals, &serialize_goal/1)
    }

    response =
      Response.resource()
      |> Response.text(Jason.encode!(payload))

    {:reply, response, frame}
  end

  defp fetch_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: @default_limit}) do
      goals when is_list(goals) -> goals
      _ -> []
    end
  end

  defp count_by_status(goals) do
    Enum.reduce(goals, %{}, fn goal, acc ->
      status =
        goal
        |> Map.get(:status, :unknown)
        |> to_string()

      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp serialize_goal(goal) when is_map(goal) do
    goal_map =
      if Map.has_key?(goal, :__struct__) do
        Map.from_struct(goal)
      else
        goal
      end

    Enum.into(goal_map, %{}, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, v} -> {k, v}
    end)
  end
end
