defmodule Graphonomous.MCP.ReplayTrace do
  @moduledoc """
  MCP tool for retrieving an OS-011 `InteractionTrace` from episodic
  memory in a form ready for replay by a `&body.*` provider.

  This is Graphonomous's half of `&memory.episodic.replay`: it emits the
  trace + replay manifest. Actual execution of the replay (perceive,
  encode_state, act, check state_hash) is the body provider's
  responsibility per OS-011 §5.4.

  Lookup modes:

    * `trace_id` — exact lookup of one trace.
    * `state_hash` — return up to `limit` traces that start at the given
      state hash (procedural clustering). Useful for "what do I know how
      to do from this state?"

  For each trace the response includes a `replay_manifest` summarizing
  the edge plan, whether it contains destructive actions (which require
  fresh authorization per §4.4), and a `re_authorization_required` flag
  so callers surface this to their governance layer.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Types.InteractionTrace

  schema do
    field(:trace_id, :string, description: "Exact trace id to return for replay")

    field(:state_hash, :string,
      description: "State hash to search for (returns all traces starting at this state)"
    )

    field(:body_subtype, :string,
      description: "Optional filter: only return traces for this &body subtype"
    )

    field(:limit, :number,
      description: "Max traces to return when searching by state_hash (default 5)"
    )
  end

  @default_limit 5

  @impl true
  def execute(params, frame) do
    trace_id = get_param(params, :trace_id)
    state_hash = get_param(params, :state_hash)
    body_subtype = get_param(params, :body_subtype)
    limit = parse_pos_int(get_param(params, :limit), @default_limit)

    cond do
      is_binary(trace_id) and trace_id != "" ->
        fetch_single(trace_id, frame)

      is_binary(state_hash) and state_hash != "" ->
        fetch_by_state_hash(state_hash, body_subtype, limit, frame)

      true ->
        error(frame, "missing_lookup_key", "provide trace_id or state_hash")
    end
  end

  defp fetch_single(trace_id, frame) do
    case Graphonomous.Store.get_trace(trace_id) do
      {:ok, trace} ->
        payload = %{
          status: "ok",
          count: 1,
          traces: [serialize(trace)]
        }

        {:reply, Response.tool() |> Response.structured(payload), frame}

      {:error, :not_found} ->
        error(frame, "not_found", "no trace with trace_id=#{trace_id}")

      {:error, reason} ->
        error(frame, "replay_lookup_failed", inspect(reason))
    end
  end

  defp fetch_by_state_hash(state_hash, body_subtype, limit, frame) do
    filters =
      %{initial_state_hash: state_hash, limit: limit}
      |> maybe_put(:body_subtype, body_subtype)

    case Graphonomous.Store.list_traces(filters) do
      {:ok, summaries} ->
        # Hydrate each one so callers can actually replay.
        traces =
          summaries
          |> Enum.map(& &1.trace_id)
          |> Enum.map(&Graphonomous.Store.get_trace/1)
          |> Enum.flat_map(fn
            {:ok, t} -> [t]
            _ -> []
          end)

        payload = %{
          status: "ok",
          count: length(traces),
          state_hash: state_hash,
          traces: Enum.map(traces, &serialize/1)
        }

        {:reply, Response.tool() |> Response.structured(payload), frame}

      {:error, reason} ->
        error(frame, "replay_lookup_failed", inspect(reason))
    end
  end

  defp serialize(%InteractionTrace{} = trace) do
    destructive? = InteractionTrace.destructive?(trace)

    %{
      trace_id: trace.trace_id,
      body_subtype: trace.body_subtype,
      provider: trace.provider,
      agent_id: trace.agent_id,
      started_at: trace.started_at,
      ended_at: trace.ended_at,
      goal: trace.goal,
      outcome: Atom.to_string(trace.outcome),
      edge_count: length(trace.edges),
      initial_state_hash: InteractionTrace.initial_state_hash(trace),
      replay_manifest: %{
        destructive: destructive?,
        re_authorization_required: destructive?,
        note:
          if(destructive?,
            do:
              "Destructive edges require fresh authorization at replay time (OS-011 §4.4). Prior authorization is audit evidence, not replay permission.",
            else: nil
          ),
        edges:
          trace.edges
          |> Enum.sort_by(& &1.edge_id)
          |> Enum.map(fn edge ->
            %{
              edge_id: edge.edge_id,
              state_before: edge.state_before,
              state_after: edge.state_after,
              typed_action: edge.typed_action,
              latency_ms: edge.latency_ms,
              outcome_status: Atom.to_string(edge.outcome_status),
              observed_outcome: edge.observed_outcome,
              provenance: edge.provenance,
              surprise_magnitude: edge.surprise_magnitude,
              surprise_kind: edge.surprise_kind
            }
          end)
      }
    }
  end

  defp maybe_put(map, _key, v) when is_nil(v) or v == "", do: map
  defp maybe_put(map, key, v) when is_binary(v), do: Map.put(map, key, v)
  defp maybe_put(map, _key, _v), do: map

  defp parse_pos_int(v, _default) when is_integer(v) and v > 0, do: v
  defp parse_pos_int(v, _default) when is_float(v) and v > 0, do: trunc(v)

  defp parse_pos_int(v, default) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_pos_int(_, default), do: default

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
