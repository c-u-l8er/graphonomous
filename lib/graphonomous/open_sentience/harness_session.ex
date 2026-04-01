defmodule Graphonomous.OpenSentience.HarnessSession do
  @moduledoc """
  Lightweight session wrapper for OS-008 harness enforcement.

  Holds session identity, autonomy level, and the audit trail
  produced by PipelineEnforcer decisions.
  """

  alias Graphonomous.OpenSentience.HarnessAudit

  @type t :: %__MODULE__{
          session_id: binary(),
          goal_id: binary() | nil,
          autonomy_level: atom(),
          started_at: DateTime.t(),
          audit_log: [HarnessAudit.t()]
        }

  @enforce_keys [:session_id, :started_at]
  defstruct [
    :session_id,
    :started_at,
    goal_id: nil,
    autonomy_level: :supervised,
    audit_log: []
  ]

  @doc """
  Creates a new harness session.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      session_id: Keyword.get(opts, :session_id, generate_id()),
      goal_id: Keyword.get(opts, :goal_id),
      autonomy_level: Keyword.get(opts, :autonomy_level, :supervised),
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Appends an audit entry to the session log.
  """
  @spec append_audit(t(), HarnessAudit.t()) :: t()
  def append_audit(%__MODULE__{} = session, %HarnessAudit{} = entry) do
    %{session | audit_log: [entry | session.audit_log]}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
