defmodule Graphonomous.Types.Outcome do
  @moduledoc """
  Outcome report used by the causal feedback loop.

  Each outcome links an executed action to the knowledge nodes that influenced it,
  so confidence can be updated over time.
  """

  @type status :: :success | :partial_success | :failure | :timeout

  @type t :: %__MODULE__{
          action_id: binary(),
          status: status(),
          confidence: float(),
          causal_node_ids: [binary()],
          evidence: map(),
          observed_at: DateTime.t()
        }

  defstruct [
    :action_id,
    :status,
    :causal_node_ids,
    :observed_at,
    confidence: 0.5,
    evidence: %{}
  ]
end
