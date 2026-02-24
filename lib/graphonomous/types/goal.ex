defmodule Graphonomous.Types.Goal do
  @moduledoc """
  Durable intent record for the GoalGraph layer.

  A goal represents a persistent objective the agent is trying to achieve over
  time, along with progress, confidence, and linkage to supporting/causal
  knowledge nodes.
  """

  @typedoc "Lifecycle state of a goal."
  @type status :: :proposed | :active | :blocked | :completed | :abandoned

  @typedoc "Goal horizon/time scale."
  @type timescale :: :immediate | :short_term | :medium_term | :long_term

  @typedoc "How the goal was created."
  @type source_type :: :user | :system | :inferred | :policy

  @typedoc "Priority bucket for scheduling and retrieval."
  @type priority :: :low | :normal | :high | :critical

  @typedoc "Durable intent object."
  @type t :: %__MODULE__{
          id: binary() | nil,
          title: binary() | nil,
          description: binary() | nil,
          status: status(),
          timescale: timescale(),
          source_type: source_type(),
          priority: priority(),
          confidence: float(),
          progress: float(),
          owner: binary() | nil,
          tags: [binary()],
          constraints: map(),
          success_criteria: map(),
          metadata: map(),
          linked_node_ids: [binary()],
          parent_goal_id: binary() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          due_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          last_reviewed_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :title,
    :description,
    :owner,
    :parent_goal_id,
    status: :proposed,
    timescale: :short_term,
    source_type: :user,
    priority: :normal,
    confidence: 0.5,
    progress: 0.0,
    tags: [],
    constraints: %{},
    success_criteria: %{},
    metadata: %{},
    linked_node_ids: [],
    created_at: nil,
    updated_at: nil,
    due_at: nil,
    completed_at: nil,
    last_reviewed_at: nil
  ]
end
