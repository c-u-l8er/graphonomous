defmodule Graphonomous.Types.Node do
  @moduledoc """
  A knowledge node in the continual learning graph.
  """

  @typedoc "Supported node categories."
  @type node_type :: :episodic | :semantic | :procedural | :temporal | :outcome | :goal

  @typedoc "How the node was created."
  @type creation_source :: :manual | :inference | :consolidation | :federation

  @typedoc "Memory timescale for consolidation promotion."
  @type timescale :: :fast | :medium | :slow | :glacial

  @typedoc "Primary node record persisted in storage."
  @type t :: %__MODULE__{
          id: binary() | nil,
          content: binary() | nil,
          node_type: node_type(),
          confidence: float(),
          embedding: binary() | nil,
          metadata: map(),
          source: binary() | nil,
          access_count: non_neg_integer(),
          causal_parent_ids: [binary()],
          creation_source: creation_source(),
          timescale: timescale(),
          decay_rate: float() | nil,
          revision_id: binary() | nil,
          superseded_by: binary() | nil,
          q_value: float(),
          q_update_count: non_neg_integer(),
          evidence_count: non_neg_integer(),
          agent_id: binary(),
          region: [number()] | nil,
          forgotten_at: DateTime.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          last_accessed_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :content,
    :embedding,
    :source,
    :decay_rate,
    :revision_id,
    :superseded_by,
    :forgotten_at,
    # SCOPE (OS-012): optional N-dimensional spatial coordinate / region anchor.
    # nil when the node has no spatial position; otherwise a list of numbers.
    :region,
    node_type: :semantic,
    confidence: 0.5,
    metadata: %{},
    access_count: 0,
    causal_parent_ids: [],
    creation_source: :inference,
    timescale: :medium,
    q_value: 0.5,
    q_update_count: 0,
    evidence_count: 0,
    agent_id: "default",
    created_at: nil,
    updated_at: nil,
    last_accessed_at: nil
  ]
end
