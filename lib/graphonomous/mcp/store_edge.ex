defmodule Graphonomous.MCP.StoreEdge do
  @moduledoc """
  MCP tool for creating a directed edge between two knowledge nodes.
  """

  use Anubis.Server.Component, type: :tool

  schema do
    field(:source_id, :string,
      required: true,
      description: "Source node ID"
    )

    field(:target_id, :string,
      required: true,
      description: "Target node ID"
    )

    field(:edge_type, :string,
      description:
        "Edge type: causal, related, contradicts, supports, or derived_from (default: causal)"
    )

    field(:weight, :number, description: "Edge weight from 0.0 to 1.0 (default: 0.5)")

    field(:metadata, :string, description: "Optional JSON object with extra edge metadata")
  end

  @impl true
  def execute(params, frame) do
    source_id = get_param(params, :source_id)
    target_id = get_param(params, :target_id)

    attrs = %{
      edge_type: normalize_edge_type(get_param(params, :edge_type, "causal")),
      weight: normalize_weight(get_param(params, :weight, 0.5)),
      metadata: normalize_metadata(get_param(params, :metadata, %{}))
    }

    case Graphonomous.link_nodes(source_id, target_id, attrs) do
      %{id: id} = edge ->
        payload = %{
          status: "stored",
          edge_id: id,
          source_id: source_id,
          target_id: target_id,
          edge_type: Map.get(edge, :edge_type, :causal),
          weight: Map.get(edge, :weight, 0.5)
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload), frame}

      {:error, reason} ->
        payload = %{
          status: "error",
          error: "store_edge_failed",
          reason: inspect(reason)
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload)
         |> Map.put(:isError, true), frame}

      other ->
        payload = %{
          status: "error",
          error: "unexpected_result",
          reason: inspect(other)
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload)
         |> Map.put(:isError, true), frame}
    end
  end

  defp get_param(params, key, default \\ nil) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key), default))
  end

  defp normalize_edge_type(type) when is_atom(type), do: normalize_edge_type(Atom.to_string(type))

  defp normalize_edge_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "causal" -> "causal"
      "contradicts" -> "contradicts"
      "supports" -> "supports"
      "derived_from" -> "derived_from"
      "related" -> "related"
      _ -> "causal"
    end
  end

  defp normalize_edge_type(_), do: "causal"

  defp normalize_weight(value) when is_float(value), do: clamp(value, 0.0, 1.0)
  defp normalize_weight(value) when is_integer(value), do: normalize_weight(value * 1.0)

  defp normalize_weight(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> normalize_weight(parsed)
      :error -> 0.5
    end
  end

  defp normalize_weight(_), do: 0.5

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(value) when is_map(value), do: value

  defp normalize_metadata(value) when is_binary(value) do
    with {:ok, decoded} <- Jason.decode(value),
         true <- is_map(decoded) do
      decoded
    else
      _ -> %{}
    end
  end

  defp normalize_metadata(_), do: %{}

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value
end
