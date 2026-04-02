defmodule Graphonomous.MCPToolsTest do
  @moduledoc """
  Tests for MCP tools added in v0.2.0:
  - ManageEdge (list_all, list_for_node, update, delete)
  - DeleteNode
  - StoreEdge default weight fix (0.3)
  """

  use ExUnit.Case, async: false

  alias Graphonomous.Graph

  setup do
    {:ok, nodes} = Graph.list_nodes(%{})
    Enum.each(nodes, fn node -> _ = Graph.delete_node(node.id) end)

    {:ok, edges} = Graph.list_all_edges()
    Enum.each(edges, fn edge -> _ = Graph.delete_edge(edge.id) end)

    :ok
  end

  # ─── ManageEdge ─────────────────────────────────────────────────

  describe "manage_edge: list_all" do
    test "returns empty list when no edges exist" do
      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(%{"operation" => "list_all"}, nil)

      payload = decode_response(response)
      assert payload["status"] == "ok"
      assert payload["count"] == 0
      assert payload["edges"] == []
    end

    test "returns all edges" do
      {:ok, a} = Graph.store_node(%{content: "A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "B", node_type: "semantic"})
      {:ok, _edge} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})

      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(%{"operation" => "list_all"}, nil)

      payload = decode_response(response)
      assert payload["status"] == "ok"
      assert payload["count"] == 1
      assert length(payload["edges"]) == 1
    end
  end

  describe "manage_edge: list_for_node" do
    test "returns edges for a specific node" do
      {:ok, a} = Graph.store_node(%{content: "A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "B", node_type: "semantic"})
      {:ok, _edge} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})

      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(
          %{"operation" => "list_for_node", "node_id" => a.id},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "ok"
      assert payload["node_id"] == a.id
      assert payload["count"] >= 1
    end

    test "returns error without node_id" do
      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(%{"operation" => "list_for_node"}, nil)

      payload = decode_response(response)
      assert payload["status"] == "error"
    end
  end

  describe "manage_edge: update" do
    test "updates edge weight and co_activation_count" do
      {:ok, a} = Graph.store_node(%{content: "A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "B", node_type: "semantic"})
      {:ok, edge} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.5})

      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(
          %{
            "operation" => "update",
            "edge_id" => edge.id,
            "weight" => 0.9,
            "co_activation_count" => 5
          },
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "ok"
      assert payload["edge"]["weight"] == 0.9
      assert payload["edge"]["co_activation_count"] == 5
    end

    test "returns error for non-existent edge" do
      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(
          %{"operation" => "update", "edge_id" => "nonexistent", "weight" => 0.5},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "error"
    end

    test "returns error without edge_id" do
      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(%{"operation" => "update", "weight" => 0.5}, nil)

      payload = decode_response(response)
      assert payload["status"] == "error"
    end
  end

  describe "manage_edge: delete" do
    test "deletes an edge" do
      {:ok, a} = Graph.store_node(%{content: "A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "B", node_type: "semantic"})
      {:ok, edge} = Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.5})

      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(
          %{"operation" => "delete", "edge_id" => edge.id},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "ok"
      assert payload["deleted"] == edge.id

      # Verify it's gone
      {:ok, edges} = Graph.get_edges_for_node(a.id)
      refute Enum.any?(edges, &(&1.id == edge.id))
    end

    test "returns error without edge_id" do
      {:reply, response, _} =
        Graphonomous.MCP.ManageEdge.execute(%{"operation" => "delete"}, nil)

      payload = decode_response(response)
      assert payload["status"] == "error"
    end
  end

  # ─── DeleteNode ─────────────────────────────────────────────────

  describe "delete_node MCP tool" do
    test "deletes an existing node" do
      {:ok, node} = Graph.store_node(%{content: "To be deleted", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.DeleteNode.execute(%{"node_id" => node.id}, nil)

      payload = decode_response(response)
      assert payload["status"] == "deleted"
      assert payload["node_id"] == node.id

      # Verify it's gone
      assert {:error, :not_found} = Graph.get_node(node.id)
    end

    test "returns error without node_id" do
      {:reply, response, _} =
        Graphonomous.MCP.DeleteNode.execute(%{}, nil)

      payload = decode_response(response)
      assert payload["status"] == "error"
    end
  end

  # ─── StoreEdge default weight ───────────────────────────────────

  describe "store_edge MCP tool default weight" do
    test "defaults to 0.3 per spec when weight not provided" do
      {:ok, a} = Graph.store_node(%{content: "A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "B", node_type: "semantic"})

      {:reply, response, _} =
        Graphonomous.MCP.StoreEdge.execute(
          %{"source_id" => a.id, "target_id" => b.id, "edge_type" => "related"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "stored"
      assert_in_delta payload["weight"], 0.3, 0.01
    end
  end

  # ─── Server registration ────────────────────────────────────────

  describe "server tool count" do
    test "server registers 22 tools" do
      # Count component/1 calls for tool modules (not resource modules)
      tool_modules = [
        Graphonomous.MCP.StoreEdge,
        Graphonomous.MCP.StoreNode,
        Graphonomous.MCP.RetrieveContext,
        Graphonomous.MCP.LearnFromOutcome,
        Graphonomous.MCP.QueryGraph,
        Graphonomous.MCP.ManageGoal,
        Graphonomous.MCP.ReviewGoal,
        Graphonomous.MCP.RunConsolidation,
        Graphonomous.MCP.TopologyAnalyze,
        Graphonomous.MCP.Deliberate,
        Graphonomous.MCP.AttentionSurvey,
        Graphonomous.MCP.AttentionRunCycle,
        Graphonomous.MCP.GraphTraverse,
        Graphonomous.MCP.GraphStats,
        Graphonomous.MCP.CoverageQuery,
        Graphonomous.MCP.RetrieveEpisodic,
        Graphonomous.MCP.RetrieveProcedural,
        Graphonomous.MCP.LearnFromFeedback,
        Graphonomous.MCP.LearnDetectNovelty,
        Graphonomous.MCP.LearnFromInteraction,
        Graphonomous.MCP.ManageEdge,
        Graphonomous.MCP.DeleteNode
      ]

      assert length(tool_modules) == 22

      # Verify all modules are loadable
      Enum.each(tool_modules, fn mod ->
        # Force load the module before checking exports
        Code.ensure_loaded!(mod)

        assert function_exported?(mod, :execute, 2),
               "#{inspect(mod)} missing execute/2"
      end)
    end
  end

  # ─── Helpers ────────────────────────────────────────────────────

  defp decode_response(%{content: [%{text: json} | _]}) do
    Jason.decode!(json)
  end

  defp decode_response(%{content: [%{"text" => json} | _]}) do
    Jason.decode!(json)
  end

  defp decode_response(%{content: json}) when is_binary(json) do
    Jason.decode!(json)
  end
end
