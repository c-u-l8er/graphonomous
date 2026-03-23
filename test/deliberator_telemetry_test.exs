defmodule Graphonomous.DeliberatorTelemetryTest do
  use ExUnit.Case, async: false

  alias Graphonomous.Deliberator

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_nodes()

    on_exit(fn ->
      purge_nodes()
    end)

    :ok
  end

  test "crystallize/3 emits telemetry with status :ok on successful write_back" do
    attach_crystallization_telemetry!()

    conclusion = %{
      content: "Crystallized test conclusion for cyclic region.",
      confidence: 0.82,
      source_scc_id: "scc-ok",
      source_kappa: 2,
      fault_lines_examined: [%{source: "a", target: "b"}]
    }

    scc = %{
      id: "scc-ok",
      nodes: ["a", "b", "c"],
      kappa: 2,
      fault_line_edges: [%{source: "a", target: "b"}]
    }

    assert {:ok, node_id} =
             Deliberator.crystallize(conclusion, scc,
               write_back: true,
               source: "test:deliberator_telemetry"
             )

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :deliberator, :crystallization],
                     %{count: 1, duration_ms: duration_ms},
                     %{
                       status: :ok,
                       source_scc_id: "scc-ok",
                       source_kappa: 2,
                       confidence: confidence,
                       reason: nil
                     }
                   },
                   1_000

    assert is_number(duration_ms)
    assert duration_ms >= 0.0
    assert_in_delta(confidence, 0.82, 0.0001)

    assert :ok = Graphonomous.delete_node(node_id)
  end

  test "crystallize/3 emits telemetry with status :skipped when write_back is disabled" do
    attach_crystallization_telemetry!()

    conclusion = %{
      content: "No write-back expected.",
      confidence: 0.64,
      source_scc_id: "scc-skip",
      source_kappa: 1,
      fault_lines_examined: []
    }

    scc = %{
      id: "scc-skip",
      nodes: ["x", "y"],
      kappa: 1,
      fault_line_edges: []
    }

    assert :skipped = Deliberator.crystallize(conclusion, scc, write_back: false)

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :deliberator, :crystallization],
                     %{count: 0, duration_ms: duration_ms},
                     %{
                       status: :skipped,
                       source_scc_id: "scc-skip",
                       source_kappa: 1,
                       confidence: confidence,
                       reason: reason
                     }
                   },
                   1_000

    assert duration_ms >= 0.0
    assert_in_delta(confidence, 0.64, 0.0001)
    assert reason == ":write_back_disabled"
  end

  defp attach_crystallization_telemetry! do
    handler_id = "deliberator-telemetry-test-#{System.unique_integer([:positive, :monotonic])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:graphonomous, :deliberator, :crystallization],
        fn event_name, measurements, metadata, pid ->
          send(pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        parent
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)
  end

  defp purge_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        Enum.each(nodes, fn node ->
          _ = Graphonomous.delete_node(node.id)
        end)

      _ ->
        :ok
    end
  end
end
