defmodule Graphonomous.StoreNodeContentValidationTest do
  @moduledoc """
  Regression test for the 2026-04-11 empty-content bug.

  Previously, calling `Graphonomous.MCP.StoreNode.execute/2` (and the v0.4 `act`
  machine) without a `content` field would silently persist a node with
  content = "". This made the graph look like it had saved something while in
  fact losing all the data.

  These tests lock in that:

    1. The MCP `store_node` tool returns an error when content is missing,
       nil, empty, or whitespace-only — and creates no node.
    2. The v0.4 `act` machine with action "store_node" returns the same error.
    3. The internal `Graphonomous.store_node/1` API returns
       `{:error, :content_required}` for the same inputs.
  """

  use ExUnit.Case, async: false

  alias Graphonomous.Graph

  setup do
    {:ok, nodes} = Graph.list_nodes(%{})
    Enum.each(nodes, fn node -> _ = Graph.delete_node(node.id) end)
    :ok
  end

  describe "Graphonomous.MCP.StoreNode.execute/2 — content validation" do
    test "missing content returns error and stores nothing" do
      {:reply, response, _} =
        Graphonomous.MCP.StoreNode.execute(%{"node_type" => "semantic"}, nil)

      payload = decode_response(response)
      assert payload["status"] == "error"
      assert payload["error"] in ["content_required", "store_node_failed"]

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == [], "expected no node to be persisted, got #{length(nodes)}"
    end

    test "nil content returns error and stores nothing" do
      {:reply, response, _} =
        Graphonomous.MCP.StoreNode.execute(
          %{"content" => nil, "node_type" => "semantic"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "error"

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "empty-string content returns error and stores nothing" do
      {:reply, response, _} =
        Graphonomous.MCP.StoreNode.execute(
          %{"content" => "", "node_type" => "semantic"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "error"

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "whitespace-only content returns error and stores nothing" do
      {:reply, response, _} =
        Graphonomous.MCP.StoreNode.execute(
          %{"content" => "   \n\t  ", "node_type" => "semantic"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "error"

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "valid content still stores successfully" do
      {:reply, response, _} =
        Graphonomous.MCP.StoreNode.execute(
          %{"content" => "real knowledge", "node_type" => "semantic"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "stored"
      assert is_binary(payload["node_id"])

      {:ok, [node]} = Graph.list_nodes(%{})
      assert node.content == "real knowledge"
    end
  end

  describe "Graphonomous.MCP.Machines.Act — store_node content validation" do
    test "act(store_node) without content returns error" do
      {:reply, response, _} =
        Graphonomous.MCP.Machines.Act.execute(
          %{"action" => "store_node", "node_type" => "semantic"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "error"

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "act(store_node) with nil content returns error" do
      {:reply, response, _} =
        Graphonomous.MCP.Machines.Act.execute(
          %{"action" => "store_node", "content" => nil, "node_type" => "semantic"},
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "error"

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "act(store_node) with valid content stores successfully" do
      {:reply, response, _} =
        Graphonomous.MCP.Machines.Act.execute(
          %{
            "action" => "store_node",
            "content" => "real knowledge via act",
            "node_type" => "semantic"
          },
          nil
        )

      payload = decode_response(response)
      assert payload["status"] == "stored"

      {:ok, [node]} = Graph.list_nodes(%{})
      assert node.content == "real knowledge via act"
    end
  end

  describe "Graphonomous.Store (Store GenServer) — defense-in-depth" do
    test "insert_node with nil content returns error and stores nothing" do
      assert {:error, {:content_required, _reason}} =
               Graphonomous.Store.insert_node(%{content: nil, node_type: :semantic})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "insert_node with empty content returns error and stores nothing" do
      assert {:error, {:content_required, _reason}} =
               Graphonomous.Store.insert_node(%{content: "", node_type: :semantic})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "insert_node with whitespace content returns error and stores nothing" do
      assert {:error, {:content_required, _reason}} =
               Graphonomous.Store.insert_node(%{content: "  \n\t ", node_type: :semantic})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "insert_node with non-binary content returns error" do
      assert {:error, {:content_required, _reason}} =
               Graphonomous.Store.insert_node(%{content: 123, node_type: :semantic})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "insert_node with valid content stores successfully" do
      assert {:ok, node} =
               Graphonomous.Store.insert_node(%{
                 content: "direct store payload",
                 node_type: :semantic
               })

      assert node.content == "direct store payload"
    end
  end

  describe "Graphonomous.store_node/1 — internal API" do
    test "nil content returns {:error, :content_required}" do
      assert {:error, :content_required} =
               Graphonomous.store_node(%{content: nil, node_type: "semantic"})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "missing content returns {:error, :content_required}" do
      assert {:error, :content_required} =
               Graphonomous.store_node(%{node_type: "semantic"})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "empty string content returns {:error, :content_required}" do
      assert {:error, :content_required} =
               Graphonomous.store_node(%{content: "", node_type: "semantic"})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end

    test "whitespace-only content returns {:error, :content_required}" do
      assert {:error, :content_required} =
               Graphonomous.store_node(%{content: "   ", node_type: "semantic"})

      {:ok, nodes} = Graph.list_nodes(%{})
      assert nodes == []
    end
  end

  # ─── Helpers ────────────────────────────────────────────────────

  defp decode_response(%{content: [%{text: json} | _]}), do: Jason.decode!(json)
  defp decode_response(%{content: [%{"text" => json} | _]}), do: Jason.decode!(json)
  defp decode_response(%{content: json}) when is_binary(json), do: Jason.decode!(json)

  defp decode_response(%{structured_content: %{} = sc}), do: stringify(sc)

  defp decode_response(%{structuredContent: %{} = sc}), do: stringify(sc)

  defp decode_response(other) do
    raise "unexpected response shape: #{inspect(other)}"
  end

  defp stringify(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify(v)}
      {k, v} -> {k, stringify(v)}
    end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other
end
