defmodule Graphonomous.MCP.RetrieveContext do
  @moduledoc """
  Retrieve semantically relevant context from Graphonomous.

  This MCP tool is used by LLM clients to:
  - search memory by natural-language query
  - receive ranked results
  - capture `causal_context` node IDs for later outcome feedback
  """

  use Anubis.Server.Component, type: :tool

  schema do
    field(:query, :string,
      required: true,
      description: "Natural-language query to retrieve relevant knowledge"
    )

    field(:limit, :number, description: "Max number of results to return (default: 10)")

    field(:expansion_hops, :number,
      description: "Graph neighborhood expansion depth (default: 1)"
    )

    field(:neighbors_per_node, :number,
      description: "Max neighbors to expand per seed node (default: 5)"
    )

    field(:min_score, :number, description: "Optional minimum score threshold (0.0-1.0)")

    field(:node_type, :string, description: "Optional filter: episodic, semantic, or procedural")
  end

  @impl true
  def execute(params, frame) do
    query =
      params
      |> fetch_param(:query)
      |> to_string_or_nil()
      |> normalize_query()

    if is_nil(query) do
      {:ok,
       Jason.encode!(%{
         status: "error",
         error: "query is required"
       }), frame}
    else
      opts = build_opts(params)

      case Graphonomous.retrieve_context(query, opts) do
        %{} = retrieval ->
          retrieval = apply_result_filters(retrieval, params)
          results = Map.get(retrieval, :results, [])
          causal_context = Map.get(retrieval, :causal_context, [])

          {:ok,
           Jason.encode!(%{
             status: "ok",
             query: query,
             count: length(results),
             causal_context: causal_context,
             stats: Map.get(retrieval, :stats, %{}),
             results: Enum.map(results, &serialize_result/1)
           }), frame}

        {:error, reason} ->
          {:ok,
           Jason.encode!(%{
             status: "error",
             query: query,
             error: inspect(reason)
           }), frame}

        other ->
          {:ok,
           Jason.encode!(%{
             status: "error",
             query: query,
             error: "unexpected retrieval response",
             details: inspect(other)
           }), frame}
      end
    end
  end

  defp build_opts(params) do
    []
    |> maybe_put_opt(:limit, fetch_param(params, :limit), &parse_pos_int/1)
    |> maybe_put_opt(:similarity_limit, fetch_param(params, :limit), &parse_pos_int/1)
    |> maybe_put_opt(:final_limit, fetch_param(params, :limit), &parse_pos_int/1)
    |> maybe_put_opt(:expansion_hops, fetch_param(params, :expansion_hops), &parse_non_neg_int/1)
    |> maybe_put_opt(
      :neighbors_per_node,
      fetch_param(params, :neighbors_per_node),
      &parse_pos_int/1
    )
  end

  defp maybe_put_opt(opts, _key, nil, _parser), do: opts

  defp maybe_put_opt(opts, key, value, parser) do
    case parser.(value) do
      nil -> opts
      parsed -> Keyword.put(opts, key, parsed)
    end
  end

  defp apply_result_filters(%{} = retrieval, params) do
    min_score = fetch_param(params, :min_score) |> parse_probability()
    node_type = fetch_param(params, :node_type) |> normalize_node_type()

    results =
      retrieval
      |> Map.get(:results, [])
      |> maybe_filter_min_score(min_score)
      |> maybe_filter_node_type(node_type)

    causal_context =
      results
      |> Enum.map(&Map.get(&1, :node_id))
      |> Enum.filter(&is_binary/1)

    retrieval
    |> Map.put(:results, results)
    |> Map.put(:causal_context, causal_context)
    |> Map.update(:stats, %{returned: length(results)}, fn stats ->
      Map.put(stats || %{}, :returned, length(results))
    end)
  end

  defp maybe_filter_min_score(results, nil), do: results

  defp maybe_filter_min_score(results, min_score) do
    Enum.filter(results, fn r ->
      score = r |> Map.get(:score, 0.0) |> to_float()
      score >= min_score
    end)
  end

  defp maybe_filter_node_type(results, nil), do: results

  defp maybe_filter_node_type(results, node_type) do
    Enum.filter(results, fn r ->
      r_type =
        r
        |> Map.get(:node_type)
        |> normalize_node_type()

      r_type == node_type
    end)
  end

  defp serialize_result(result) when is_map(result) do
    %{
      node_id: Map.get(result, :node_id),
      content: Map.get(result, :content),
      node_type: Map.get(result, :node_type),
      confidence: to_float(Map.get(result, :confidence)),
      similarity: to_float(Map.get(result, :similarity)),
      score: to_float(Map.get(result, :score)),
      source: Map.get(result, :source),
      hops: Map.get(result, :hops),
      via: Map.get(result, :via)
    }
  end

  defp fetch_param(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v) when is_binary(v), do: v
  defp to_string_or_nil(v), do: to_string(v)

  defp normalize_query(nil), do: nil

  defp normalize_query(query) when is_binary(query) do
    query = String.trim(query)
    if query == "", do: nil, else: query
  end

  defp parse_pos_int(v) when is_integer(v) and v > 0, do: v
  defp parse_pos_int(v) when is_float(v) and v > 0, do: trunc(v)

  defp parse_pos_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp parse_pos_int(_), do: nil

  defp parse_non_neg_int(v) when is_integer(v) and v >= 0, do: v
  defp parse_non_neg_int(v) when is_float(v) and v >= 0, do: trunc(v)

  defp parse_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> nil
    end
  end

  defp parse_non_neg_int(_), do: nil

  defp parse_probability(v) do
    v
    |> to_float_or_nil()
    |> case do
      nil -> nil
      f when f < 0.0 -> 0.0
      f when f > 1.0 -> 1.0
      f -> f
    end
  end

  defp to_float_or_nil(v) when is_float(v), do: v
  defp to_float_or_nil(v) when is_integer(v), do: v * 1.0

  defp to_float_or_nil(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp to_float_or_nil(_), do: nil

  defp to_float(v), do: to_float_or_nil(v) || 0.0

  defp normalize_node_type(nil), do: nil
  defp normalize_node_type(:episodic), do: :episodic
  defp normalize_node_type(:semantic), do: :semantic
  defp normalize_node_type(:procedural), do: :procedural

  defp normalize_node_type(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "episodic" -> :episodic
      "semantic" -> :semantic
      "procedural" -> :procedural
      _ -> nil
    end
  end

  defp normalize_node_type(_), do: nil
end
