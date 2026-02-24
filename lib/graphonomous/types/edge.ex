defmodule Graphonomous.Types.Edge do
  @moduledoc "A weighted, typed, decaying edge between knowledge nodes."

  @type edge_type :: :causal | :related | :contradicts | :supports | :derived_from

  @type t :: %__MODULE__{
          id: binary(),
          source_id: binary(),
          target_id: binary(),
          edge_type: edge_type(),
          weight: float(),
          metadata: map(),
          created_at: DateTime.t() | nil,
          last_activated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :source_id,
    :target_id,
    edge_type: :related,
    weight: 0.5,
    metadata: %{},
    created_at: nil,
    last_activated_at: nil
  ]
end
