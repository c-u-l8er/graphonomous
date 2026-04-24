defmodule Graphonomous.InteractionTraceTest do
  @moduledoc """
  Covers the OS-011 episodic `store/replay` pipeline:

    * `Graphonomous.Types.InteractionTrace.parse/1` validation
    * `Graphonomous.Store` CRUD for traces + edges
    * `Graphonomous.MCP.StoreTrace` (act(action: "store_trace"))
    * `Graphonomous.MCP.ReplayTrace` (retrieve(action: "replay"))
    * `Graphonomous.MCP.Machines.{Act,Retrieve}` routing

  Scope: the in-graph persistence and retrieval halves of the protocol.
  Actual execution of the replay (perceive/encode/act by a body
  provider) is OS-011 §5 and lives outside Graphonomous.
  """
  use ExUnit.Case, async: false

  alias Graphonomous.MCP.Machines.{Act, Retrieve}
  alias Graphonomous.Store
  alias Graphonomous.Types.InteractionTrace

  setup do
    unless Process.whereis(Store) do
      start_supervised!({Store, db_path: "tmp/graphonomous_trace_test.db"})
    end

    :ok
  end

  # -- fixtures --

  defp sample_trace_map(trace_id) do
    %{
      "trace_id" => trace_id,
      "body_subtype" => "browser",
      "provider" => "agent-browser",
      "agent_id" => "WebOperator@test",
      "started_at" => "2026-04-21T14:22:00Z",
      "ended_at" => "2026-04-21T14:22:45Z",
      "environment" => %{
        "browser_family" => "chromium",
        "initial_url" => "https://example.com/expenses"
      },
      "goal" => "Submit weekly expense report",
      "outcome" => "success",
      "metadata" => %{"session" => "test"},
      "edges" => [
        %{
          "edge_id" => 0,
          "state_before" => "sha256:aaa",
          "state_after" => "sha256:bbb",
          "typed_action" => %{"type" => "navigate", "target" => "https://example.com/login"},
          "latency_ms" => 120,
          "outcome_status" => "success",
          "provenance" => %{
            "timestamp" => "2026-04-21T14:22:01Z",
            "capability" => "&body.browser",
            "operation" => "act"
          }
        },
        %{
          "edge_id" => 1,
          "state_before" => "sha256:bbb",
          "state_after" => "sha256:ccc",
          "typed_action" => %{
            "type" => "click",
            "target" => "@submit",
            "semantic_locator" => %{"role" => "button", "name" => "Submit"}
          },
          "latency_ms" => 243,
          "outcome_status" => "success",
          "observed_outcome" => %{"mutation_summary" => "form submitted"},
          "provenance" => %{
            "timestamp" => "2026-04-21T14:22:05Z",
            "capability" => "&body.browser",
            "operation" => "act"
          },
          "surprise_magnitude" => 0.12,
          "surprise_kind" => "other"
        }
      ]
    }
  end

  defp destructive_trace_map(trace_id) do
    %{
      "trace_id" => trace_id,
      "body_subtype" => "os",
      "started_at" => "2026-04-21T10:00:00Z",
      "edges" => [
        %{
          "edge_id" => 0,
          "state_before" => "sha256:os-before",
          "state_after" => "sha256:os-after",
          "typed_action" => %{"type" => "file_write", "target" => "/tmp/x", "params" => %{}},
          "latency_ms" => 12,
          "outcome_status" => "success",
          "authorization" => %{
            "policy_id" => "delegatic://test/deploy",
            "approved_by" => "supervisor@test",
            "approved_at" => "2026-04-21T09:59:00Z",
            "expires_at" => "2026-04-21T10:09:00Z",
            "authorization_token" => "sha256:tok"
          },
          "provenance" => %{"capability" => "&body.os", "operation" => "act"}
        }
      ]
    }
  end

  defp unique_trace_id(prefix \\ "trace") do
    suffix = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    "#{prefix}_#{suffix}"
  end

  # -- parse/1 validation --

  describe "InteractionTrace.parse/1" do
    test "accepts a well-formed trace map" do
      assert {:ok, trace} = InteractionTrace.parse(sample_trace_map("t1"))
      assert trace.trace_id == "t1"
      assert trace.body_subtype == "browser"
      assert length(trace.edges) == 2
      assert InteractionTrace.initial_state_hash(trace) == "sha256:aaa"
      refute InteractionTrace.destructive?(trace)
    end

    test "accepts a JSON string" do
      assert {:ok, trace} = InteractionTrace.parse(Jason.encode!(sample_trace_map("t2")))
      assert trace.trace_id == "t2"
    end

    test "rejects missing trace_id" do
      bad = Map.delete(sample_trace_map("t3"), "trace_id")
      assert {:error, {:invalid_trace, reason}} = InteractionTrace.parse(bad)
      assert reason =~ "trace_id"
    end

    test "rejects empty edges array" do
      bad = %{sample_trace_map("t4") | "edges" => []}
      assert {:error, {:invalid_trace, reason}} = InteractionTrace.parse(bad)
      assert reason =~ "edges"
    end

    test "rejects edge missing state_before" do
      [e0, e1] = sample_trace_map("t5")["edges"]
      bad = %{sample_trace_map("t5") | "edges" => [Map.delete(e0, "state_before"), e1]}
      assert {:error, {:invalid_trace, reason}} = InteractionTrace.parse(bad)
      assert reason =~ "state_before"
    end

    test "flags destructive traces (&body.os file_write, etc.)" do
      assert {:ok, trace} = InteractionTrace.parse(destructive_trace_map("t6"))
      assert InteractionTrace.destructive?(trace)
    end

    test "malformed JSON strings return an invalid_trace error" do
      assert {:error, {:invalid_trace, reason}} = InteractionTrace.parse("not json")
      assert reason =~ "JSON" or reason =~ "json"
    end
  end

  # -- Store CRUD --

  describe "Store trace persistence" do
    test "insert_trace/1 then get_trace/1 round-trips the trace + edges" do
      trace_id = unique_trace_id()
      on_exit(fn -> _ = Store.delete_trace(trace_id) end)

      {:ok, trace} = InteractionTrace.parse(sample_trace_map(trace_id))
      assert {:ok, _} = Store.insert_trace(trace)

      assert {:ok, fetched} = Store.get_trace(trace_id)
      assert fetched.trace_id == trace_id
      assert fetched.body_subtype == "browser"
      assert fetched.outcome == :success
      assert length(fetched.edges) == 2

      [first, second] = fetched.edges
      assert first.edge_id == 0
      assert first.state_before == "sha256:aaa"
      assert first.typed_action["type"] == "navigate"
      assert second.edge_id == 1
      assert second.surprise_magnitude == 0.12
      assert second.surprise_kind == "other"
    end

    test "get_trace/1 returns :not_found for unknown trace_id" do
      assert {:error, :not_found} = Store.get_trace("does_not_exist")
    end

    test "list_traces/1 filters by body_subtype and orders by started_at DESC" do
      older_id = unique_trace_id("older")
      newer_id = unique_trace_id("newer")

      on_exit(fn ->
        _ = Store.delete_trace(older_id)
        _ = Store.delete_trace(newer_id)
      end)

      older_map = sample_trace_map(older_id) |> Map.put("started_at", "2026-01-01T00:00:00Z")
      newer_map = sample_trace_map(newer_id) |> Map.put("started_at", "2026-04-01T00:00:00Z")

      {:ok, older} = InteractionTrace.parse(older_map)
      {:ok, newer} = InteractionTrace.parse(newer_map)
      assert {:ok, _} = Store.insert_trace(older)
      assert {:ok, _} = Store.insert_trace(newer)

      assert {:ok, listed} = Store.list_traces(%{body_subtype: "browser", limit: 100})
      ids = Enum.map(listed, & &1.trace_id)
      assert newer_id in ids
      assert older_id in ids
      assert Enum.find_index(ids, &(&1 == newer_id)) < Enum.find_index(ids, &(&1 == older_id))
    end

    test "list_traces/1 filters by initial_state_hash (procedural cluster lookup)" do
      trace_id = unique_trace_id("cluster")
      on_exit(fn -> _ = Store.delete_trace(trace_id) end)

      {:ok, trace} = InteractionTrace.parse(sample_trace_map(trace_id))
      assert {:ok, _} = Store.insert_trace(trace)

      assert {:ok, [summary]} =
               Store.list_traces(%{initial_state_hash: "sha256:aaa", limit: 10})

      assert summary.trace_id == trace_id
    end

    test "delete_trace/1 cascades to trace_edges" do
      trace_id = unique_trace_id("del")
      {:ok, trace} = InteractionTrace.parse(sample_trace_map(trace_id))
      assert {:ok, _} = Store.insert_trace(trace)
      assert {:ok, _} = Store.get_trace(trace_id)

      assert :ok = Store.delete_trace(trace_id)
      assert {:error, :not_found} = Store.get_trace(trace_id)
    end
  end

  # -- MCP machine routing --

  describe "act(action: store_trace) routing" do
    test "routes valid trace to StoreTrace and returns a stored payload" do
      trace_id = unique_trace_id("mcp")
      on_exit(fn -> _ = Store.delete_trace(trace_id) end)

      params = %{
        action: "store_trace",
        interaction_trace: Jason.encode!(sample_trace_map(trace_id))
      }

      assert {:reply, response, _frame} = Act.execute(params, %{})
      assert response.structured_content.status == "stored"
      assert response.structured_content.trace_id == trace_id
      assert response.structured_content.edge_count == 2
      assert response.structured_content.initial_state_hash == "sha256:aaa"
      refute response.structured_content.destructive

      assert {:ok, _} = Store.get_trace(trace_id)
    end

    test "returns an error payload for malformed trace" do
      params = %{action: "store_trace", interaction_trace: ~s({"not": "a trace"})}
      assert {:reply, response, _frame} = Act.execute(params, %{})
      assert response.structured_content.status == "error"
      assert response.structured_content.error == "invalid_trace"
      assert response.isError == true
    end

    test "returns an error payload when interaction_trace is absent" do
      params = %{action: "store_trace"}
      assert {:reply, response, _frame} = Act.execute(params, %{})
      assert response.structured_content.status == "error"
      assert response.isError == true
    end
  end

  describe "retrieve(action: replay) routing" do
    test "returns a destructive-warning replay manifest for os.file_write traces" do
      trace_id = unique_trace_id("replay")
      on_exit(fn -> _ = Store.delete_trace(trace_id) end)

      {:ok, trace} = InteractionTrace.parse(destructive_trace_map(trace_id))
      assert {:ok, _} = Store.insert_trace(trace)

      params = %{action: "replay", trace_id: trace_id}
      assert {:reply, response, _frame} = Retrieve.execute(params, %{})
      assert response.structured_content.status == "ok"
      assert response.structured_content.count == 1

      [returned] = response.structured_content.traces
      assert returned.trace_id == trace_id
      assert returned.replay_manifest.destructive == true
      assert returned.replay_manifest.re_authorization_required == true
      assert is_binary(returned.replay_manifest.note)

      [edge] = returned.replay_manifest.edges
      assert edge.edge_id == 0
      assert edge.typed_action["type"] == "file_write"
    end

    test "finds traces by initial state_hash (procedural lookup)" do
      trace_id = unique_trace_id("replay-cluster")
      on_exit(fn -> _ = Store.delete_trace(trace_id) end)

      {:ok, trace} = InteractionTrace.parse(sample_trace_map(trace_id))
      assert {:ok, _} = Store.insert_trace(trace)

      params = %{action: "replay", state_hash: "sha256:aaa", body_subtype: "browser", limit: 5}
      assert {:reply, response, _frame} = Retrieve.execute(params, %{})
      assert response.structured_content.status == "ok"
      assert response.structured_content.state_hash == "sha256:aaa"
      assert response.structured_content.count >= 1

      assert Enum.any?(response.structured_content.traces, &(&1.trace_id == trace_id))
    end

    test "returns not_found for unknown trace_id" do
      params = %{action: "replay", trace_id: "does_not_exist_123"}
      assert {:reply, response, _frame} = Retrieve.execute(params, %{})
      assert response.structured_content.status == "error"
      assert response.structured_content.error == "not_found"
      assert response.isError == true
    end

    test "returns a missing_lookup_key error when neither trace_id nor state_hash provided" do
      params = %{action: "replay"}
      assert {:reply, response, _frame} = Retrieve.execute(params, %{})
      assert response.structured_content.status == "error"
      assert response.structured_content.error == "missing_lookup_key"
      assert response.isError == true
    end
  end
end
