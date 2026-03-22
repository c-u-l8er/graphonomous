defmodule Graphonomous.MCP.TopologyAnalyze do
  @moduledoc """
  Compute topological structure (SCCs, κ values, routing decision) for a set of
  nodes in the knowledge graph.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.{Store, Topology}

  schema do
    field(:node_ids, :array,
      description: "Node IDs to analyze. If omitted, analyzes the full graph."
    )

    field(:query, :string,
      description:
        "Optional query text. If provided, retrieves relevant nodes first, then analyzes their topology."
    )
  end

  @impl true
  def execute(params, frame) do
    query = params |> p(:query) |> normalize_query()

    with {:ok, node_ids, context_info} <- resolve_node_ids(params, query),
         {:ok, topology} <- analyze_nodes(node_ids) do
      payload =
        topology
        |> serialize_topology()
        |> Map.put(:recommendation, recommendation(topology))
        |> maybe_put(:query, query)
        |> maybe_put(:node_count, length(node_ids))
        |> maybe_put(:selection, context_info)

      {:reply, tool_response(payload), frame}
    else
      {:error, reason} ->
        {:reply,
         tool_response(
           %{
             status: "error",
             error: format_reason(reason),
             query: query
           },
           true
         ), frame}
    end
  end

  defp resolve_node_ids(params, query) do
    explicit_ids = params |> p(:node_ids) |> normalize_node_ids()

    cond do
      explicit_ids != [] ->
        {:ok, explicit_ids, "explicit_node_ids"}

      is_binary(query) and query != "" ->
        case Graphonomous.retrieve_context(
               query,
               similarity_limit: 20,
               final_limit: 20,
               expansion_hops: 1
             ) do
          %{} = retrieval ->
            ids =
              retrieval
              |> Map.get(:results, [])
              |> Enum.map(&Map.get(&1, :node_id))
              |> Enum.filter(&is_binary/1)
              |> Enum.uniq()

            {:ok, ids, "query_retrieval_subgraph"}

          {:error, _} = err ->
            err

          other ->
            {:error, {:unexpected_retrieval_response, other}}
        end

      true ->
        case Graphonomous.list_nodes(%{}) do
          nodes when is_list(nodes) ->
            ids =
              nodes
              |> Enum.map(&Map.get(&1, :id))
              |> Enum.filter(&is_binary/1)
              |> Enum.uniq()

            {:ok, ids, "full_graph"}

          {:error, _} = err ->
            err

          other ->
            {:error, {:unexpected_list_nodes_response, other}}
        end
    end
  end

  defp analyze_nodes(node_ids) when is_list(node_ids) do
    ids = node_ids |> Enum.filter(&is_binary/1) |> Enum.uniq()

    edges =
      case Store.list_edges_between(ids) do
        {:ok, list} when is_list(list) -> list
        {:error, reason} -> throw({:error, reason})
        other -> throw({:error, {:unexpected_edges_response, other}})
      end

    adjacency = Topology.build_adjacency(ids, edges)
    {:ok, Topology.analyze(adjacency)}
  catch
    {:error, reason} -> {:error, reason}
  end

  defp serialize_topology(%{} = topology) do
    sccs = topology |> Map.get(:sccs, []) |> Enum.map(&serialize_scc/1)

    %{
      status: "ok",
      routing: normalize_routing(Map.get(topology, :routing)),
      max_kappa: as_non_neg_int(Map.get(topology, :max_kappa)),
      scc_count: as_non_neg_int(Map.get(topology, :scc_count)),
      sccs: sccs,
      dag_nodes: Map.get(topology, :dag_nodes, [])
    }
  end

  defp serialize_scc(%{} = scc) do
    %{
      id: Map.get(scc, :id),
      nodes: Map.get(scc, :nodes, []),
      kappa: as_non_neg_int(Map.get(scc, :kappa)),
      approximate: Map.get(scc, :approximate, false) == true,
      fault_line_edges:
        scc
        |> Map.get(:fault_line_edges, [])
        |> Enum.map(fn
          %{source: s, target: t} -> %{source: s, target: t}
          %{"source" => s, "target" => t} -> %{source: s, target: t}
          _ -> %{}
        end)
        |> Enum.reject(&(map_size(&1) == 0)),
      routing: normalize_routing(Map.get(scc, :routing)),
      deliberation_budget: Map.get(scc, :deliberation_budget, %{})
    }
  end

  defp recommendation(%{} = topology) do
    routing = normalize_routing(Map.get(topology, :routing))
    scc_count = as_non_neg_int(Map.get(topology, :scc_count))
    max_kappa = as_non_neg_int(Map.get(topology, :max_kappa))

    if routing == "fast" do
      "This knowledge region is acyclic (κ=0). Use fast retrieval."
    else
      fault_lines =
        topology
        |> Map.get(:sccs, [])
        |> Enum.flat_map(&Map.get(&1, :fault_line_edges, []))
        |> Enum.take(3)
        |> Enum.map(fn
          %{source: s, target: t} -> "#{s}→#{t}"
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      suffix =
        case fault_lines do
          [] -> ""
          lines -> " Deliberate on fault lines: #{Enum.join(lines, ", ")}."
        end

      "This knowledge region contains #{scc_count} strongly connected component(s) with max κ=#{max_kappa}. Route to deliberation.#{suffix}"
    end
  end

  defp normalize_node_ids(nil), do: []

  defp normalize_node_ids(list) when is_list(list) do
    list
    |> Enum.map(&to_string_safe/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_node_ids(_), do: []

  defp normalize_query(nil), do: nil

  defp normalize_query(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      q -> q
    end
  end

  defp normalize_query(v), do: v |> to_string_safe() |> normalize_query()

  defp normalize_routing(:deliberate), do: "deliberate"
  defp normalize_routing(:fast), do: "fast"

  defp normalize_routing(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "deliberate" -> "deliberate"
      "fast" -> "fast"
      _ -> "fast"
    end
  end

  defp normalize_routing(_), do: "fast"

  defp as_non_neg_int(v) when is_integer(v) and v >= 0, do: v
  defp as_non_neg_int(v) when is_float(v) and v >= 0, do: trunc(v)

  defp as_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> 0
    end
  end

  defp as_non_neg_int(_), do: 0

  defp to_string_safe(v) when is_binary(v), do: v
  defp to_string_safe(v), do: to_string(v)

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp tool_response(payload, is_error \\ false) do
    response =
      Response.tool()
      |> Response.structured(payload)

    if is_error, do: Map.put(response, :isError, true), else: response
  end

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:not_found), do: "not found"
  defp format_reason(other), do: inspect(other)

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
