defmodule Graphonomous.MCP.EpistemicFrontier do
  @moduledoc """
  MCP tool returning nodes where investigation would most reduce uncertainty.

  Returns nodes with widest Wilson score intervals, sorted by information gain.
  Only includes nodes with evidence_count > 0.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Uncertainty

  schema do
    field(:min_gap, :number, description: "Minimum interval width to include (default: 0.3)")

    field(:limit, :number,
      description: "Maximum number of frontier nodes to return (default: 10)"
    )
  end

  @impl true
  def execute(params, frame) do
    min_gap = p(params, :min_gap, 0.3) |> parse_float(0.3)
    limit = p(params, :limit, 10) |> parse_pos_int(10)

    frontier = Uncertainty.frontier(min_gap: min_gap, limit: limit)

    result = %{
      status: "ok",
      count: length(frontier),
      frontier:
        Enum.map(frontier, fn item ->
          {lo, hi} = item.interval

          %{
            node_id: item.node_id,
            content: String.slice(item.content || "", 0..200),
            confidence: item.confidence,
            evidence_count: item.evidence_count,
            interval_lower: Float.round(lo, 4),
            interval_upper: Float.round(hi, 4),
            width: Float.round(item.width, 4),
            information_gain: Float.round(item.information_gain, 4),
            access_count: item.access_count
          }
        end)
    }

    {:reply, ok_response(result), frame}
  end

  defp ok_response(data) do
    Response.tool()
    |> Response.text(Jason.encode!(data))
  end

  defp p(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value * 1.0

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp parse_pos_int(value, _default) when is_integer(value) and value > 0, do: value
  defp parse_pos_int(value, _default) when is_float(value) and value > 0, do: trunc(value)

  defp parse_pos_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_pos_int(_, default), do: default
end
