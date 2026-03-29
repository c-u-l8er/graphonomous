defmodule Graphonomous.MCP.LearnDetectNovelty do
  @moduledoc """
  MCP tool for novelty detection.

  Checks whether a query contains concepts that are novel (not well-covered)
  in the current knowledge graph. Returns a novelty score and the nearest
  existing nodes for comparison.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @novelty_threshold 0.35
  @default_limit 5

  schema do
    field(:query, :string,
      required: true,
      description: "Natural-language query to check for novelty"
    )

    field(:threshold, :number,
      description:
        "Similarity threshold below which content is considered novel (default: 0.35, range 0.0-1.0)"
    )

    field(:limit, :number, description: "Max nearest nodes to return for comparison (default: 5)")
  end

  @impl true
  def execute(params, frame) do
    query = p(params, :query)

    if not is_binary(query) or String.trim(query) == "" do
      {:reply, error_response("query is required"), frame}
    else
      threshold =
        p(params, :threshold, @novelty_threshold)
        |> parse_float(@novelty_threshold)
        |> clamp(0.0, 1.0)

      limit = p(params, :limit, @default_limit) |> parse_pos_int(@default_limit)

      case detect_novelty(String.trim(query), threshold, limit) do
        {:ok, result} ->
          {:reply, ok_response(result), frame}

        {:error, reason} ->
          {:reply, error_response(inspect(reason)), frame}
      end
    end
  end

  defp detect_novelty(query, threshold, limit) do
    # Retrieve the most similar nodes to the query
    retrieval =
      Graphonomous.retrieve_context(query,
        limit: limit,
        expansion_hops: 0,
        neighbors_per_node: 0
      )

    case retrieval do
      %{results: results} when is_list(results) ->
        analyze_novelty(query, results, threshold, limit)

      %{} ->
        results = Map.get(retrieval, :results, [])
        analyze_novelty(query, results, threshold, limit)

      {:error, _} = err ->
        err
    end
  end

  defp analyze_novelty(query, results, threshold, limit) do
    nearest =
      results
      |> Enum.take(limit)
      |> Enum.map(fn r ->
        %{
          node_id: Map.get(r, :node_id),
          content: Map.get(r, :content),
          node_type: Map.get(r, :node_type),
          confidence: Map.get(r, :confidence),
          similarity: Map.get(r, :similarity, 0.0),
          score: Map.get(r, :score, 0.0)
        }
      end)

    # Highest similarity among existing nodes
    max_similarity =
      case nearest do
        [] -> 0.0
        nodes -> nodes |> Enum.map(&(Map.get(&1, :similarity) || 0.0)) |> Enum.max()
      end

    # Novelty score: inverse of max similarity (1.0 = completely novel, 0.0 = exact match)
    novelty_score = 1.0 - clamp(max_similarity, 0.0, 1.0)
    is_novel = max_similarity < threshold

    {:ok,
     %{
       query: query,
       is_novel: is_novel,
       novelty_score: Float.round(novelty_score, 4),
       max_similarity: Float.round(max_similarity, 4),
       threshold: threshold,
       nearest_node_count: length(nearest),
       nearest_nodes: nearest
     }}
  end

  defp ok_response(data) do
    payload = Map.put(data, :status, "ok")

    Response.tool()
    |> Response.text(Jason.encode!(payload))
  end

  defp error_response(message) do
    payload = %{status: "error", error: message}

    Response.tool()
    |> Response.text(Jason.encode!(payload))
    |> Map.put(:isError, true)
  end

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp parse_pos_int(value, _default) when is_integer(value) and value > 0, do: value
  defp parse_pos_int(value, _default) when is_float(value) and value > 0, do: trunc(value)

  defp parse_pos_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_pos_int(_, default), do: default

  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value * 1.0

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end
