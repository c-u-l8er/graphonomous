defmodule Graphonomous.Types.Edge do
  @moduledoc "A weighted, typed, decaying edge between knowledge nodes."

  @type edge_type ::
          :causal
          | :causes
          | :resolves
          | :related
          | :related_to
          | :part_of
          | :follows
          | :contradicts
          | :supersedes
          | :depends_on
          | :similar_to
          | :supports
          | :derived_from
          | :temporal_before
          | :temporal_after
          | :co_occurs

  @type t :: %__MODULE__{
          id: binary(),
          source_id: binary(),
          target_id: binary(),
          edge_type: edge_type(),
          weight: float(),
          metadata: map(),
          co_activation_count: non_neg_integer(),
          decay_rate: float() | nil,
          created_at: DateTime.t() | nil,
          last_activated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :source_id,
    :target_id,
    :decay_rate,
    edge_type: :related,
    weight: 0.3,
    metadata: %{},
    co_activation_count: 0,
    created_at: nil,
    last_activated_at: nil
  ]
end
