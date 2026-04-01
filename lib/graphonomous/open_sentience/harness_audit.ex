defmodule Graphonomous.OpenSentience.HarnessAudit do
  @moduledoc """
  Audit entry struct for OS-008 harness events.

  Records pipeline enforcement decisions — both completions and blocks —
  for observability and post-hoc analysis.
  """

  @type event_type ::
          :pipeline_stage_completed
          | :pipeline_stage_blocked
          | :session_reset

  @type t :: %__MODULE__{
          event_type: event_type(),
          session_id: binary(),
          tool_name: atom() | nil,
          timestamp: DateTime.t(),
          metadata: map()
        }

  @enforce_keys [:event_type, :session_id, :timestamp]
  defstruct [
    :event_type,
    :session_id,
    :tool_name,
    timestamp: nil,
    metadata: %{}
  ]

  @doc """
  Creates a new audit entry with the current UTC timestamp.
  """
  @spec new(event_type(), binary(), keyword()) :: t()
  def new(event_type, session_id, opts \\ []) do
    %__MODULE__{
      event_type: event_type,
      session_id: session_id,
      tool_name: Keyword.get(opts, :tool_name),
      timestamp: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
