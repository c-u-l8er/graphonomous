defmodule Graphonomous.AttentionIntegrationTest do
  use ExUnit.Case, async: false

  alias Graphonomous.{Attention, Store}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_nodes()
    purge_goals()
    :ok = Attention.deactivate()

    on_exit(fn ->
      _ = Attention.deactivate()
      purge_nodes()
      purge_goals()
    end)

    :ok
  end

  test "act-mode cycle dispatches explore for low-confidence stale context and enriches graph" do
    stale = DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second)

    {:ok, n1} =
      Store.insert_node(%{
        content: "Retention churn segment alpha baseline stale",
        node_type: :semantic,
        confidence: 0.12,
        source: "test:attention_integration",
        created_at: stale,
        updated_at: stale,
        last_accessed_at: stale
      })

    {:ok, n2} =
      Store.insert_node(%{
        content: "Retention churn segment beta baseline stale",
        node_type: :semantic,
        confidence: 0.14,
        source: "test:attention_integration",
        created_at: stale,
        updated_at: stale,
        last_accessed_at: stale
      })

    {:ok, n3} =
      Store.insert_node(%{
        content: "Retention churn segment gamma baseline stale",
        node_type: :semantic,
        confidence: 0.16,
        source: "test:attention_integration",
        created_at: stale,
        updated_at: stale,
        last_accessed_at: stale
      })

    goal =
      Graphonomous.create_goal(%{
        title: "Retention churn baseline update",
        description: "Refresh stale retention evidence before action",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :low,
        linked_node_ids: [n1.id, n2.id, n3.id]
      })

    assert goal.status == :active

    before_nodes = Graphonomous.list_nodes(%{})
    before_count = length(before_nodes)

    {:ok, cycle} = Attention.run_cycle(autonomy_override: :act)

    assert is_map(cycle)
    assert cycle.items_surveyed >= 1
    assert is_list(cycle.dispatches)

    assert length(cycle.dispatches) >= 1

    assert Enum.any?(cycle.dispatches, fn d ->
             Map.get(d, :mode) in [:explore, :focus, :act, :escalate, :propose]
           end)

    assert Enum.any?(cycle.dispatches, fn d ->
             Map.get(d, :result) in [:ok, :deferred, :escalated]
           end)

    after_nodes = Graphonomous.list_nodes(%{})
    after_count = length(after_nodes)

    assert after_count >= before_count
  end

  test "attention_survey MCP tool returns ranked attention payload" do
    _goal =
      Graphonomous.create_goal(%{
        title: "Revenue model sanity-check",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :normal
      })

    frame = Anubis.Server.Frame.new()

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.AttentionSurvey.execute(%{"include_idle" => true}, frame)

    payload = extract_payload!(response)

    assert getv(payload, :status) == "ok"
    assert is_list(getv(payload, :attention_items))
    assert getv(payload, :autonomy_level) in ["observe", "advise", "act"]

    assert is_integer(getv(payload, :next_heartbeat_in_ms)) or
             is_nil(getv(payload, :next_heartbeat_in_ms))
  end

  test "attention_run_cycle MCP tool triggers one cycle and returns cycle + status" do
    _goal =
      Graphonomous.create_goal(%{
        title: "Pipeline diagnostics review",
        status: :active,
        source_type: :user,
        timescale: :short_term,
        priority: :normal
      })

    frame = Anubis.Server.Frame.new()

    assert {:reply, response, _frame_after} =
             Graphonomous.MCP.AttentionRunCycle.execute(
               %{"autonomy_override" => "observe"},
               frame
             )

    payload = extract_payload!(response)

    assert getv(payload, :status) == "ok"

    cycle = getv(payload, :cycle)
    assert is_map(cycle)
    assert is_binary(getv(cycle, :cycle_id))
    assert is_list(getv(cycle, :dispatches))
    assert is_integer(getv(cycle, :items_surveyed))
    assert is_integer(getv(cycle, :items_dispatched))

    attention_status = getv(payload, :attention_status)
    assert is_map(attention_status)
    assert getv(attention_status, :autonomy_level) in ["observe", "advise", "act"]
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

  defp purge_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: 10_000}) do
      goals when is_list(goals) ->
        Enum.each(goals, fn goal ->
          _ = Graphonomous.delete_goal(goal.id)
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
        from_content =
          response
          |> getv(:content, nil)
          |> extract_payload_from_contents()

        from_contents =
          response
          |> getv(:contents, nil)
          |> extract_payload_from_contents()

        payload = if is_map(from_content), do: from_content, else: from_contents

        if is_map(payload) do
          payload
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
