defmodule Graphonomous.Types.Node do
  @moduledoc """
  A knowledge node in the continual learning graph.
  """

  @typedoc "Supported node categories."
  @type node_type :: :episodic | :semantic | :procedural

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
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          last_accessed_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :content,
    :embedding,
    :source,
    node_type: :semantic,
    confidence: 0.5,
    metadata: %{},
    access_count: 0,
    created_at: nil,
    updated_at: nil,
    last_accessed_at: nil
  ]
end
