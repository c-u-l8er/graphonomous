defmodule Graphonomous.Types.InteractionTrace do
  @moduledoc """
  OS-011 Embodiment Protocol `InteractionTrace` — canonical record of a
  perception-action cycle produced by any `&body.*` subtype (e.g.
  `&body.browser`, `&body.os`).

  A trace is a sequence of `TraceEdge`s, each carrying a
  `(state_before, typed_action, state_after)` triple plus outcome and
  provenance. Traces form the input to `&memory.episodic.store` and the
  payload returned by `&memory.episodic.replay`.

  See `opensentience.org/docs/spec/OS-011-EMBODIMENT.md` §4 for the
  authoritative schema.
  """

  alias __MODULE__

  @type outcome :: :success | :partial | :failure | :aborted
  @type edge_status :: :success | :partial | :failure | :blocked | :timeout

  @type t :: %InteractionTrace{
          trace_id: binary(),
          body_subtype: binary(),
          provider: binary() | nil,
          agent_id: binary() | nil,
          started_at: binary() | nil,
          ended_at: binary() | nil,
          environment: map(),
          edges: [InteractionTrace.Edge.t()],
          goal: binary() | nil,
          outcome: outcome(),
          metadata: map()
        }

  defstruct trace_id: nil,
            body_subtype: "browser",
            provider: nil,
            agent_id: nil,
            started_at: nil,
            ended_at: nil,
            environment: %{},
            edges: [],
            goal: nil,
            outcome: :success,
            metadata: %{}

  defmodule Edge do
    @moduledoc "One step in an InteractionTrace — see OS-011 §4.2."

    @type t :: %__MODULE__{
            edge_id: non_neg_integer(),
            state_before: binary(),
            state_after: binary(),
            typed_action: map(),
            latency_ms: non_neg_integer() | nil,
            outcome_status: Graphonomous.Types.InteractionTrace.edge_status(),
            observed_outcome: map() | nil,
            authorization: map() | nil,
            provenance: map(),
            surprise_magnitude: float() | nil,
            surprise_kind: binary() | nil
          }

    defstruct edge_id: 0,
              state_before: nil,
              state_after: nil,
              typed_action: %{},
              latency_ms: nil,
              outcome_status: :success,
              observed_outcome: nil,
              authorization: nil,
              provenance: %{},
              surprise_magnitude: nil,
              surprise_kind: nil
  end

  @valid_outcomes ~w(success partial failure aborted)
  @valid_edge_statuses ~w(success partial failure blocked timeout)

  @doc """
  Parse a trace from decoded-JSON (or JSON string) into a validated struct.

  Returns `{:ok, trace}` or `{:error, {:invalid_trace, reason}}`.
  """
  @spec parse(map() | binary()) :: {:ok, t()} | {:error, {:invalid_trace, binary()}}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> parse(map)
      {:ok, _other} -> {:error, {:invalid_trace, "trace must be a JSON object"}}
      {:error, err} -> {:error, {:invalid_trace, "malformed JSON: #{inspect(err)}"}}
    end
  end

  def parse(map) when is_map(map) do
    with {:ok, trace_id} <- require_string(map, "trace_id"),
         {:ok, body_subtype} <- require_string(map, "body_subtype"),
         {:ok, started_at} <- require_string(map, "started_at"),
         {:ok, edges_raw} <- require_list(map, "edges"),
         {:ok, edges} <- parse_edges(edges_raw) do
      {:ok,
       %InteractionTrace{
         trace_id: trace_id,
         body_subtype: body_subtype,
         provider: get_string(map, "provider"),
         agent_id: get_string(map, "agent_id"),
         started_at: started_at,
         ended_at: get_string(map, "ended_at"),
         environment: get_map(map, "environment"),
         edges: edges,
         goal: get_string(map, "goal"),
         outcome: normalize_outcome(get_string(map, "outcome") || "success"),
         metadata: get_map(map, "metadata")
       }}
    else
      {:error, {:invalid_trace, _} = tagged} -> {:error, tagged}
      {:error, reason} when is_binary(reason) -> {:error, {:invalid_trace, reason}}
      {:error, other} -> {:error, {:invalid_trace, inspect(other)}}
    end
  end

  def parse(_), do: {:error, {:invalid_trace, "trace must be a map or JSON string"}}

  defp parse_edges([]), do: {:error, {:invalid_trace, "edges must be a non-empty array"}}

  defp parse_edges(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {raw, idx}, {:ok, acc} ->
      case parse_edge(raw, idx) do
        {:ok, edge} -> {:cont, {:ok, [edge | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, rev} -> {:ok, Enum.reverse(rev)}
      other -> other
    end
  end

  defp parse_edge(map, idx) when is_map(map) do
    with {:ok, state_before} <- require_string(map, "state_before"),
         {:ok, state_after} <- require_string(map, "state_after"),
         {:ok, typed_action} <- require_map(map, "typed_action"),
         :ok <- require_action_shape(typed_action) do
      {:ok,
       %Edge{
         edge_id: get_integer(map, "edge_id", idx),
         state_before: state_before,
         state_after: state_after,
         typed_action: typed_action,
         latency_ms: get_integer(map, "latency_ms", nil),
         outcome_status: normalize_edge_status(get_string(map, "outcome_status") || "success"),
         observed_outcome: Map.get(map, "observed_outcome"),
         authorization: Map.get(map, "authorization"),
         provenance: get_map(map, "provenance"),
         surprise_magnitude: get_float(map, "surprise_magnitude", nil),
         surprise_kind: get_string(map, "surprise_kind")
       }}
    else
      {:error, reason} ->
        {:error, {:invalid_trace, "edge[#{idx}]: #{reason}"}}
    end
  end

  defp parse_edge(_, idx),
    do: {:error, {:invalid_trace, "edge[#{idx}] must be an object"}}

  defp require_action_shape(%{"type" => type}) when is_binary(type) and type != "", do: :ok
  defp require_action_shape(_), do: {:error, "typed_action.type is required"}

  @doc "Serialize the trace back to a plain (JSON-ready) map."
  @spec to_map(t()) :: map()
  def to_map(%InteractionTrace{} = t) do
    %{
      "trace_id" => t.trace_id,
      "body_subtype" => t.body_subtype,
      "provider" => t.provider,
      "agent_id" => t.agent_id,
      "started_at" => t.started_at,
      "ended_at" => t.ended_at,
      "environment" => t.environment,
      "goal" => t.goal,
      "outcome" => Atom.to_string(t.outcome),
      "metadata" => t.metadata,
      "edges" => Enum.map(t.edges, &edge_to_map/1)
    }
  end

  defp edge_to_map(%Edge{} = e) do
    %{
      "edge_id" => e.edge_id,
      "state_before" => e.state_before,
      "state_after" => e.state_after,
      "typed_action" => e.typed_action,
      "latency_ms" => e.latency_ms,
      "outcome_status" => Atom.to_string(e.outcome_status),
      "observed_outcome" => e.observed_outcome,
      "authorization" => e.authorization,
      "provenance" => e.provenance,
      "surprise_magnitude" => e.surprise_magnitude,
      "surprise_kind" => e.surprise_kind
    }
  end

  @doc """
  True iff any edge carries a destructive `&body.os` action. Replay of
  such edges requires fresh authorization per OS-011 §4.4.
  """
  @spec destructive?(t()) :: boolean()
  def destructive?(%InteractionTrace{edges: edges}) do
    Enum.any?(edges, fn %Edge{typed_action: ta} ->
      Map.get(ta, "type") in ~w(shell_exec file_write file_edit file_delete process_spawn process_signal)
    end)
  end

  @doc "Return the state_before of edge[0], used for procedural clustering."
  @spec initial_state_hash(t()) :: binary() | nil
  def initial_state_hash(%InteractionTrace{edges: [%Edge{state_before: h} | _]}), do: h
  def initial_state_hash(_), do: nil

  # -- private helpers --

  defp require_string(map, key) do
    case Map.get(map, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, "#{key} is required (non-empty string)"}
    end
  end

  defp require_list(map, key) do
    case Map.get(map, key) do
      v when is_list(v) -> {:ok, v}
      _ -> {:error, "#{key} is required (array)"}
    end
  end

  defp require_map(map, key) do
    case Map.get(map, key) do
      v when is_map(v) -> {:ok, v}
      _ -> {:error, "#{key} is required (object)"}
    end
  end

  defp get_string(map, key) do
    case Map.get(map, key) do
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp get_map(map, key) do
    case Map.get(map, key) do
      v when is_map(v) -> v
      _ -> %{}
    end
  end

  defp get_integer(map, key, default) do
    case Map.get(map, key) do
      v when is_integer(v) -> v
      _ -> default
    end
  end

  defp get_float(map, key, default) do
    case Map.get(map, key) do
      v when is_float(v) -> clamp_unit(v)
      v when is_integer(v) -> clamp_unit(v * 1.0)
      _ -> default
    end
  end

  defp clamp_unit(v) when is_float(v), do: v |> max(0.0) |> min(1.0)

  defp normalize_outcome(s) when s in @valid_outcomes, do: String.to_atom(s)
  defp normalize_outcome(_), do: :success

  defp normalize_edge_status(s) when s in @valid_edge_statuses, do: String.to_atom(s)
  defp normalize_edge_status(_), do: :success
end
