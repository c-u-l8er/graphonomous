defmodule Graphonomous.OpenSentience.PipelineEnforcer do
  @moduledoc """
  OS-008 Phase 1: Pipeline stage enforcement.

  Tracks which pipeline stages have completed in the current session and
  blocks tool calls whose prerequisites have not been met. Read operations
  are always allowed; write operations require prior retrieval.

  ## Prerequisite rules

  | Tool call                | Must complete first               |
  |--------------------------|-----------------------------------|
  | Any write tool           | `retrieve_context`                |
  | `deliberate`             | `topology_analyze`                |
  | `execute_action`         | `coverage_query`                  |
  | `learn_from_outcome`     | `execute_action`                  |
  | Session complete         | `store_node`                      |
  | Sprint advance           | quality gate pass                 |

  The enforcer is lenient on read operations — retrieval, query, stats,
  and traversal tools never require prerequisites.
  """

  use GenServer

  require Logger

  alias Graphonomous.OpenSentience.HarnessAudit

  # -- Tool classification --

  @write_tools [
    :store_node,
    :store_edge,
    :learn_from_outcome,
    :learn_from_feedback,
    :learn_from_interaction
  ]

  @read_tools [
    :retrieve_context,
    :retrieve_episodic,
    :retrieve_procedural,
    :query_graph,
    :graph_stats,
    :graph_traverse,
    :topology_analyze,
    :coverage_query,
    :attention_survey,
    :attention_run_cycle,
    :run_consolidation,
    :learn_detect_novelty
  ]

  # -- Prerequisite definitions --

  # {match_key, required_completions}
  # match_key can be:
  #   {:call, tool_atom}    — specific tool
  #   {:any, :write}        — any write tool
  #   {:session, :complete} — session completion
  #   {:sprint, :advance}   — sprint advancement
  @prerequisites [
    {{:any, :write}, [{:completed, :retrieve_context}]},
    {{:call, :deliberate}, [{:completed, :topology_analyze}]},
    {{:call, :execute_action}, [{:completed, :coverage_query}]},
    {{:call, :learn_from_outcome}, [{:completed, :execute_action}]},
    {{:session, :complete}, [{:completed, :store_node}]},
    {{:sprint, :advance}, [{:completed, :quality_gate, result: :pass}]}
  ]

  @type stage_key :: atom()
  @type completion_entry :: %{stage: stage_key(), completed_at: DateTime.t(), metadata: map()}

  @type state :: %{
          session_id: binary(),
          completed_stages: %{stage_key() => completion_entry()},
          audit_log: [HarnessAudit.t()]
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks whether all prerequisites for `tool_name` are satisfied.

  Returns `:ok` if the tool may proceed, or `{:block, reason, missing_stages}`
  if prerequisites are missing.
  """
  @spec check_prerequisites(GenServer.server(), atom()) ::
          :ok | {:block, binary(), [atom()]}
  def check_prerequisites(server \\ __MODULE__, tool_name) do
    GenServer.call(server, {:check_prerequisites, tool_name})
  end

  @doc """
  Records that a pipeline stage has completed.
  """
  @spec record_completion(GenServer.server(), atom(), map()) :: :ok
  def record_completion(server \\ __MODULE__, stage, metadata \\ %{}) do
    GenServer.call(server, {:record_completion, stage, metadata})
  end

  @doc """
  Resets all session state — clears completed stages and audit log.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  @doc """
  Returns the current audit log.
  """
  @spec audit_log(GenServer.server()) :: [HarnessAudit.t()]
  def audit_log(server \\ __MODULE__) do
    GenServer.call(server, :audit_log)
  end

  @doc """
  Returns the set of completed stages.
  """
  @spec completed_stages(GenServer.server()) :: %{atom() => completion_entry()}
  def completed_stages(server \\ __MODULE__) do
    GenServer.call(server, :completed_stages)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    {:ok,
     %{
       session_id: session_id,
       completed_stages: %{},
       audit_log: []
     }}
  end

  @impl true
  def handle_call({:check_prerequisites, tool_name}, _from, state) do
    case do_check(tool_name, state.completed_stages) do
      :ok ->
        {:reply, :ok, state}

      {:block, reason, missing} ->
        entry =
          HarnessAudit.new(:pipeline_stage_blocked, state.session_id,
            tool_name: tool_name,
            metadata: %{reason: reason, missing_stages: missing}
          )

        Logger.warning("[OS-008] Blocked #{tool_name}: #{reason} (missing: #{inspect(missing)})")

        {:reply, {:block, reason, missing}, %{state | audit_log: [entry | state.audit_log]}}
    end
  end

  @impl true
  def handle_call({:record_completion, stage, metadata}, _from, state) do
    entry =
      HarnessAudit.new(:pipeline_stage_completed, state.session_id,
        tool_name: stage,
        metadata: metadata
      )

    completion = %{
      stage: stage,
      completed_at: DateTime.utc_now(),
      metadata: metadata
    }

    new_stages = Map.put(state.completed_stages, stage, completion)

    Logger.debug("[OS-008] Stage completed: #{stage}")

    {:reply, :ok, %{state | completed_stages: new_stages, audit_log: [entry | state.audit_log]}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    entry = HarnessAudit.new(:session_reset, state.session_id)

    {:reply, :ok, %{state | completed_stages: %{}, audit_log: [entry | state.audit_log]}}
  end

  @impl true
  def handle_call(:audit_log, _from, state) do
    {:reply, Enum.reverse(state.audit_log), state}
  end

  @impl true
  def handle_call(:completed_stages, _from, state) do
    {:reply, state.completed_stages, state}
  end

  ## Internal logic

  defp do_check(tool_name, completed) do
    if read_tool?(tool_name) do
      :ok
    else
      missing = collect_missing(tool_name, completed)

      if missing == [] do
        :ok
      else
        reason = "Prerequisites not met for #{tool_name}"
        {:block, reason, missing}
      end
    end
  end

  defp collect_missing(tool_name, completed) do
    @prerequisites
    |> Enum.filter(fn {match_key, _reqs} -> matches?(match_key, tool_name) end)
    |> Enum.flat_map(fn {_key, reqs} -> reqs end)
    |> Enum.reject(fn req -> requirement_met?(req, completed) end)
    |> Enum.map(&requirement_stage/1)
    |> Enum.uniq()
  end

  defp matches?({:call, name}, tool_name), do: name == tool_name
  defp matches?({:any, :write}, tool_name), do: write_tool?(tool_name)
  defp matches?({:session, _}, _tool_name), do: false
  defp matches?({:sprint, _}, _tool_name), do: false

  defp requirement_met?({:completed, stage}, completed), do: Map.has_key?(completed, stage)

  defp requirement_met?({:completed, stage, opts}, completed) do
    case Map.get(completed, stage) do
      nil ->
        false

      entry ->
        Enum.all?(opts, fn {k, v} -> Map.get(entry.metadata, k) == v end)
    end
  end

  defp requirement_stage({:completed, stage}), do: stage
  defp requirement_stage({:completed, stage, _opts}), do: stage

  defp write_tool?(name), do: name in @write_tools
  defp read_tool?(name), do: name in @read_tools

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
