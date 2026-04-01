defmodule Graphonomous.OpenSentience.PipelineEnforcerTest do
  use ExUnit.Case, async: true

  alias Graphonomous.OpenSentience.PipelineEnforcer

  setup do
    name = :"enforcer_#{System.unique_integer([:positive])}"
    {:ok, pid} = PipelineEnforcer.start_link(name: name, session_id: "test-session")
    %{enforcer: name, pid: pid}
  end

  describe "retrieve-before-write enforcement" do
    test "blocks store_node before retrieve_context", %{enforcer: e} do
      assert {:block, reason, missing} = PipelineEnforcer.check_prerequisites(e, :store_node)
      assert :retrieve_context in missing
      assert reason =~ "Prerequisites not met"
    end

    test "blocks store_edge before retrieve_context", %{enforcer: e} do
      assert {:block, _reason, missing} = PipelineEnforcer.check_prerequisites(e, :store_edge)
      assert :retrieve_context in missing
    end

    test "blocks learn_from_feedback before retrieve_context", %{enforcer: e} do
      assert {:block, _reason, missing} =
               PipelineEnforcer.check_prerequisites(e, :learn_from_feedback)

      assert :retrieve_context in missing
    end

    test "allows store_node after retrieve_context", %{enforcer: e} do
      :ok = PipelineEnforcer.record_completion(e, :retrieve_context)
      assert :ok = PipelineEnforcer.check_prerequisites(e, :store_node)
    end

    test "allows store_edge after retrieve_context", %{enforcer: e} do
      :ok = PipelineEnforcer.record_completion(e, :retrieve_context)
      assert :ok = PipelineEnforcer.check_prerequisites(e, :store_edge)
    end
  end

  describe "topology-before-deliberate enforcement" do
    test "blocks deliberate before topology_analyze", %{enforcer: e} do
      # deliberate is not in the write or read lists, so it will also
      # not be blocked by the any-write rule. It has its own specific rule.
      assert {:block, _reason, missing} = PipelineEnforcer.check_prerequisites(e, :deliberate)
      assert :topology_analyze in missing
    end

    test "allows deliberate after topology_analyze", %{enforcer: e} do
      :ok = PipelineEnforcer.record_completion(e, :topology_analyze)
      assert :ok = PipelineEnforcer.check_prerequisites(e, :deliberate)
    end
  end

  describe "read operations are lenient" do
    test "allows retrieve_context without prerequisites", %{enforcer: e} do
      assert :ok = PipelineEnforcer.check_prerequisites(e, :retrieve_context)
    end

    test "allows query_graph without prerequisites", %{enforcer: e} do
      assert :ok = PipelineEnforcer.check_prerequisites(e, :query_graph)
    end

    test "allows graph_stats without prerequisites", %{enforcer: e} do
      assert :ok = PipelineEnforcer.check_prerequisites(e, :graph_stats)
    end

    test "allows graph_traverse without prerequisites", %{enforcer: e} do
      assert :ok = PipelineEnforcer.check_prerequisites(e, :graph_traverse)
    end

    test "allows topology_analyze without prerequisites", %{enforcer: e} do
      assert :ok = PipelineEnforcer.check_prerequisites(e, :topology_analyze)
    end

    test "allows coverage_query without prerequisites", %{enforcer: e} do
      assert :ok = PipelineEnforcer.check_prerequisites(e, :coverage_query)
    end
  end

  describe "chained prerequisites" do
    test "learn_from_outcome requires both retrieve_context and execute_action", %{enforcer: e} do
      assert {:block, _reason, missing} =
               PipelineEnforcer.check_prerequisites(e, :learn_from_outcome)

      assert :retrieve_context in missing
      assert :execute_action in missing
    end

    test "learn_from_outcome allowed after full pipeline", %{enforcer: e} do
      :ok = PipelineEnforcer.record_completion(e, :retrieve_context)
      :ok = PipelineEnforcer.record_completion(e, :execute_action)
      assert :ok = PipelineEnforcer.check_prerequisites(e, :learn_from_outcome)
    end
  end

  describe "record_completion and completed_stages" do
    test "records a stage with metadata", %{enforcer: e} do
      :ok = PipelineEnforcer.record_completion(e, :retrieve_context, %{node_count: 5})
      stages = PipelineEnforcer.completed_stages(e)
      assert Map.has_key?(stages, :retrieve_context)
      assert stages[:retrieve_context].metadata == %{node_count: 5}
    end
  end

  describe "session reset" do
    test "clears completed stages and re-blocks previously allowed tools", %{enforcer: e} do
      :ok = PipelineEnforcer.record_completion(e, :retrieve_context)
      assert :ok = PipelineEnforcer.check_prerequisites(e, :store_node)

      :ok = PipelineEnforcer.reset(e)

      assert {:block, _reason, _missing} =
               PipelineEnforcer.check_prerequisites(e, :store_node)

      assert PipelineEnforcer.completed_stages(e) == %{}
    end
  end

  describe "audit log" do
    test "records blocked and completed events", %{enforcer: e} do
      _result = PipelineEnforcer.check_prerequisites(e, :store_node)
      :ok = PipelineEnforcer.record_completion(e, :retrieve_context)

      log = PipelineEnforcer.audit_log(e)
      assert length(log) == 2

      [blocked, completed] = log
      assert blocked.event_type == :pipeline_stage_blocked
      assert blocked.tool_name == :store_node
      assert completed.event_type == :pipeline_stage_completed
      assert completed.tool_name == :retrieve_context
    end

    test "reset adds an audit entry", %{enforcer: e} do
      :ok = PipelineEnforcer.reset(e)
      log = PipelineEnforcer.audit_log(e)
      assert length(log) == 1
      assert hd(log).event_type == :session_reset
    end
  end
end
