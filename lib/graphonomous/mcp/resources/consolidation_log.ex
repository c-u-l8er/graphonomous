defmodule Graphonomous.MCP.Resources.ConsolidationLog do
  @moduledoc """
  Read-only MCP resource exposing consolidation history and current state.

  URI: `graphonomous://consolidation/log`

  Since the Consolidator doesn't persist a full history log, this resource
  exposes the current consolidator state (cycle count, last run, config)
  and the Orchestrator's plasticity metrics for a complete picture of
  memory maintenance status.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "graphonomous://consolidation/log",
    name: "graphonomous_consolidation_log",
    mime_type: "application/json"

  alias Anubis.Server.Response

  @impl true
  def description do
    "Consolidation history, current state, and orchestrator plasticity metrics."
  end

  @impl true
  def read(_params, frame) do
    consolidator_info = safe_consolidator_info()
    orchestrator_info = safe_orchestrator_info()

    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      consolidator: serialize_consolidator(consolidator_info),
      orchestrator: serialize_orchestrator(orchestrator_info)
    }

    response =
      Response.resource()
      |> Response.text(Jason.encode!(payload))

    {:reply, response, frame}
  end

  defp safe_consolidator_info do
    Graphonomous.consolidator_info()
  rescue
    _ -> %{}
  end

  defp safe_orchestrator_info do
    Graphonomous.orchestrator_info()
  rescue
    _ -> %{}
  end

  defp serialize_consolidator(info) when is_map(info) do
    %{
      cycle_count: Map.get(info, :cycle_count, 0),
      last_run_at: serialize_datetime(Map.get(info, :last_run_at)),
      interval_ms: Map.get(info, :interval_ms),
      decay_rate: Map.get(info, :decay_rate),
      prune_threshold: Map.get(info, :prune_threshold),
      merge_similarity: Map.get(info, :merge_similarity)
    }
  end

  defp serialize_orchestrator(info) when is_map(info) do
    %{
      current_learning_rate: Map.get(info, :current_learning_rate),
      base_learning_rate: Map.get(info, :base_learning_rate),
      metrics: Map.get(info, :metrics, %{}),
      last_computed_at: serialize_datetime(Map.get(info, :last_computed_at)),
      counters: Map.get(info, :counters, %{})
    }
  end

  defp serialize_datetime(nil), do: nil
  defp serialize_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_datetime(other), do: other
end
