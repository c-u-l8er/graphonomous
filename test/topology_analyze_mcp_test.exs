defmodule Graphonomous.TopologyAnalyzeMCPTest do
  use ExUnit.Case, async: false

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

  test "topology_analyze returns schema-compliant deliberate topology for explicit cyclic scope" do
    a =
      store_node!(%{
        content: "Pricing pressure affects market share.",
        node_type: :semantic,
        confidence: 0.9,
        source: "test:topology_analyze_mcp"
      })

    b =
      store_node!(%{
        content: "Market share shifts influence revenue.",
        node_type: :semantic,
        confidence: 0.9,
        source: "test:topology_analyze_mcp"
      })

    c =
      store_node!(%{
        content: "Revenue outcomes feed back into pricing strategy.",
        node_type: :semantic,
        confidence: 0.9,
        source: "test:topology_analyze_mcp"
      })

    d =
      store_node!(%{
        content: "Headquarters location is static profile metadata.",
        node_type: :semantic,
        confidence: 0.5,
        source: "test:topology_analyze_mcp"
      })

    :ok = link!(a.id, b.id)
    :ok = link!(b.id, c.id)
    :ok = link!(c.id, a.id)

    frame = Anubis.Server.Frame.new()

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.TopologyAnalyze.execute(
               %{"node_ids" => [a.id, b.id, c.id, d.id]},
               frame
             )

    payload = extract_payload!(response)

    assert getv(payload, :status) == "ok"

    key_strings =
      payload
      |> Map.keys()
      |> Enum.map(&to_string/1)

    assert "routing" in key_strings
    assert "max_kappa" in key_strings
    assert "scc_count" in key_strings
    assert "sccs" in key_strings
    assert "dag_nodes" in key_strings
    assert "recommendation" in key_strings

    assert getv(payload, :routing) == "deliberate"
    assert getv(payload, :max_kappa) >= 1
    assert getv(payload, :scc_count) >= 1
    assert getv(payload, :selection) == "explicit_node_ids"
    assert getv(payload, :node_count) == 4

    dag_nodes = getv(payload, :dag_nodes, [])
    assert is_list(dag_nodes)
    assert d.id in dag_nodes

    sccs = getv(payload, :sccs, [])
    assert is_list(sccs)
    assert length(sccs) >= 1

    Enum.each(sccs, fn scc ->
      assert is_binary(getv(scc, :id))
      assert is_list(getv(scc, :nodes, []))
      assert is_integer(getv(scc, :kappa))
      assert is_boolean(getv(scc, :approximate))
      assert getv(scc, :routing) in ["fast", "deliberate"]
      assert is_map(getv(scc, :deliberation_budget))
      assert is_list(getv(scc, :fault_line_edges, []))

      Enum.each(getv(scc, :fault_line_edges, []), fn edge ->
        assert is_binary(getv(edge, :source))
        assert is_binary(getv(edge, :target))
      end)
    end)
  end

  test "topology_analyze is deterministic for identical explicit node_ids input" do
    a =
      store_node!(%{
        content: "Alpha causal source.",
        node_type: :semantic,
        confidence: 0.8,
        source: "test:topology_analyze_mcp"
      })

    b =
      store_node!(%{
        content: "Beta causal relay.",
        node_type: :semantic,
        confidence: 0.8,
        source: "test:topology_analyze_mcp"
      })

    c =
      store_node!(%{
        content: "Gamma causal sink.",
        node_type: :semantic,
        confidence: 0.8,
        source: "test:topology_analyze_mcp"
      })

    :ok = link!(a.id, b.id)
    :ok = link!(b.id, c.id)
    :ok = link!(c.id, a.id)

    params = %{"node_ids" => [c.id, a.id, b.id]}

    assert {:reply, response1, _} =
             Graphonomous.MCP.TopologyAnalyze.execute(params, Anubis.Server.Frame.new())

    assert {:reply, response2, _} =
             Graphonomous.MCP.TopologyAnalyze.execute(params, Anubis.Server.Frame.new())

    payload1 = extract_payload!(response1)
    payload2 = extract_payload!(response2)

    assert normalize_payload_for_compare(payload1) == normalize_payload_for_compare(payload2)
  end

  test "topology_analyze query mode resolves retrieval subgraph and echoes query" do
    a =
      store_node!(%{
        content: "Pricing loop pressure affects demand elasticity.",
        node_type: :semantic,
        confidence: 0.86,
        source: "test:topology_analyze_mcp"
      })

    b =
      store_node!(%{
        content: "Demand elasticity influences revenue sensitivity.",
        node_type: :semantic,
        confidence: 0.84,
        source: "test:topology_analyze_mcp"
      })

    c =
      store_node!(%{
        content: "Revenue sensitivity feeds back into pricing loop decisions.",
        node_type: :semantic,
        confidence: 0.85,
        source: "test:topology_analyze_mcp"
      })

    :ok = link!(a.id, b.id)
    :ok = link!(b.id, c.id)
    :ok = link!(c.id, a.id)

    query = "pricing loop demand revenue feedback"

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.TopologyAnalyze.execute(
               %{"query" => query},
               Anubis.Server.Frame.new()
             )

    payload = extract_payload!(response)

    assert getv(payload, :status) == "ok"
    assert getv(payload, :query) == query
    assert getv(payload, :selection) == "query_retrieval_subgraph"
    assert is_integer(getv(payload, :node_count))
    assert getv(payload, :node_count) >= 1
    assert getv(payload, :routing) in ["fast", "deliberate"]
  end

  defp normalize_payload_for_compare(payload) do
    %{
      status: getv(payload, :status),
      routing: getv(payload, :routing),
      max_kappa: getv(payload, :max_kappa),
      scc_count: getv(payload, :scc_count),
      selection: getv(payload, :selection),
      node_count: getv(payload, :node_count),
      recommendation: getv(payload, :recommendation),
      dag_nodes:
        payload
        |> getv(:dag_nodes, [])
        |> Enum.sort(),
      sccs:
        payload
        |> getv(:sccs, [])
        |> Enum.map(fn scc ->
          %{
            id: getv(scc, :id),
            nodes: scc |> getv(:nodes, []) |> Enum.sort(),
            kappa: getv(scc, :kappa),
            approximate: getv(scc, :approximate),
            routing: getv(scc, :routing),
            deliberation_budget: getv(scc, :deliberation_budget, %{}),
            fault_line_edges:
              scc
              |> getv(:fault_line_edges, [])
              |> Enum.map(fn edge -> {getv(edge, :source), getv(edge, :target)} end)
              |> Enum.sort()
          }
        end)
        |> Enum.sort_by(& &1.id)
    }
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
