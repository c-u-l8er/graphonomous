defmodule Graphonomous.Types.Entity do
  @moduledoc """
  An identity anchor in the knowledge graph.

  Entities are distinct from knowledge nodes — they represent stable identities
  (people, projects, tools, organizations) that accumulate facts over time.
  They do not have confidence scores or decay because identity is not a claim.
  """

  @type entity_type :: :person | :project | :tool | :organization | :concept | :place | :other

  @type t :: %__MODULE__{
          id: binary() | nil,
          name: binary(),
          canonical_name: binary(),
          entity_type: entity_type(),
          aliases: [binary()],
          metadata: map(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :name,
    :created_at,
    :updated_at,
    canonical_name: "",
    entity_type: :other,
    aliases: [],
    metadata: %{}
  ]
end
