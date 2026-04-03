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

  alias Graphonomous.{Attention, CostTracker, Deliberator, Graph, ModelTier, Store, Topology}
  alias Graphonomous.Types.Node
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
          stats: map(),
          topology: map()
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
    GenServer.call(__MODULE__, {:retrieve, query, opts}, 120_000)
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
          |> maybe_diversify_domains(cfg)
          |> maybe_diversify_sessions(cfg)
          |> Enum.take(cfg.final_limit)

        topology = analyze_topology(ranked)

        # K2+K4: κ-guided adaptive expansion — if κ > 0, re-expand with
        # deeper hops and gentler decay to follow cyclic knowledge paths
        {ranked, topology} = maybe_kappa_expand(ranked, topology, cfg)

        # K5: Boost nodes adjacent to fault-line edges (knowledge boundaries)
        ranked = apply_fault_line_boost(ranked, topology)

        # K7: Propagate confidence through SCC edges — high-confidence nodes
        # boost low-confidence neighbors in the same SCC
        ranked = propagate_scc_confidence(ranked, topology)

        # K8: Query-time edge impact — detect high-scoring disconnected nodes
        # that would change κ if linked; annotate for downstream reasoning
        edge_impact_notes = detect_edge_impact_opportunities(ranked, topology)

        # P1: Two-phase retrieval — re-rank by Q-value utility scoring
        ranked = utility_rerank(ranked, call_opts)

        base_result = %{
          query: query,
          results: ranked,
          causal_context: Enum.map(ranked, & &1.node_id),
          stats: %{
            seed_count: map_size(seed_entries),
            expanded_count: max(map_size(expanded) - map_size(seed_entries), 0),
            returned: length(ranked)
          },
          topology: topology
        }

        base_result =
          if edge_impact_notes != [],
            do: Map.put(base_result, :edge_impact_notes, edge_impact_notes),
            else: base_result

        {:ok, maybe_enrich_or_deliberate(base_result, query, call_opts)}
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

        # P1: Filter out soft-forgotten nodes
        forgotten? =
          case node_id && Store.get_node(node_id) do
            {:ok, %Node{forgotten_at: %DateTime{}}} -> true
            _ -> false
          end

        if is_binary(node_id) and not forgotten? do
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

  # Hard cap on expanded nodes to prevent BFS explosion on dense graphs
  # (e.g., 21K+ cross-session entity edges at LongMemEval scale)
  @max_expanded_nodes 500

  defp bfs_expand([], acc, _visited, _cfg), do: acc

  defp bfs_expand([item | rest], acc, visited, cfg) do
    node_id = item.node_id
    hop = item.hop
    parent_score = item.parent_score

    cond do
      map_size(acc) >= @max_expanded_nodes ->
        acc

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

  ## Domain-aware re-ranking
  #
  # When multiple results come from the same domain, slightly demote duplicates
  # to promote cross-domain diversity. This improves precision on cross-domain
  # queries without hurting single-domain recall (which is already perfect).

  defp maybe_diversify_domains(results, cfg) do
    diversity = Map.get(cfg, :domain_diversity, true)

    if diversity and length(results) > 3 do
      diversify_domains(results)
    else
      results
    end
  end

  defp diversify_domains(results) do
    # Score penalty for domain concentration: each additional result from the
    # same domain gets a small score reduction, pushing diverse results up.
    decay_factor = 0.95

    {reranked, _seen} =
      results
      |> Enum.reduce({[], %{}}, fn entry, {acc, domain_counts} ->
        domain = domain_from_entry(entry)
        count = Map.get(domain_counts, domain, 0)

        # Apply diminishing returns for repeated domains
        adjusted_score = entry.score * :math.pow(decay_factor, count)
        adjusted_entry = %{entry | score: adjusted_score}

        {[adjusted_entry | acc], Map.put(domain_counts, domain, count + 1)}
      end)

    reranked
    |> Enum.reverse()
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp domain_from_entry(entry) do
    # Extract domain from node metadata (filesystem traversal nodes have relative_path)
    node_id = Map.get(entry, :node_id)

    case node_id && Graphonomous.get_node(node_id) do
      %{metadata: meta} when is_map(meta) ->
        path = Map.get(meta, "relative_path", "") |> to_string()
        extract_domain_from_path(path)

      _ ->
        "unknown"
    end
  end

  defp extract_domain_from_path(path) do
    case String.split(path, "/", parts: 2) do
      [domain | _] when domain != "" -> domain
      _ -> "unknown"
    end
  end

  # S5: Session-aware diversity — penalize results clustering in one session
  # to spread retrieval across sessions for multi-session questions.
  defp maybe_diversify_sessions(results, _cfg) do
    if length(results) > 3 do
      {reranked, _} =
        results
        |> Enum.reduce({[], %{}}, fn entry, {acc, seen} ->
          sid = session_id_for_entry(entry)
          count = Map.get(seen, sid, 0)
          penalty = :math.pow(0.90, count)
          adjusted = %{entry | score: entry.score * penalty}
          {[adjusted | acc], Map.put(seen, sid, count + 1)}
        end)

      reranked |> Enum.reverse() |> Enum.sort_by(& &1.score, :desc)
    else
      results
    end
  end

  defp session_id_for_entry(entry) do
    node_id = Map.get(entry, :node_id)

    case node_id && Graphonomous.get_node(node_id) do
      %{metadata: meta} when is_map(meta) -> Map.get(meta, "session_id", "unknown")
      _ -> "unknown"
    end
  end

  # K5: Fault-line-aware retrieval boosting — nodes at knowledge boundaries
  # between SCCs are more likely to contain multi-hop answer evidence.
  defp apply_fault_line_boost(ranked, topology) do
    fault_nodes =
      topology
      |> Map.get(:sccs, [])
      |> Enum.flat_map(fn scc ->
        scc
        |> Map.get(:fault_line_edges, [])
        |> Enum.flat_map(fn
          %{source: s, target: t} -> [s, t]
          %{"source" => s, "target" => t} -> [s, t]
          _ -> []
        end)
      end)
      |> MapSet.new()

    if MapSet.size(fault_nodes) == 0 do
      ranked
    else
      ranked
      |> Enum.map(fn entry ->
        if MapSet.member?(fault_nodes, entry.node_id),
          do: %{entry | score: entry.score * 1.15},
          else: entry
      end)
      |> Enum.sort_by(& &1.score, :desc)
    end
  end

  # K8: Query-time edge impact — check top disconnected result pairs to see if
  # linking them would change κ. If so, they're semantically related but not yet
  # connected in the graph → answer likely requires bridging them.
  defp detect_edge_impact_opportunities(ranked, topology) do
    dag_nodes = Map.get(topology, :dag_nodes, [])
    # Only check DAG nodes (not already in SCCs) — top 5 pairs
    top_dag =
      ranked
      |> Enum.filter(fn e -> e.node_id in dag_nodes end)
      |> Enum.take(6)

    if length(top_dag) < 2 do
      []
    else
      adjacency = build_adjacency_from_topology(ranked, topology)

      top_dag
      |> pairs()
      |> Enum.take(5)
      |> Enum.flat_map(fn {a, b} ->
        impact = Topology.preview_edge_impact(adjacency, a.node_id, b.node_id)
        kappa_before = Map.get(impact, :kappa_before, 0)
        kappa_after = Map.get(impact, :kappa_after, 0)

        if kappa_after > kappa_before do
          [
            %{
              source: a.node_id,
              target: b.node_id,
              kappa_delta: kappa_after - kappa_before,
              note: "Linking these nodes would create a cycle — they may need bridge reasoning."
            }
          ]
        else
          []
        end
      end)
    end
  rescue
    _ -> []
  end

  defp build_adjacency_from_topology(ranked, _topology) do
    node_ids = Enum.map(ranked, & &1.node_id) |> Enum.filter(&is_binary/1) |> Enum.uniq()

    edges =
      node_ids
      |> Enum.flat_map(fn id ->
        case Store.list_edges_for_node(id) do
          {:ok, list} -> list
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.id)

    neighbor_ids =
      edges
      |> Enum.flat_map(fn e -> [e.source_id, e.target_id] end)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    Topology.build_adjacency(Enum.uniq(node_ids ++ neighbor_ids), edges)
  end

  defp pairs(list) do
    for {a, i} <- Enum.with_index(list),
        {b, j} <- Enum.with_index(list),
        i < j,
        do: {a, b}
  end

  # K2+K4: After initial topology analysis, if κ > 0, re-expand from top
  # results with deeper hops and gentler decay to follow cyclic paths.
  defp maybe_kappa_expand(ranked, topology, cfg) do
    max_kappa = Map.get(topology, :max_kappa, 0)

    if max_kappa > 0 do
      # K2: additional hops proportional to κ
      effective_hops = min(max_kappa + 1, 3)
      # K4: gentler decay for cyclic regions
      effective_decay = min(cfg.hop_decay + max_kappa * 0.02, 0.95)

      new_seeds =
        ranked
        |> Enum.take(10)
        |> Enum.reduce(%{}, fn e, acc -> Map.put(acc, e.node_id, e) end)

      expanded_cfg = %{
        cfg
        | expansion_hops: effective_hops,
          hop_decay: effective_decay
      }

      {:ok, re_expanded} = expand_neighbors(new_seeds, expanded_cfg)

      # Merge with originals, keeping best score per node
      original_map = Enum.reduce(ranked, %{}, fn e, acc -> Map.put(acc, e.node_id, e) end)

      merged =
        Map.merge(original_map, re_expanded, fn _k, old, new ->
          if new.score > old.score, do: new, else: old
        end)

      re_ranked =
        merged
        |> Map.values()
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(cfg.final_limit)

      new_topology = analyze_topology(re_ranked)
      {re_ranked, new_topology}
    else
      {ranked, topology}
    end
  end

  # K7: Propagate confidence through SCC edges — high-confidence nodes in the
  # same SCC boost low-confidence neighbors. Scale boost by 1/κ to be cautious
  # in highly entangled regions.
  defp propagate_scc_confidence(ranked, topology) do
    sccs = Map.get(topology, :sccs, [])

    if sccs == [] do
      ranked
    else
      # For each SCC, find max confidence among its members in the ranked results
      scc_boosts =
        Enum.flat_map(sccs, fn scc ->
          kappa = Map.get(scc, :kappa, Map.get(scc, "kappa", 0))
          nodes = Map.get(scc, :nodes, Map.get(scc, "nodes", []))

          max_conf =
            ranked
            |> Enum.filter(fn e -> e.node_id in nodes end)
            |> Enum.map(& &1.confidence)
            |> Enum.max(fn -> 0.5 end)

          Enum.map(nodes, fn nid -> {nid, max_conf, max(kappa, 1)} end)
        end)
        |> Map.new(fn {nid, max_conf, kappa} -> {nid, {max_conf, kappa}} end)

      ranked
      |> Enum.map(fn entry ->
        case Map.get(scc_boosts, entry.node_id) do
          {max_conf, kappa} when max_conf > entry.confidence ->
            boost = (max_conf - entry.confidence) * (1 / kappa) * 0.3
            %{entry | score: entry.score * (1 + boost)}

          _ ->
            entry
        end
      end)
      |> Enum.sort_by(& &1.score, :desc)
    end
  end

  # P1: Two-phase retrieval — after semantic + topology scoring, re-rank by
  # Q-value (outcome utility). Nodes that contributed to successful outcomes
  # rank higher; failure nodes rank lower. Skip when no outcome data exists.
  defp utility_rerank(ranked, opts) do
    alpha = Keyword.get(opts, :utility_weight, 0.3)

    # Check if any candidate has Q-value outcome data
    has_outcome_data? =
      Enum.any?(ranked, fn entry ->
        case Store.get_node(entry.node_id) do
          {:ok, %Node{q_update_count: count}} when count > 0 -> true
          _ -> false
        end
      end)

    if has_outcome_data? do
      ranked
      |> Enum.map(fn entry ->
        {q, q_count} =
          case Store.get_node(entry.node_id) do
            {:ok, %Node{q_value: q, q_update_count: c}} -> {q, c}
            _ -> {0.5, 0}
          end

        if q_count > 0 do
          blended = (1.0 - alpha) * entry.score + alpha * q
          Map.merge(entry, %{score: blended, utility: q})
        else
          entry
        end
      end)
      |> Enum.sort_by(& &1.score, :desc)
    else
      ranked
    end
  end

  defp analyze_topology(ranked_results) when is_list(ranked_results) do
    retrieved_ids =
      ranked_results
      |> Enum.map(&Map.get(&1, :node_id))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    adjacency =
      case retrieved_ids do
        [] ->
          %{}

        ids ->
          # Expanded topology window: include 1-hop neighbors of retrieved nodes.
          # This is the key fix for kappa=0 — previously only edges *between*
          # retrieved nodes were considered, missing cycles that route through
          # non-retrieved intermediaries.
          all_edges =
            ids
            |> Enum.flat_map(fn id ->
              case Store.list_edges_for_node(id) do
                {:ok, edges} -> edges
                _ -> []
              end
            end)
            |> Enum.uniq_by(& &1.id)

          neighbor_ids =
            all_edges
            |> Enum.flat_map(fn edge -> [edge.source_id, edge.target_id] end)
            |> Enum.filter(&is_binary/1)
            |> Enum.uniq()

          expanded_ids = Enum.uniq(ids ++ neighbor_ids)

          Topology.build_adjacency(expanded_ids, all_edges)
      end

    topology = Topology.analyze(adjacency)
    _ = Topology.emit_retrieve_route_telemetry(topology)
    topology
  end

  defp maybe_enrich_or_deliberate(result, query, opts) when is_map(result) and is_binary(query) do
    tier = resolve_tier(opts)
    tier_cfg = ModelTier.deliberation_config(tier)
    attention_cfg = ModelTier.attention_config(tier)
    max_kappa = result |> Map.get(:topology, %{}) |> Map.get(:max_kappa, 0)
    floor = tier_cfg |> Map.get(:kappa_deliberation_floor, 1) |> normalize_non_neg_int(1)

    # K6: κ-bucketed answer strategies — route by κ profile:
    #   κ=0 → fast path (direct answer from top results)
    #   κ=1 → resolve contradictions first (knowledge update pattern)
    #   κ≥2 → full multi-pass deliberation
    result =
      cond do
        max_kappa == 0 ->
          # Fast path — no cycles, direct answer
          result

        max_kappa < floor ->
          enrich_with_topology_notes(result)

        Keyword.get(opts, :auto_deliberate, false) ->
          # K6: Select deliberation strategy by κ bucket
          deliberation_budget =
            cond do
              # κ=1: likely contradiction — single pass suffices
              max_kappa == 1 ->
                %{strategy: :single_pass, max_iterations: 1}

              # κ≥2: full multi-pass deliberation
              true ->
                %{max_iterations: min(max_kappa + 1, 4)}
            end

          deliberation_opts = [
            model_tier: tier,
            write_back: true,
            budget: deliberation_budget
          ]

          started_at = System.monotonic_time(:millisecond)

          case Deliberator.deliberate(
                 Map.get(result, :topology, %{}),
                 query,
                 Map.get(result, :results, []),
                 deliberation_opts
               ) do
            %{} = deliberation ->
              duration_ms = max(System.monotonic_time(:millisecond) - started_at, 0)

              _ =
                CostTracker.record(%{
                  operation: :deliberation,
                  tier: tier,
                  tokens_in: approx_token_count(query),
                  tokens_out:
                    approx_token_count(inspect(Map.get(deliberation, :conclusions, []))),
                  inference_ms: duration_ms * 1.0,
                  timestamp: DateTime.utc_now()
                })

              Map.put(result, :deliberation, deliberation)

            _ ->
              result
          end

        true ->
          result
      end

    if attention_cfg[:trigger_mode] == :demand and max_kappa > 0 do
      maybe_trigger_demand_attention(Map.get(result, :topology, %{}), query)
    end

    result
  end

  defp maybe_enrich_or_deliberate(result, _query, _opts), do: result

  defp enrich_with_topology_notes(result) when is_map(result) do
    topology = Map.get(result, :topology, %{})

    topology_notes =
      topology
      |> Map.get(:sccs, [])
      |> Enum.map(fn scc ->
        fault_lines =
          scc
          |> Map.get(:fault_line_edges, [])
          |> Enum.map(fn
            %{source: s, target: t} -> "#{s} → #{t}"
            %{"source" => s, "target" => t} -> "#{s} → #{t}"
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        %{
          scc_id: Map.get(scc, :id),
          kappa: Map.get(scc, :kappa, 0),
          node_ids: Map.get(scc, :nodes, []),
          note:
            "These #{length(Map.get(scc, :nodes, []))} concepts form a feedback loop (κ=#{Map.get(scc, :kappa, 0)}). " <>
              "Weakest link: #{if(fault_lines == "", do: "unknown", else: fault_lines)}. " <>
              "Consider this circularity when reasoning."
        }
      end)

    Map.put(result, :topology_notes, topology_notes)
  end

  defp maybe_trigger_demand_attention(topology, query) do
    Task.start(fn ->
      _ = Attention.on_demand_check(topology, query)
    end)

    :ok
  rescue
    _ -> :ok
  end

  defp resolve_tier(opts) do
    opts
    |> Keyword.get(:model_tier, ModelTier.current_tier())
    |> ModelTier.normalize_tier()
  end

  defp approx_token_count(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> length()
    |> max(1)
  end

  defp approx_token_count(_), do: 1

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
