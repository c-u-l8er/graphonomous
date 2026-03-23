defmodule Graphonomous.MCP.AttentionSurvey do
  @moduledoc """
  MCP tool to expose the current ranked attention map.

  This tool is read-only: it surveys and reports what the Attention engine
  believes needs focus, without executing dispatch actions.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:include_idle, :boolean,
      default: false,
      description: "Include items that don't currently require action (dispatch_mode: idle)."
    )
  end

  @impl true
  def execute(params, frame) do
    include_idle = params |> p(:include_idle, false) |> parse_bool(false)

    with {:ok, items} <- Graphonomous.Attention.survey(),
         %{} = status <- Graphonomous.Attention.status() do
      filtered =
        if include_idle do
          items
        else
          Enum.reject(items, fn item -> map_get(item, :dispatch_mode) == :idle end)
        end

      payload = %{
        status: "ok",
        attention_items: Enum.map(filtered, &serialize_item/1),
        autonomy_level: status |> map_get(:autonomy_level, :observe) |> atom_to_string(),
        next_heartbeat_in_ms: map_get(status, :next_heartbeat_in_ms)
      }

      {:reply, tool_response(payload, false), frame}
    else
      {:error, reason} ->
        {:reply,
         tool_response(
           %{
             status: "error",
             error: format_reason(reason)
           },
           true
         ), frame}

      other ->
        {:reply,
         tool_response(
           %{
             status: "error",
             error: "unexpected_attention_response",
             details: inspect(other)
           },
           true
         ), frame}
    end
  end

  defp serialize_item(item) when is_map(item) do
    coverage = map_get(item, :coverage, %{})
    topology = map_get(item, :topology, %{})

    %{
      goal_id: map_get(item, :goal_id),
      goal_title: map_get(item, :goal_title),
      attention_score: round3(map_get(item, :attention_score, 0.0)),
      dispatch_mode: item |> map_get(:dispatch_mode, :idle) |> atom_to_string(),
      coverage_score: round3(map_get(coverage, :coverage_score, 0.0)),
      coverage_decision: coverage |> map_get(:decision) |> atom_to_string(),
      decision_confidence: round3(map_get(coverage, :decision_confidence, 0.0)),
      max_kappa: as_non_neg_int(map_get(topology, :max_kappa, 0)),
      routing: topology |> map_get(:routing, :fast) |> atom_to_string(),
      coverage_rationale: map_get(coverage, :rationale, []),
      attention_rationale: attention_rationale(item, coverage, topology)
    }
  end

  defp serialize_item(_), do: %{}

  defp attention_rationale(item, coverage, topology) do
    urgency = round3(map_get(item, :urgency, 0.0))
    gap = round3(map_get(item, :gap, 0.0))
    kappa = as_non_neg_int(map_get(topology, :max_kappa, 0))
    routing = topology |> map_get(:routing, :fast) |> atom_to_string()
    decision = coverage |> map_get(:decision, :learn) |> atom_to_string()

    "Urgency=#{urgency}, gap=#{gap}, coverage_decision=#{decision}, κ=#{kappa}, routing=#{routing}."
  end

  defp tool_response(payload, is_error) when is_map(payload) do
    response =
      Response.tool()
      |> Response.text(Jason.encode!(payload))

    if is_error, do: %{response | isError: true}, else: response
  end

  defp p(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default

  defp parse_bool(v, _default) when is_boolean(v), do: v

  defp parse_bool(v, default) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "true" -> true
      "1" -> true
      "yes" -> true
      "on" -> true
      "false" -> false
      "0" -> false
      "no" -> false
      "off" -> false
      _ -> default
    end
  end

  defp parse_bool(_v, default), do: default

  defp atom_to_string(nil), do: nil
  defp atom_to_string(v) when is_atom(v), do: Atom.to_string(v)
  defp atom_to_string(v), do: to_string(v)

  defp as_non_neg_int(v) when is_integer(v) and v >= 0, do: v
  defp as_non_neg_int(v) when is_float(v) and v >= 0, do: trunc(v)

  defp as_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> 0
    end
  end

  defp as_non_neg_int(_), do: 0

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp round3(v), do: v |> to_float() |> Float.round(3)

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:not_found), do: "not found"
  defp format_reason(other), do: inspect(other)
end
