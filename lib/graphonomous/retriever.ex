defmodule Graphonomous.Retriever do
  @moduledoc """
  Context retrieval engine for Graphonomous.

  Strategy:
    1) Run semantic similarity search over stored node embeddings.
    2) Expand the neighborhood through graph edges.
    3) Return a single ranked list scored by confidence-aware relevance.

  The module is intentionally lightweight for v0.1 and relies on
  `Graphonomous.Graph` for node/edge access.
  """

  use GenServer

  alias Graphonomous.Graph
  alias Graphonomous.Types.Node

  @default_similarity_limit 10
  @default_final_limit 20
  @default_expansion_hops 1
  @default_neighbors_per_node 5
  @default_hop_decay 0.85
  @default_similarity_timeout_ms 25_000

  @type retrieve_opts :: keyword()
  @type retrieval_result :: %{
          query: String.t(),
          results: [map()],
          causal_context: [String.t()],
          stats: map()
        }

  @type state :: %{
          similarity_limit: pos_integer(),
          final_limit: pos_integer(),
          expansion_hops: non_neg_integer(),
          neighbors_per_node: pos_integer(),
          hop_decay: float(),
          similarity_timeout_ms: pos_integer()
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieve combined context with similarity + neighborhood expansion.
  """
  @spec retrieve(String.t(), retrieve_opts()) :: {:ok, retrieval_result()} | {:error, term()}
  def retrieve(query, opts \\ []) when is_binary(query) and is_list(opts) do
    GenServer.call(__MODULE__, {:retrieve, query, opts}, 30_000)
  end

  ## GenServer

  @impl true
  def init(opts) do
    state = %{
      similarity_limit: Keyword.get(opts, :similarity_limit, @default_similarity_limit),
      final_limit: Keyword.get(opts, :final_limit, @default_final_limit),
      expansion_hops: Keyword.get(opts, :expansion_hops, @default_expansion_hops),
      neighbors_per_node: Keyword.get(opts, :neighbors_per_node, @default_neighbors_per_node),
      hop_decay: Keyword.get(opts, :hop_decay, @default_hop_decay),
      similarity_timeout_ms:
        normalize_timeout_ms(
          Keyword.get(opts, :similarity_timeout_ms, @default_similarity_timeout_ms),
          @default_similarity_timeout_ms
        )
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:retrieve, query, call_opts}, _from, state) do
    cfg = merge_opts(state, call_opts)

    reply =
      with {:ok, seed_hits} <-
             safe_graph_retrieve_similar(query, cfg.similarity_limit, cfg.similarity_timeout_ms),
           {:ok, seed_entries} <- seed_entries(seed_hits),
           {:ok, expanded} <- expand_neighbors(seed_entries, cfg) do
        ranked =
          expanded
          |> Map.values()
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(cfg.final_limit)

        {:ok,
         %{
           query: query,
           results: ranked,
           causal_context: Enum.map(ranked, & &1.node_id),
           stats: %{
             seed_count: map_size(seed_entries),
             expanded_count: max(map_size(expanded) - map_size(seed_entries), 0),
             returned: length(ranked)
           }
         }}
      end

    {:reply, reply, state}
  end

  defp safe_graph_retrieve_similar(query, limit, timeout_ms)
       when is_binary(query) and is_integer(limit) and is_integer(timeout_ms) do
    try do
      GenServer.call(Graphonomous.Graph, {:retrieve_similar, query, [limit: limit]}, timeout_ms)
    catch
      :exit, reason ->
        {:error, {:graph_retrieve_similar_exit, reason}}
    end
  end

  ## Build seed entries (from similarity search)

  defp seed_entries(hits) when is_list(hits) do
    entries =
      Enum.reduce(hits, %{}, fn hit, acc ->
        node_id = Map.get(hit, :node_id)

        if is_binary(node_id) do
          entry = %{
            node_id: node_id,
            content: Map.get(hit, :content, ""),
            node_type: Map.get(hit, :node_type, :semantic),
            confidence: clamp01(to_float(Map.get(hit, :confidence, 0.5))),
            similarity: to_float(Map.get(hit, :similarity, 0.0)),
            score: to_float(Map.get(hit, :score, 0.0)),
            source: :seed,
            hops: 0,
            via: nil
          }

          Map.put(acc, node_id, entry)
        else
          acc
        end
      end)

    {:ok, entries}
  end

  ## Neighborhood expansion

  defp expand_neighbors(seed_entries, cfg) do
    frontier =
      seed_entries
      |> Map.values()
      |> Enum.map(fn e -> %{node_id: e.node_id, parent_score: e.score, hop: 1} end)

    expanded = bfs_expand(frontier, seed_entries, MapSet.new(), cfg)
    {:ok, expanded}
  end

  defp bfs_expand([], acc, _visited, _cfg), do: acc

  defp bfs_expand([item | rest], acc, visited, cfg) do
    node_id = item.node_id
    hop = item.hop
    parent_score = item.parent_score

    cond do
      hop > cfg.expansion_hops ->
        bfs_expand(rest, acc, visited, cfg)

      MapSet.member?(visited, {node_id, hop}) ->
        bfs_expand(rest, acc, visited, cfg)

      true ->
        visited = MapSet.put(visited, {node_id, hop})

        {acc, next_frontier} =
          case Graph.get_edges_for_node(node_id) do
            {:ok, edges} ->
              expand_from_edges(node_id, hop, parent_score, edges, acc, cfg)

            _ ->
              {acc, []}
          end

        bfs_expand(rest ++ next_frontier, acc, visited, cfg)
    end
  end

  defp expand_from_edges(node_id, hop, parent_score, edges, acc, cfg) do
    neighbors =
      edges
      |> Enum.map(fn edge ->
        neighbor_id =
          if edge.source_id == node_id do
            edge.target_id
          else
            edge.source_id
          end

        {neighbor_id, clamp01(to_float(Map.get(edge, :weight, 0.5)))}
      end)
      |> Enum.uniq_by(fn {nid, _} -> nid end)
      |> Enum.sort_by(fn {_nid, w} -> w end, :desc)
      |> Enum.take(cfg.neighbors_per_node)

    Enum.reduce(neighbors, {acc, []}, fn {neighbor_id, edge_weight}, {acc_map, frontier_acc} ->
      if not is_binary(neighbor_id) or neighbor_id == node_id do
        {acc_map, frontier_acc}
      else
        with {:ok, %Node{} = node} <- Graph.get_node(neighbor_id) do
          inherited_similarity = 0.0
          decayed = parent_score * edge_weight * :math.pow(cfg.hop_decay, hop)
          score = max(decayed, 0.0)

          entry = %{
            node_id: node.id,
            content: node.content,
            node_type: node.node_type,
            confidence: clamp01(to_float(node.confidence)),
            similarity: inherited_similarity,
            score: score,
            source: :neighbor,
            hops: hop,
            via: node_id
          }

          acc_map = upsert_best(acc_map, entry)

          frontier_item = %{
            node_id: node.id,
            parent_score: entry.score,
            hop: hop + 1
          }

          {acc_map, [frontier_item | frontier_acc]}
        else
          _ -> {acc_map, frontier_acc}
        end
      end
    end)
  end

  defp upsert_best(entries, new_entry) do
    case Map.get(entries, new_entry.node_id) do
      nil ->
        Map.put(entries, new_entry.node_id, new_entry)

      old ->
        cond do
          new_entry.score > old.score ->
            merged = %{
              old
              | content: new_entry.content || old.content,
                node_type: new_entry.node_type || old.node_type,
                confidence: max(old.confidence, new_entry.confidence),
                similarity: max(old.similarity, new_entry.similarity),
                score: new_entry.score,
                source: old.source,
                hops: min(old.hops, new_entry.hops),
                via: old.via || new_entry.via
            }

            Map.put(entries, new_entry.node_id, merged)

          true ->
            entries
        end
    end
  end

  ## Config + utils

  defp merge_opts(state, opts) do
    %{
      similarity_limit:
        normalize_positive_int(
          Keyword.get(opts, :similarity_limit, state.similarity_limit),
          @default_similarity_limit
        ),
      final_limit:
        normalize_positive_int(
          Keyword.get(opts, :final_limit, state.final_limit),
          @default_final_limit
        ),
      expansion_hops:
        normalize_non_neg_int(
          Keyword.get(opts, :expansion_hops, state.expansion_hops),
          @default_expansion_hops
        ),
      neighbors_per_node:
        normalize_positive_int(
          Keyword.get(opts, :neighbors_per_node, state.neighbors_per_node),
          @default_neighbors_per_node
        ),
      hop_decay:
        clamp(
          to_float(Keyword.get(opts, :hop_decay, state.hop_decay)),
          0.1,
          1.0
        ),
      similarity_timeout_ms:
        normalize_timeout_ms(
          Keyword.get(opts, :similarity_timeout_ms, state.similarity_timeout_ms),
          @default_similarity_timeout_ms
        )
    }
  end

  defp normalize_positive_int(v, _fallback) when is_integer(v) and v > 0, do: v

  defp normalize_positive_int(v, fallback) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} when i > 0 -> i
      _ -> fallback
    end
  end

  defp normalize_positive_int(_, fallback), do: fallback

  defp normalize_non_neg_int(v, _fallback) when is_integer(v) and v >= 0, do: v

  defp normalize_non_neg_int(v, fallback) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} when i >= 0 -> i
      _ -> fallback
    end
  end

  defp normalize_non_neg_int(_, fallback), do: fallback

  defp normalize_timeout_ms(v, _fallback) when is_integer(v) and v > 0, do: v

  defp normalize_timeout_ms(v, fallback) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} when i > 0 -> i
      _ -> fallback
    end
  end

  defp normalize_timeout_ms(_, fallback), do: fallback

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp clamp01(v), do: clamp(v, 0.0, 1.0)
  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end
