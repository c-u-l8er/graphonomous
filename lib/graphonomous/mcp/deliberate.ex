defmodule Graphonomous.MCP.Deliberate do
  @moduledoc """
  κ-driven deliberation MCP tool.

  This tool orchestrates:

    1) Node-set resolution (explicit IDs or retrieval-derived)
    2) Topology analysis (SCCs, κ, routing)
    3) Deliberation over cyclic regions
    4) Optional crystallization write-back to graph
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.{Deliberator, Store, Topology}

  schema do
    field(:query, :string,
      required: true,
      description: "Natural-language query or decision to deliberate over."
    )

    field(:node_ids, :array,
      description: "Optional explicit node IDs to constrain deliberation scope."
    )

    field(:write_back, :boolean,
      default: false,
      description:
        "If true, crystallized deliberation conclusions are written back to the graph as semantic nodes."
    )
  end

  @impl true
  def execute(params, frame) do
    query = params |> p(:query) |> normalize_query()
    node_ids = params |> p(:node_ids) |> normalize_node_ids()
    write_back? = params |> p(:write_back, false) |> parse_bool(false)

    cond do
      is_nil(query) ->
        {:reply,
         tool_response(
           %{
             status: "error",
             error: "query is required"
           },
           true
         ), frame}

      true ->
        with {:ok, ids, retrieval_results, selection} <- resolve_scope(query, node_ids),
             {:ok, topology} <- analyze_topology(ids),
             result <- run_deliberation(topology, query, retrieval_results, write_back?) do
          payload = %{
            status: "ok",
            query: query,
            deliberation: serialize_deliberation(result),
            topology: serialize_topology(topology),
            selection: %{
              mode: selection,
              node_count: length(ids),
              write_back: write_back?
            }
          }

          {:reply, tool_response(payload), frame}
        else
          {:error, reason} ->
            {:reply,
             tool_response(
               %{
                 status: "error",
                 query: query,
                 error: format_reason(reason)
               },
               true
             ), frame}
        end
    end
  end

  defp resolve_scope(query, explicit_ids) when is_binary(query) and is_list(explicit_ids) do
    cond do
      explicit_ids != [] ->
        {:ok, explicit_ids, fetch_rows_for_ids(explicit_ids), "explicit_node_ids"}

      true ->
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

            if ids == [] do
              {:ok, [], [], "query_retrieval_empty"}
            else
              {:ok, ids, Map.get(retrieval, :results, []), "query_retrieval_subgraph"}
            end

          {:error, _} = err ->
            err

          other ->
            {:error, {:unexpected_retrieve_context_response, other}}
        end
    end
  end

  defp fetch_rows_for_ids(ids) do
    ids
    |> Enum.reduce([], fn id, acc ->
      case Graphonomous.get_node(id) do
        %{id: nid} = node when is_binary(nid) ->
          row = %{
            node_id: node.id,
            content: Map.get(node, :content, ""),
            node_type: Map.get(node, :node_type, :semantic),
            confidence: to_float(Map.get(node, :confidence, 0.5)),
            similarity: 0.0,
            score: 0.0
          }

          [row | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp analyze_topology([]) do
    {:ok,
     %{
       sccs: [],
       dag_nodes: [],
       routing: :fast,
       max_kappa: 0,
       scc_count: 0
     }}
  end

  defp analyze_topology(node_ids) when is_list(node_ids) do
    case Store.list_edges_between(node_ids) do
      {:ok, edges} when is_list(edges) ->
        adjacency = Topology.build_adjacency(node_ids, edges)
        {:ok, Topology.analyze(adjacency)}

      {:error, _} = err ->
        err

      other ->
        {:error, {:unexpected_edges_response, other}}
    end
  end

  defp run_deliberation(topology, query, retrieval_results, write_back?) do
    Deliberator.deliberate(
      topology,
      query,
      retrieval_results,
      write_back: write_back?
    )
  end

  defp serialize_deliberation(result) when is_map(result) do
    %{
      converged: Map.get(result, :converged, false) == true,
      iterations_used: as_non_neg_int(Map.get(result, :iterations_used, 0)),
      conclusions:
        result
        |> Map.get(:conclusions, [])
        |> Enum.map(&serialize_conclusion/1),
      topology_change: serialize_topology_change(Map.get(result, :topology_change, %{}))
    }
  end

  defp serialize_deliberation(_),
    do: %{converged: false, iterations_used: 0, conclusions: [], topology_change: %{}}

  defp serialize_conclusion(c) when is_map(c) do
    %{
      content: Map.get(c, :content, ""),
      confidence: to_float(Map.get(c, :confidence, 0.0)),
      source_scc_id: Map.get(c, :source_scc_id),
      source_kappa: as_non_neg_int(Map.get(c, :source_kappa, 0)),
      fault_lines_examined:
        c
        |> Map.get(:fault_lines_examined, [])
        |> Enum.map(fn
          %{source: s, target: t} -> %{source: s, target: t}
          %{"source" => s, "target" => t} -> %{source: s, target: t}
          _ -> %{}
        end)
        |> Enum.reject(&(map_size(&1) == 0))
    }
  end

  defp serialize_conclusion(_),
    do: %{
      content: "",
      confidence: 0.0,
      source_scc_id: nil,
      source_kappa: 0,
      fault_lines_examined: []
    }

  defp serialize_topology_change(change) when is_map(change) do
    %{
      kappa_before: as_non_neg_int(Map.get(change, :kappa_before, 0)),
      kappa_after: as_non_neg_int(Map.get(change, :kappa_after, 0)),
      new_nodes_created: as_non_neg_int(Map.get(change, :new_nodes_created, 0)),
      note: to_string_safe(Map.get(change, :note, ""))
    }
  end

  defp serialize_topology_change(_),
    do: %{kappa_before: 0, kappa_after: 0, new_nodes_created: 0, note: ""}

  defp serialize_topology(topology) when is_map(topology) do
    %{
      routing: normalize_routing(Map.get(topology, :routing)),
      max_kappa: as_non_neg_int(Map.get(topology, :max_kappa, 0)),
      scc_count: as_non_neg_int(Map.get(topology, :scc_count, 0)),
      sccs:
        topology
        |> Map.get(:sccs, [])
        |> Enum.map(&serialize_scc/1),
      dag_nodes: Map.get(topology, :dag_nodes, [])
    }
  end

  defp serialize_topology(_),
    do: %{routing: "fast", max_kappa: 0, scc_count: 0, sccs: [], dag_nodes: []}

  defp serialize_scc(scc) when is_map(scc) do
    %{
      id: Map.get(scc, :id),
      nodes: Map.get(scc, :nodes, []),
      kappa: as_non_neg_int(Map.get(scc, :kappa, 0)),
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

  defp serialize_scc(_),
    do: %{
      id: nil,
      nodes: [],
      kappa: 0,
      approximate: false,
      fault_line_edges: [],
      routing: "fast",
      deliberation_budget: %{}
    }

  defp tool_response(payload, is_error \\ false) when is_map(payload) do
    response =
      Response.tool()
      |> Response.structured(payload)

    if is_error, do: Map.put(response, :isError, true), else: response
  end

  defp normalize_query(nil), do: nil

  defp normalize_query(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      q -> q
    end
  end

  defp normalize_query(v), do: v |> to_string_safe() |> normalize_query()

  defp normalize_node_ids(nil), do: []

  defp normalize_node_ids(list) when is_list(list) do
    list
    |> Enum.map(&to_string_safe/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_node_ids(_), do: []

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

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp to_string_safe(v) when is_binary(v), do: v
  defp to_string_safe(v), do: to_string(v)

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:not_found), do: "not found"
  defp format_reason(other), do: inspect(other)

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
