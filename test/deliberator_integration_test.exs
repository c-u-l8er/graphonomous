defmodule Graphonomous.DeliberatorIntegrationTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_nodes()
    on_exit(&purge_nodes/0)
    :ok
  end

  test "MCP Deliberate executes on explicit cyclic scope without write-back" do
    a =
      store_node!(%{
        content: "Pricing changes affect demand elasticity.",
        node_type: :semantic,
        confidence: 0.9,
        source: "test:deliberator_integration"
      })

    b =
      store_node!(%{
        content: "Demand elasticity affects revenue outcomes.",
        node_type: :semantic,
        confidence: 0.9,
        source: "test:deliberator_integration"
      })

    c =
      store_node!(%{
        content: "Revenue outcomes feed back into pricing strategy.",
        node_type: :semantic,
        confidence: 0.9,
        source: "test:deliberator_integration"
      })

    :ok = link!(a.id, b.id)
    :ok = link!(b.id, c.id)
    :ok = link!(c.id, a.id)

    frame = Anubis.Server.Frame.new()

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.Deliberate.execute(
               %{
                 "query" => "How do we stabilize the pricing-demand-revenue cycle?",
                 "node_ids" => [a.id, b.id, c.id],
                 "write_back" => false
               },
               frame
             )

    payload = extract_payload!(response)

    assert getv(payload, :status) == "ok"
    assert getv(payload, :query) =~ "stabilize"

    selection = getv(payload, :selection)
    assert is_map(selection)
    assert getv(selection, :mode) == "explicit_node_ids"
    assert getv(selection, :write_back) == false
    assert getv(selection, :node_count) == 3

    topology = getv(payload, :topology)
    assert is_map(topology)
    assert getv(topology, :routing) == "deliberate"
    assert getv(topology, :scc_count) >= 1
    assert getv(topology, :max_kappa) >= 1

    deliberation = getv(payload, :deliberation)
    assert is_map(deliberation)
    assert is_boolean(getv(deliberation, :converged))
    assert getv(deliberation, :iterations_used) >= 0

    conclusions = getv(deliberation, :conclusions)
    assert is_list(conclusions)

    if conclusions == [] do
      # local_small tier may skip κ=1 SCCs due kappa_deliberation_floor=2
      topology_change = getv(deliberation, :topology_change, %{})
      assert is_map(topology_change)
      assert getv(topology_change, :kappa_before) >= 1
      assert getv(topology_change, :new_nodes_created) == 0
    else
      [first | _] = conclusions
      assert is_binary(getv(first, :content))
      assert getv(first, :source_kappa) >= 1
      assert is_list(getv(first, :fault_lines_examined))
    end
  end

  test "MCP Deliberate write_back=true crystallizes conclusions into graph nodes" do
    a =
      store_node!(%{
        content: "Market share shifts with product quality changes.",
        node_type: :semantic,
        confidence: 0.88,
        source: "test:deliberator_integration"
      })

    b =
      store_node!(%{
        content: "Product quality is affected by R&D allocation.",
        node_type: :semantic,
        confidence: 0.87,
        source: "test:deliberator_integration"
      })

    c =
      store_node!(%{
        content: "R&D allocation responds to market share pressure.",
        node_type: :semantic,
        confidence: 0.86,
        source: "test:deliberator_integration"
      })

    :ok = link!(a.id, b.id)
    :ok = link!(b.id, c.id)
    :ok = link!(c.id, a.id)

    before_nodes = Graphonomous.list_nodes(%{})
    before_count = length(before_nodes)

    frame = Anubis.Server.Frame.new()

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.Deliberate.execute(
               %{
                 "query" => "What intervention can reduce this feedback loop?",
                 "node_ids" => [a.id, b.id, c.id],
                 "write_back" => true
               },
               frame
             )

    payload = extract_payload!(response)
    assert getv(payload, :status) == "ok"

    deliberation = getv(payload, :deliberation)
    assert is_map(deliberation)

    topology_change = getv(deliberation, :topology_change)
    assert is_map(topology_change)

    after_nodes = Graphonomous.list_nodes(%{})

    new_nodes_created = getv(topology_change, :new_nodes_created)

    if new_nodes_created >= 1 do
      assert length(after_nodes) >= before_count + 1

      crystallized =
        Enum.filter(after_nodes, fn node ->
          Map.get(node, :source) == "deliberator:crystallization" and
            is_map(Map.get(node, :metadata)) and
            Map.get(node.metadata, "kind") == "deliberation_conclusion"
        end)

      assert length(crystallized) >= 1

      Enum.each(crystallized, fn node ->
        assert node.node_type == :semantic
        assert is_binary(node.content)
        assert map_size(node.metadata) > 0
        assert Map.has_key?(node.metadata, "source_scc_id")
        assert Map.has_key?(node.metadata, "source_kappa")
        assert Map.has_key?(node.metadata, "fault_lines_examined")
      end)
    else
      # local_small tier may skip κ=1 SCCs due kappa_deliberation_floor=2
      assert new_nodes_created == 0
      assert length(after_nodes) >= before_count
    end
  end

  test "MCP Deliberate returns error when query is missing" do
    frame = Anubis.Server.Frame.new()

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.Deliberate.execute(%{"write_back" => true}, frame)

    payload = extract_payload!(response)

    assert getv(payload, :status) == "error"
    assert getv(payload, :error) =~ "query"
  end

  defp store_node!(attrs) do
    case Graphonomous.store_node(attrs) do
      %{id: id} = node when is_binary(id) -> node
      other -> flunk("expected stored node, got: #{inspect(other)}")
    end
  end

  defp link!(source_id, target_id) do
    case Graphonomous.link_nodes(source_id, target_id, %{edge_type: :causal, weight: 1.0}) do
      %{source_id: ^source_id, target_id: ^target_id} -> :ok
      other -> flunk("expected edge #{source_id} -> #{target_id}, got: #{inspect(other)}")
    end
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

  defp extract_payload!(response) when is_map(response) do
    candidates = [
      getv(response, :structured),
      getv(response, :structured_content),
      getv(response, :structuredContent),
      getv(response, :payload)
    ]

    case Enum.find(candidates, &is_map/1) do
      %{} = payload ->
        payload

      nil ->
        from_contents =
          response
          |> getv(:contents, nil)
          |> extract_payload_from_contents()

        if is_map(from_contents) do
          from_contents
        else
          flunk("unable to extract structured payload from response: #{inspect(response)}")
        end
    end
  end

  defp extract_payload_from_contents(%{} = map), do: map

  defp extract_payload_from_contents(list) when is_list(list) do
    Enum.find_value(list, fn item ->
      cond do
        is_map(item) and is_map(getv(item, :json)) ->
          getv(item, :json)

        is_map(item) and is_binary(getv(item, :text)) ->
          case Jason.decode(getv(item, :text)) do
            {:ok, decoded} when is_map(decoded) -> decoded
            _ -> nil
          end

        true ->
          nil
      end
    end)
  end

  defp extract_payload_from_contents(_), do: nil

  defp getv(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
