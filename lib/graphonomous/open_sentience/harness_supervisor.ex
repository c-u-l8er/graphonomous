defmodule Graphonomous.OpenSentience.HarnessSupervisor do
  @moduledoc """
  DynamicSupervisor for OS-008 harness sessions.

  Manages the lifecycle of PipelineEnforcer processes — one per active session.
  Added to the main Graphonomous.Application supervision tree.
  """

  use DynamicSupervisor

  alias Graphonomous.OpenSentience.PipelineEnforcer

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new PipelineEnforcer session under this supervisor.

  ## Options

    * `:session_id` — identifier for the session (auto-generated if omitted)
    * `:name` — registered name for the enforcer process (required for lookup)

  """
  @spec start_session(keyword()) :: DynamicSupervisor.on_start_child()
  def start_session(opts \\ []) do
    child_spec = {PipelineEnforcer, opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Terminates a harness session by its pid.
  """
  @spec stop_session(pid()) :: :ok | {:error, :not_found}
  def stop_session(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
