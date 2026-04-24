defmodule Graphonomous.MCP.StoreTrace do
  @moduledoc """
  MCP tool for storing an OS-011 `InteractionTrace` in episodic memory.

  This is the `&memory.episodic.store(trace)` operation: persists a full
  perception-action-outcome sequence so the same trace can later be
  retrieved, replayed by a `&body.*` provider, or clustered into
  procedural skills. See `opensentience.org/docs/spec/OS-011-EMBODIMENT.md`
  §5 and §10.1.

  Payload: the `interaction_trace` field accepts either a JSON string or
  an already-decoded object and must validate against
  `Graphonomous.Types.InteractionTrace`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Types.InteractionTrace

  schema do
    field(:interaction_trace, :string,
      required: true,
      description: "InteractionTrace as a JSON string (or object). See OS-011 §4."
    )
  end

  @impl true
  def execute(params, frame) do
    raw = get_param(params, :interaction_trace)

    with {:ok, map} <- coerce_to_map(raw),
         {:ok, trace} <- InteractionTrace.parse(map),
         {:ok, _} <- Graphonomous.Store.insert_trace(trace) do
      payload = %{
        status: "stored",
        trace_id: trace.trace_id,
        body_subtype: trace.body_subtype,
        edge_count: length(trace.edges),
        initial_state_hash: InteractionTrace.initial_state_hash(trace),
        outcome: Atom.to_string(trace.outcome),
        destructive: InteractionTrace.destructive?(trace)
      }

      {:reply,
       Response.tool()
       |> Response.structured(payload), frame}
    else
      {:error, {:invalid_trace, reason}} ->
        error(frame, "invalid_trace", reason)

      {:error, :invalid_payload} ->
        error(frame, "invalid_payload", "interaction_trace must be a JSON object or JSON string")

      {:error, reason} ->
        error(frame, "store_trace_failed", inspect(reason))
    end
  end

  defp coerce_to_map(nil), do: {:error, :invalid_payload}

  defp coerce_to_map(v) when is_map(v), do: {:ok, v}

  defp coerce_to_map(v) when is_binary(v) do
    case Jason.decode(String.trim(v)) do
      {:ok, m} when is_map(m) -> {:ok, m}
      _ -> {:error, :invalid_payload}
    end
  end

  defp coerce_to_map(_), do: {:error, :invalid_payload}

  defp error(frame, code, reason) do
    payload = %{status: "error", error: code, reason: reason}

    {:reply,
     Response.tool()
     |> Response.structured(payload)
     |> Map.put(:isError, true), frame}
  end

  defp get_param(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end
end
