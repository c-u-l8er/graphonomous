defmodule Graphonomous.MCP.GraphStats do
  @moduledoc """
  MCP tool for graph statistics and health metrics.

  Returns aggregate counts, type distributions, confidence statistics,
  and other health indicators for the knowledge graph.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:include_distributions, :boolean,
      description: "Include detailed type/timescale distributions (default: true)"
    )
  end

  @impl true
  def execute(params, frame) do
    include_distributions = p(params, :include_distributions, true)

    case build_stats(include_distributions) do
      {:ok, stats} ->
        payload = Map.put(stats, :status, "ok")

        {:reply,
         Response.tool()
         |> Response.text(Jason.encode!(payload)), frame}

      {:error, reason} ->
        payload = %{status: "error", error: inspect(reason)}

        {:reply,
         Response.tool()
         |> Response.text(Jason.encode!(payload))
         |> Map.put(:isError, true), frame}
    end
  end

  defp build_stats(include_distributions) do
    with nodes when is_list(nodes) <- Graphonomous.list_nodes(%{}),
         edges <- list_all_edges(nodes) do
      confidences = Enum.map(nodes, &(Map.get(&1, :confidence) || 0.5))

      stats = %{
        node_count: length(nodes),
        edge_count: length(edges),
        avg_confidence: safe_avg(confidences),
        min_confidence: safe_min(confidences),
        max_confidence: safe_max(confidences)
      }

      stats =
        if include_distributions do
          type_dist =
            nodes
            |> Enum.group_by(&(Map.get(&1, :node_type) || Map.get(&1, :type) || :unknown))
            |> Enum.map(fn {type, group} -> {to_string(type), length(group)} end)
            |> Map.new()

          timescale_dist =
            nodes
            |> Enum.group_by(&(Map.get(&1, :timescale) || :medium))
            |> Enum.map(fn {ts, group} -> {to_string(ts), length(group)} end)
            |> Map.new()

          source_dist =
            nodes
            |> Enum.group_by(&(Map.get(&1, :creation_source) || :unknown))
            |> Enum.map(fn {src, group} -> {to_string(src), length(group)} end)
            |> Map.new()

          relationship_dist =
            edges
            |> Enum.group_by(&(Map.get(&1, :relationship) || Map.get(&1, :edge_type) || :unknown))
            |> Enum.map(fn {rel, group} -> {to_string(rel), length(group)} end)
            |> Map.new()

          orphan_count =
            nodes
            |> Enum.count(fn node ->
              node_id = Map.get(node, :id)

              not Enum.any?(edges, fn edge ->
                Map.get(edge, :source_id) == node_id or Map.get(edge, :target_id) == node_id
              end)
            end)

          stats
          |> Map.put(:type_distribution, type_dist)
          |> Map.put(:timescale_distribution, timescale_dist)
          |> Map.put(:source_distribution, source_dist)
          |> Map.put(:relationship_distribution, relationship_dist)
          |> Map.put(:orphan_node_count, orphan_count)
        else
          stats
        end

      {:ok, stats}
    else
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp list_all_edges(nodes) do
    nodes
    |> Enum.flat_map(fn node ->
      node_id = Map.get(node, :id)

      case Graphonomous.query_graph(%{operation: "get_edges", node_id: node_id}) do
        edges when is_list(edges) -> edges
        {:ok, edges} when is_list(edges) -> edges
        _ -> []
      end
    end)
    |> Enum.uniq_by(&Map.get(&1, :id))
  end

  defp safe_avg([]), do: 0.0
  defp safe_avg(values), do: Float.round(Enum.sum(values) / length(values), 4)

  defp safe_min([]), do: 0.0
  defp safe_min(values), do: Enum.min(values)

  defp safe_max([]), do: 0.0
  defp safe_max(values), do: Enum.max(values)

  defp p(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
