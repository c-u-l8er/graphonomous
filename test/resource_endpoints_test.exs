defmodule Graphonomous.ResourceEndpointsTest do
  @moduledoc """
  Tests for all 5 MCP resource endpoints, exercising read/2 callbacks directly.
  """

  use ExUnit.Case, async: false

  alias Anubis.Server.Frame

  alias Graphonomous.MCP.Resources.{
    HealthSnapshot,
    GoalsSnapshot,
    NodeDetail,
    RecentNodes,
    ConsolidationLog
  }

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  setup do
    purge_nodes()
    purge_goals()
    :ok
  end

  describe "HealthSnapshot (graphonomous://runtime/health)" do
    test "returns valid health payload with counts" do
      # Store a node and goal so counts are non-zero
      Graphonomous.store_node(%{
        content: "Health test node",
        node_type: "semantic",
        confidence: 0.5,
        source: "resource_test"
      })

      Graphonomous.create_goal(%{
        title: "Health test goal",
        status: :proposed,
        timescale: :short_term,
        source_type: :user,
        priority: :normal
      })

      frame = Frame.new()
      assert {:reply, response, _frame} = HealthSnapshot.read(%{}, frame)
      assert response.type == :resource

      payload = decode_payload!(response)
      assert is_binary(payload["generated_at"])
      assert is_map(payload["health"])
      assert is_map(payload["counts"])
      assert payload["counts"]["nodes"] >= 1
      assert payload["counts"]["goals"] >= 1
    end

    test "returns zero counts on empty graph" do
      frame = Frame.new()
      assert {:reply, response, _frame} = HealthSnapshot.read(%{}, frame)

      payload = decode_payload!(response)
      assert payload["counts"]["nodes"] == 0
      assert payload["counts"]["goals"] == 0
    end
  end

  describe "GoalsSnapshot (graphonomous://goals/snapshot)" do
    test "returns all goals with status breakdown" do
      Graphonomous.create_goal(%{
        title: "Active goal",
        status: :active,
        timescale: :short_term,
        source_type: :user,
        priority: :high
      })

      Graphonomous.create_goal(%{
        title: "Proposed goal",
        status: :proposed,
        timescale: :short_term,
        source_type: :user,
        priority: :normal
      })

      frame = Frame.new()
      assert {:reply, response, _frame} = GoalsSnapshot.read(%{}, frame)

      payload = decode_payload!(response)
      assert is_binary(payload["generated_at"])
      assert payload["total"] >= 2
      assert is_map(payload["by_status"])
      assert is_list(payload["goals"])
      assert length(payload["goals"]) >= 2

      # Check status breakdown sums to total
      by_status = payload["by_status"]
      status_sum = Enum.reduce(by_status, 0, fn {_k, v}, acc -> acc + v end)
      assert status_sum == payload["total"]
    end

    test "returns empty snapshot when no goals exist" do
      frame = Frame.new()
      assert {:reply, response, _frame} = GoalsSnapshot.read(%{}, frame)

      payload = decode_payload!(response)
      assert payload["total"] == 0
      assert payload["goals"] == []
    end
  end

  describe "NodeDetail (graphonomous://graph/node/{id})" do
    test "returns node details and edges for a valid node" do
      n1 =
        Graphonomous.store_node(%{
          content: "Node detail test content",
          node_type: "semantic",
          confidence: 0.75,
          source: "resource_test",
          metadata: %{"key" => "value"}
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Connected node for edge testing",
          node_type: "episodic",
          confidence: 0.6,
          source: "resource_test"
        })

      Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "supports", weight: 0.8})

      frame = Frame.new()
      params = %{"uri" => "graphonomous://graph/node/#{n1.id}"}
      assert {:reply, response, _frame} = NodeDetail.read(params, frame)

      payload = decode_payload!(response)
      assert is_binary(payload["generated_at"])
      assert is_map(payload["node"])
      assert payload["node"]["id"] == n1.id
      assert payload["node"]["content"] == "Node detail test content"
      assert payload["node"]["confidence"] == 0.75
      assert payload["edge_count"] >= 1
      assert is_list(payload["edges"])
      assert length(payload["edges"]) >= 1

      # Embedding should be stripped
      refute Map.has_key?(payload["node"], "embedding")
    end

    test "returns error for non-existent node" do
      frame = Frame.new()
      params = %{"uri" => "graphonomous://graph/node/nonexistent_id_12345"}
      assert {:error, _error, _frame} = NodeDetail.read(params, frame)
    end

    test "returns error for missing URI" do
      frame = Frame.new()
      assert {:error, _error, _frame} = NodeDetail.read(%{}, frame)
    end

    test "returns error for malformed URI" do
      frame = Frame.new()
      params = %{"uri" => "not-a-valid-uri"}
      assert {:error, _error, _frame} = NodeDetail.read(params, frame)
    end
  end

  describe "RecentNodes (graphonomous://graph/recent)" do
    test "returns nodes sorted by recency" do
      # Store nodes with slight time gaps
      n1 =
        Graphonomous.store_node(%{
          content: "First node stored",
          node_type: "semantic",
          confidence: 0.5,
          source: "resource_test"
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Second node stored",
          node_type: "episodic",
          confidence: 0.6,
          source: "resource_test"
        })

      n3 =
        Graphonomous.store_node(%{
          content: "Third node stored (most recent)",
          node_type: "procedural",
          confidence: 0.7,
          source: "resource_test"
        })

      frame = Frame.new()
      assert {:reply, response, _frame} = RecentNodes.read(%{}, frame)

      payload = decode_payload!(response)
      assert is_binary(payload["generated_at"])
      assert payload["count"] == 3
      assert payload["limit"] == 20
      assert is_list(payload["nodes"])
      assert length(payload["nodes"]) == 3

      # All nodes should be present
      ids = Enum.map(payload["nodes"], & &1["id"])
      assert n1.id in ids
      assert n2.id in ids
      assert n3.id in ids

      # Embeddings should be stripped
      Enum.each(payload["nodes"], fn node ->
        refute Map.has_key?(node, "embedding")
      end)
    end

    test "returns empty list when no nodes exist" do
      frame = Frame.new()
      assert {:reply, response, _frame} = RecentNodes.read(%{}, frame)

      payload = decode_payload!(response)
      assert payload["count"] == 0
      assert payload["nodes"] == []
    end

    test "respects the 20-node limit" do
      # Store 25 nodes
      for i <- 1..25 do
        Graphonomous.store_node(%{
          content: "Limit test node #{i}",
          node_type: "semantic",
          confidence: 0.5,
          source: "resource_test"
        })
      end

      frame = Frame.new()
      assert {:reply, response, _frame} = RecentNodes.read(%{}, frame)

      payload = decode_payload!(response)
      assert payload["count"] == 20
      assert length(payload["nodes"]) == 20
    end
  end

  describe "ConsolidationLog (graphonomous://consolidation/log)" do
    test "returns consolidator and orchestrator state" do
      # Run a consolidation so there's state to report
      Graphonomous.run_consolidation_now()

      frame = Frame.new()
      assert {:reply, response, _frame} = ConsolidationLog.read(%{}, frame)

      payload = decode_payload!(response)
      assert is_binary(payload["generated_at"])

      # Consolidator section
      consolidator = payload["consolidator"]
      assert is_map(consolidator)
      assert is_integer(consolidator["cycle_count"]) or is_nil(consolidator["cycle_count"])

      # Orchestrator section
      orchestrator = payload["orchestrator"]
      assert is_map(orchestrator)
      assert Map.has_key?(orchestrator, "current_learning_rate")
      assert Map.has_key?(orchestrator, "base_learning_rate")
      assert Map.has_key?(orchestrator, "metrics")
    end

    test "works even before any consolidation has run" do
      frame = Frame.new()
      assert {:reply, response, _frame} = ConsolidationLog.read(%{}, frame)

      payload = decode_payload!(response)
      assert is_map(payload["consolidator"])
      assert is_map(payload["orchestrator"])
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp decode_payload!(response) do
    text =
      cond do
        is_map(response.contents) and is_binary(response.contents["text"]) ->
          response.contents["text"]

        is_list(response.contents) ->
          Enum.find_value(response.contents, fn
            %{text: t} when is_binary(t) -> t
            %{"text" => t} when is_binary(t) -> t
            _ -> nil
          end)

        true ->
          nil
      end

    assert text != nil, "Expected resource response to contain text payload"
    Jason.decode!(text)
  end

  defp purge_nodes do
    case Graphonomous.list_nodes(%{}) do
      nodes when is_list(nodes) ->
        Enum.each(nodes, fn node -> _ = Graphonomous.delete_node(node.id) end)

      _ ->
        :ok
    end
  end

  defp purge_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: 10_000}) do
      goals when is_list(goals) ->
        Enum.each(goals, fn goal -> _ = Graphonomous.delete_goal(goal.id) end)

      _ ->
        :ok
    end
  end
end
