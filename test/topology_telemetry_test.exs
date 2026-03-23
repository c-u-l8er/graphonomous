defmodule Graphonomous.TopologyTelemetryTest do
  use ExUnit.Case, async: false

  alias Graphonomous.Topology

  test "analyze/1 emits topology analyze + route telemetry for DAG input" do
    attach_topology_telemetry!()

    adjacency = %{
      "a" => MapSet.new(["b"]),
      "b" => MapSet.new(["c"]),
      "c" => MapSet.new()
    }

    result = Topology.analyze(adjacency)
    assert result.routing == :fast
    assert result.max_kappa == 0
    assert result.scc_count == 0

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :topology, :analyze],
                     %{duration_ms: duration_ms, node_count: 3, edge_count: 2},
                     %{scc_count: 0, max_kappa: 0, routing: :fast}
                   },
                   1_000

    assert is_number(duration_ms)
    assert duration_ms >= 0.0

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :topology, :route],
                     %{},
                     %{decision: :fast, max_kappa: 0, trigger: :analyze_topology}
                   },
                   1_000
  end

  test "analyze/1 emits deliberate routing metadata for cyclic input" do
    attach_topology_telemetry!()

    result =
      Topology.analyze([
        {"x", "y"},
        {"y", "z"},
        {"z", "x"}
      ])

    assert result.routing == :deliberate
    assert result.max_kappa >= 1
    assert result.scc_count >= 1

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :topology, :analyze],
                     %{duration_ms: duration_ms, node_count: 3, edge_count: 3},
                     %{scc_count: scc_count, max_kappa: max_kappa, routing: :deliberate}
                   },
                   1_000

    assert is_number(duration_ms)
    assert duration_ms >= 0.0
    assert scc_count >= 1
    assert max_kappa >= 1

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :topology, :route],
                     %{},
                     %{decision: :deliberate, max_kappa: route_kappa, trigger: :analyze_topology}
                   },
                   1_000

    assert route_kappa >= 1
  end

  test "emit_retrieve_route_telemetry/1 emits retrieve_context route event" do
    attach_topology_telemetry!()

    assert :ok =
             Topology.emit_retrieve_route_telemetry(%{
               routing: :deliberate,
               max_kappa: 2
             })

    assert_receive {
                     :telemetry_event,
                     [:graphonomous, :topology, :route],
                     %{},
                     %{decision: :deliberate, max_kappa: 2, trigger: :retrieve_context}
                   },
                   1_000

    refute_receive {:telemetry_event, [:graphonomous, :topology, :analyze], _, _}, 100
  end

  defp attach_topology_telemetry! do
    handler_id = "topology-telemetry-test-#{System.unique_integer([:positive, :monotonic])}"

    events = [
      [:graphonomous, :topology, :analyze],
      [:graphonomous, :topology, :route]
    ]

    parent = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        fn event_name, measurements, metadata, pid ->
          send(pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        parent
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)
  end
end
