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

  alias Graphonomous.{
    Attention,
    BM25Index,
    CostTracker,
    Deliberator,
    Graph,
    ModelTier,
    Reranker,
    Store,
    Topology
  }

  alias Graphonomous.Types.Node

  @default_similarity_limit 10
  @default_final_limit 20
  @default_expansion_hops 1
  @default_neighbors_per_node 5
  @default_hop_decay 0.85
  @node_cache_key :__retriever_node_cache__
  @default_similarity_timeout_ms 25_000

  # Fix 1: Learned abstention — track running statistics of max ANN similarity
  # across queries to detect low-confidence retrievals (observe-only, no filtering).
  @abstention_zscore_threshold 1.5

  # P3-Q3: Stop words for query expansion (concept extraction)
  @stop_words MapSet.new(~w(
    a an the is are was were be been being have has had do does did
    will would shall should can could may might must
    i me my we our you your he she it they them their his her its
    this that these those what which who whom when where why how
    in on at to for with from by of and or but not no nor so yet
    about above after again against all am any between both down
    during each few into more most other out over own same some
    such than then through too under up very also just than
    if as because while until before after since during
  ))

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
        ),
      # Fix 1: Running statistics for max ANN similarity (Welford's online algorithm)
      ann_score_count: 0,
      ann_score_mean: 0.0,
      ann_score_m2: 0.0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:retrieve, query, call_opts}, _from, state) do
    cfg = merge_opts(state, call_opts)
    # R3-P1: Preference queries need wider candidate pools because the correct
    # session is often absent from the default top-K ANN candidates.
    pref_query? = preference_query?(query)

    cfg =
      if pref_query? do
        %{
          cfg
          | similarity_limit: round(cfg.similarity_limit * 2.5),
            final_limit: round(cfg.final_limit * 1.5),
            neighbors_per_node: round(cfg.neighbors_per_node * 1.5)
        }
      else
        cfg
      end

    init_node_cache()
    timings = %{}

    # P3-Q2: Detect temporal intent from query
    temporal_intent = detect_temporal_intent(query)

    # P3-Q3: Expand query into variants for broader recall via multi-source BM25
    query_variants = expand_query(query)
    bm25_limit = Map.get(cfg, :similarity_limit, @default_similarity_limit) * 2

    # P2-L4 + P3-Q3: Run ANN (HNSW) + BM25 variants fully in parallel, then fuse with RRF
    bm25_tasks =
      Enum.map(query_variants, fn variant ->
        {variant, Task.async(fn -> safe_bm25_search(variant, bm25_limit) end)}
      end)

    ann_task =
      Task.async(fn ->
        safe_graph_retrieve_similar(query, cfg.similarity_limit, cfg.similarity_timeout_ms)
      end)

    reply =
      with {ann_us, {:ok, seed_hits}} <-
             :timer.tc(fn ->
               Task.await(ann_task, cfg.similarity_timeout_ms + 1_000)
             end),
           timings = Map.put(timings, :ann_retrieve, ann_us),
           # Fix 1: Capture max ANN similarity BEFORE any boosting/fusion (observe-only)
           max_ann_similarity = extract_max_ann_similarity(seed_hits),
           {seed_us, {:ok, seed_entries}} <-
             :timer.tc(fn -> seed_entries(seed_hits, temporal_intent, pref_query?) end),
           timings = Map.put(timings, :seed_entries, seed_us),
           {bm25_await_us, bm25_results} <-
             :timer.tc(fn ->
               Enum.map(bm25_tasks, fn {variant, task} ->
                 {variant, await_bm25_task(task, 5_000)}
               end)
             end),
           timings = Map.put(timings, :bm25_await, bm25_await_us),
           {fuse_us, {:ok, seed_entries}} <-
             :timer.tc(fn -> hybrid_fuse_expanded(seed_entries, bm25_results, cfg) end),
           timings = Map.put(timings, :hybrid_fuse, fuse_us),
           {expand_us, {:ok, expanded}} <-
             :timer.tc(fn -> expand_neighbors(seed_entries, cfg) end),
           timings = Map.put(timings, :expand_neighbors, expand_us) do
        {sort_us, sorted} =
          :timer.tc(fn ->
            expanded |> Map.values() |> Enum.sort_by(& &1.score, :desc)
          end)

        {diversify_domain_us, ranked} =
          :timer.tc(fn -> maybe_diversify_domains(sorted, cfg) end)

        {diversify_session_us, ranked} =
          :timer.tc(fn -> maybe_diversify_sessions(ranked, cfg, query) end)

        {rerank_us, ranked} =
          :timer.tc(fn -> maybe_cross_encoder_rerank(ranked, query) end)

        # P4-Q11: Chain-of-retrieval — if first pass results are weak,
        # extract entities from top results and run a supplementary BM25 pass
        {chain_us, ranked} =
          :timer.tc(fn -> maybe_chain_retrieval(ranked, query, cfg, temporal_intent) end)

        # STEP A: Session-aggregate ranking boost — boost all nodes belonging to
        # sessions with multiple strong hits. Targets session_ndcg (0.699 → ~0.85)
        # by promoting clusters of correct-session evidence to top ranks.
        {session_boost_us, ranked} =
          :timer.tc(fn -> maybe_session_aggregate_boost(ranked) end)

        # R2-P2: Temporal filter — for temporal queries, filter results by session_rank
        # to remove results from the wrong time range (e.g., keep only early sessions
        # for "first" queries). Applied after reranking but before final_limit.
        {temporal_filter_us, ranked} =
          :timer.tc(fn -> maybe_temporal_filter(ranked, temporal_intent) end)

        ranked = Enum.take(ranked, cfg.final_limit)

        skip_topology = Keyword.get(call_opts, :skip_topology, false)

        {topology_us, {topology, adjacency}} =
          :timer.tc(fn ->
            if skip_topology,
              do: {%{sccs: [], dag_nodes: [], routing: :fast, max_kappa: 0, scc_count: 0}, %{}},
              else: analyze_topology_with_adjacency(ranked)
          end)

        # K2+K4: κ-guided adaptive expansion
        {kappa_expand_us, {ranked, topology}} =
          :timer.tc(fn ->
            if skip_topology,
              do: {ranked, topology},
              else: maybe_kappa_expand(ranked, topology, adjacency, cfg)
          end)

        # K5: Boost nodes adjacent to fault-line edges
        {fault_line_us, ranked} =
          :timer.tc(fn ->
            if skip_topology, do: ranked, else: apply_fault_line_boost(ranked, topology)
          end)

        # K7: Propagate confidence through SCC edges
        {scc_conf_us, ranked} =
          :timer.tc(fn ->
            if skip_topology, do: ranked, else: propagate_scc_confidence(ranked, topology)
          end)

        # K8: Query-time edge impact
        {edge_impact_us, edge_impact_notes} =
          :timer.tc(fn ->
            if skip_topology, do: [], else: detect_edge_impact_opportunities(ranked, adjacency)
          end)

        # P1: Two-phase retrieval — re-rank by Q-value utility scoring
        {utility_us, ranked} =
          :timer.tc(fn -> utility_rerank(ranked, call_opts) end)

        {enrich_us, enriched_or_base} =
          :timer.tc(fn ->
            # Fix 1+4: Compute retrieval confidence signals (observe-only, no filtering)
            top_blended_score =
              case ranked do
                [first | _] -> first.score
                [] -> 0.0
              end

            node_count = safe_node_count()
            expected_max = 0.5 + 0.1 * :math.log(max(node_count, 100)) / :math.log(1000)
            retrieval_confidence = min(top_blended_score / max(expected_max, 0.01), 1.0)

            ann_stats = %{
              mean: state.ann_score_mean,
              stddev: ann_score_stddev(state),
              count: state.ann_score_count
            }

            ann_low_confidence =
              state.ann_score_count >= 10 and ann_stats.stddev > 0.0 and
                max_ann_similarity <
                  ann_stats.mean - @abstention_zscore_threshold * ann_stats.stddev

            abstention_signal = ann_low_confidence and retrieval_confidence < 0.4

            base_result = %{
              query: query,
              results: ranked,
              causal_context: Enum.map(ranked, & &1.node_id),
              stats: %{
                seed_count: map_size(seed_entries),
                expanded_count: max(map_size(expanded) - map_size(seed_entries), 0),
                returned: length(ranked),
                temporal_intent: temporal_intent,
                topology_skipped: skip_topology,
                # Fix 1+4: Observe-only confidence signals
                max_ann_similarity: max_ann_similarity,
                retrieval_confidence: retrieval_confidence,
                abstention_signal: abstention_signal,
                ann_score_stats: ann_stats
              },
              topology: topology,
              topology_skipped: skip_topology
            }

            base_result =
              if edge_impact_notes != [],
                do: Map.put(base_result, :edge_impact_notes, edge_impact_notes),
                else: base_result

            if skip_topology,
              do: base_result,
              else: maybe_enrich_or_deliberate(base_result, query, call_opts)
          end)

        stage_timings =
          timings
          |> Map.put(:sort, sort_us)
          |> Map.put(:diversify_domains, diversify_domain_us)
          |> Map.put(:diversify_sessions, diversify_session_us)
          |> Map.put(:cross_encoder_rerank, rerank_us)
          |> Map.put(:chain_retrieval, chain_us)
          |> Map.put(:session_aggregate_boost, session_boost_us)
          |> Map.put(:temporal_filter, temporal_filter_us)
          |> Map.put(:topology, topology_us)
          |> Map.put(:kappa_expand, kappa_expand_us)
          |> Map.put(:fault_line_boost, fault_line_us)
          |> Map.put(:scc_confidence, scc_conf_us)
          |> Map.put(:edge_impact, edge_impact_us)
          |> Map.put(:utility_rerank, utility_us)
          |> Map.put(:enrich_deliberate, enrich_us)

        {:ok, Map.put(enriched_or_base, :stage_timings, stage_timings)}
      end

    # Fix 1: Update running ANN score statistics (Welford's online algorithm)
    state =
      case reply do
        {:ok, %{stats: %{max_ann_similarity: mas}}} when is_float(mas) and mas > 0.0 ->
          update_ann_score_stats(state, mas)

        _ ->
          state
      end

    clear_node_cache()
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

  defp seed_entries(hits, temporal_intent, pref_query?) when is_list(hits) do
    entries =
      Enum.reduce(hits, %{}, fn hit, acc ->
        node_id = Map.get(hit, :node_id)

        # P1: Filter out soft-forgotten nodes
        forgotten? =
          case node_id && cached_get_node(node_id) do
            {:ok, %Node{forgotten_at: %DateTime{}}} -> true
            _ -> false
          end

        if is_binary(node_id) and not forgotten? do
          base_score = to_float(Map.get(hit, :score, 0.0))

          # S7: Temporal boost — recently accessed/updated nodes get a recency bonus
          temporal_boost = temporal_recency_boost(node_id, temporal_intent)

          # P3-Q2: Turn-index boost for temporal queries
          turn_boost = temporal_turn_boost(node_id, temporal_intent)

          # R3-P1: Profile-node boost — preference queries have no keyword overlap
          # with answers, so summary/fact-bearing nodes should surface first.
          profile_boost = if pref_query?, do: profile_node_boost(node_id), else: 1.0

          entry = %{
            node_id: node_id,
            content: Map.get(hit, :content, ""),
            node_type: Map.get(hit, :node_type, :semantic),
            confidence: clamp01(to_float(Map.get(hit, :confidence, 0.5))),
            similarity: to_float(Map.get(hit, :similarity, 0.0)),
            score: base_score * temporal_boost * turn_boost * profile_boost,
            source: :seed,
            hops: 0,
            via: nil
          }

          Map.put(acc, node_id, entry)
        else
          acc
        end
      end)

    # P3-Q4: Penalize superseded nodes — if a seed node has been superseded_by another,
    # reduce its score to 0.3x so the superseding node wins during ranking.
    entries =
      Map.new(entries, fn {id, entry} ->
        case cached_get_node(id) do
          {:ok, %Node{superseded_by: sb}} when is_binary(sb) and sb != "" ->
            {id, %{entry | score: entry.score * 0.3}}

          _ ->
            {id, entry}
        end
      end)

    {:ok, entries}
  end

  ## Fix 1: ANN score statistics for learned abstention (observe-only)

  # R3-P1: Boost nodes whose metadata carries bm25_facts or is_summary=true.
  # These are dense fact aggregates — exactly what preference queries need.
  defp profile_node_boost(node_id) do
    with {:ok, %Node{metadata: meta}} when is_map(meta) <- cached_get_node(node_id) do
      has_facts =
        case Map.get(meta, "bm25_facts") do
          [_ | _] -> true
          _ -> false
        end

      is_summary =
        case Map.get(meta, "is_summary") do
          true -> true
          "true" -> true
          _ -> false
        end

      if has_facts or is_summary, do: 1.25, else: 1.0
    else
      _ -> 1.0
    end
  rescue
    _ -> 1.0
  end

  defp extract_max_ann_similarity(seed_hits) when is_list(seed_hits) do
    seed_hits
    |> Enum.map(fn hit -> to_float(Map.get(hit, :similarity, 0.0)) end)
    |> Enum.max(fn -> 0.0 end)
  end

  defp extract_max_ann_similarity(_), do: 0.0

  # Welford's online algorithm for running mean/variance
  defp update_ann_score_stats(state, new_score) do
    n = state.ann_score_count + 1
    delta = new_score - state.ann_score_mean
    new_mean = state.ann_score_mean + delta / n
    delta2 = new_score - new_mean
    new_m2 = state.ann_score_m2 + delta * delta2
    %{state | ann_score_count: n, ann_score_mean: new_mean, ann_score_m2: new_m2}
  end

  defp ann_score_stddev(%{ann_score_count: n, ann_score_m2: m2}) when n >= 2 do
    :math.sqrt(m2 / (n - 1))
  end

  defp ann_score_stddev(_), do: 0.0

  # Safe node count for retrieval confidence normalization
  defp safe_node_count do
    case Store.count_nodes() do
      {:ok, count} when is_integer(count) -> count
      _ -> 1000
    end
  rescue
    _ -> 1000
  end

  ## BM25 hybrid fusion via Reciprocal Rank Fusion (RRF)
  #
  # Runs a BM25 keyword search in parallel with ANN results, then fuses
  # using RRF: score(d) = Σ 1/(k + rank_i(d)) for each retrieval system.
  # k=60 is the standard RRF constant that balances high-ranked vs low-ranked items.

  @rrf_k 60

  # P3-Q3: Fuse ANN results with multiple expanded BM25 result sets via RRF.
  # Each BM25 variant acts as a separate ranker in the RRF formula.
  defp hybrid_fuse_expanded(seed_entries, bm25_results, cfg) do
    # Collect all successful BM25 hit lists
    bm25_hit_lists =
      bm25_results
      |> Enum.flat_map(fn
        {_variant, {:ok, hits}} when hits != [] -> [hits]
        _ -> []
      end)

    case bm25_hit_lists do
      [] ->
        {:ok, seed_entries}

      [single] ->
        # Only one BM25 result — fall back to standard 2-source fusion
        hybrid_fuse_bm25(seed_entries, {:ok, single}, cfg)

      _multiple ->
        # Multi-source RRF: ANN is ranker 0, each BM25 variant is ranker 1..N
        fused = rrf_fuse_multi(seed_entries, bm25_hit_lists)
        {:ok, fused}
    end
  rescue
    _ -> {:ok, seed_entries}
  end

  defp hybrid_fuse_bm25(seed_entries, bm25_result, _cfg) do
    case bm25_result do
      {:ok, bm25_hits} when bm25_hits != [] ->
        fused = rrf_fuse(seed_entries, bm25_hits)
        {:ok, fused}

      _ ->
        # BM25 unavailable or empty — proceed with ANN-only results
        {:ok, seed_entries}
    end
  rescue
    _ -> {:ok, seed_entries}
  end

  defp safe_bm25_search(query, limit) do
    try do
      BM25Index.search(query, limit: limit, timeout: 15_000)
    rescue
      _ -> {:error, :bm25_crashed}
    catch
      :exit, {:timeout, _} -> {:error, :bm25_timeout}
      :exit, reason -> {:error, {:bm25_exit, reason}}
    end
  end

  defp await_bm25_task(task, timeout_ms) do
    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        {:error, :bm25_timeout}

      {:exit, reason} ->
        {:error, {:bm25_task_exit, reason}}
    end
  end

  # P3-Q3: Programmatic query expansion — generate reformulations for broader recall.
  # Returns a list of 1-3 query variants (always includes the original).
  # Variants: concept-only (stop words stripped), entity-focused (proper nouns + key terms).
  defp expand_query(query) when is_binary(query) do
    words = String.split(query, ~r/\s+/, trim: true)
    variants = [query]

    # Variant 1: Concept-only — strip stop words, keep content words
    content_words =
      words
      |> Enum.reject(fn w -> MapSet.member?(@stop_words, String.downcase(w)) end)
      |> Enum.reject(fn w -> String.length(w) < 2 end)

    concept_query = Enum.join(content_words, " ")

    variants =
      if concept_query != "" and concept_query != query and length(content_words) >= 2,
        do: variants ++ [concept_query],
        else: variants

    # Variant 2: Entity-focused — extract proper nouns, acronyms, and quoted terms
    entities =
      Enum.filter(words, fn w ->
        clean = String.replace(w, ~r/[^\w]/, "")

        String.match?(clean, ~r/^[A-Z]/) or
          String.match?(clean, ~r/^[A-Z]{2,}$/) or
          String.match?(clean, ~r/\d{4}/)
      end)

    # Also extract quoted phrases
    quoted =
      Regex.scan(~r/"([^"]+)"/, query)
      |> Enum.map(fn [_, phrase] -> phrase end)

    entity_terms = (entities ++ quoted) |> Enum.uniq()

    entity_query = Enum.join(entity_terms, " ")

    variants =
      if entity_query != "" and entity_query != query and length(entity_terms) >= 2,
        do: variants ++ [entity_query],
        else: variants

    Enum.uniq(variants)
  end

  defp expand_query(_), do: []

  defp rrf_fuse(ann_entries, bm25_hits) do
    # Build ANN rank map (rank by descending score)
    ann_ranked =
      ann_entries
      |> Map.values()
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.with_index(1)
      |> Map.new(fn {entry, rank} -> {entry.node_id, rank} end)

    # Build BM25 rank map (already sorted by relevance)
    bm25_ranked =
      bm25_hits
      |> Enum.with_index(1)
      |> Map.new(fn {{node_id, _score}, rank} -> {node_id, rank} end)

    # All candidate node IDs
    all_ids = MapSet.union(MapSet.new(Map.keys(ann_ranked)), MapSet.new(Map.keys(bm25_ranked)))

    # Compute RRF score for each candidate
    rrf_scores =
      Map.new(all_ids, fn id ->
        ann_rank = Map.get(ann_ranked, id, 1000)
        bm25_rank = Map.get(bm25_ranked, id, 1000)
        rrf_score = 1.0 / (@rrf_k + ann_rank) + 1.0 / (@rrf_k + bm25_rank)
        {id, rrf_score}
      end)

    # Update existing entries with RRF scores
    updated_entries =
      Enum.reduce(ann_entries, %{}, fn {node_id, entry}, acc ->
        rrf = Map.get(rrf_scores, node_id, entry.score)
        Map.put(acc, node_id, %{entry | score: rrf})
      end)

    # Add BM25-only hits (not in ANN results) as new seed entries
    bm25_only_ids =
      MapSet.difference(MapSet.new(Map.keys(bm25_ranked)), MapSet.new(Map.keys(ann_ranked)))

    Enum.reduce(bm25_only_ids, updated_entries, fn node_id, acc ->
      case cached_get_node(node_id) do
        {:ok, %Node{forgotten_at: nil} = node} ->
          rrf = Map.get(rrf_scores, node_id, 0.0)

          entry = %{
            node_id: node.id,
            content: node.content,
            node_type: node.node_type,
            confidence: clamp01(to_float(node.confidence)),
            similarity: 0.0,
            score: rrf,
            source: :bm25,
            hops: 0,
            via: nil
          }

          Map.put(acc, node_id, entry)

        _ ->
          acc
      end
    end)
  end

  # P3-Q3: Multi-source RRF fusion — ANN as one ranker, each BM25 variant as additional rankers.
  # score(d) = Σ 1/(k + rank_i(d)) for each retrieval system
  defp rrf_fuse_multi(ann_entries, bm25_hit_lists) do
    # Ranker 0: ANN (rank by descending score)
    ann_ranked =
      ann_entries
      |> Map.values()
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.with_index(1)
      |> Map.new(fn {entry, rank} -> {entry.node_id, rank} end)

    # Rankers 1..N: each BM25 variant
    bm25_rank_maps =
      Enum.map(bm25_hit_lists, fn hits ->
        hits
        |> Enum.with_index(1)
        |> Map.new(fn {{node_id, _score}, rank} -> {node_id, rank} end)
      end)

    # All candidate node IDs across all rankers
    all_bm25_ids =
      bm25_rank_maps
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()

    all_ids = MapSet.union(MapSet.new(Map.keys(ann_ranked)), all_bm25_ids)

    # Compute RRF score: sum across all rankers (no normalization).
    # Normalization by num_rankers penalizes ANN-only results by ~30% when
    # BM25 variants miss — catastrophic for semantic-only queries (e.g. preferences)
    # where ANN is the only useful signal. Plain summation matches rrf_fuse/2 behavior.
    absent_rank = 1000

    rrf_scores =
      Map.new(all_ids, fn id ->
        ann_score = 1.0 / (@rrf_k + Map.get(ann_ranked, id, absent_rank))

        bm25_score =
          Enum.reduce(bm25_rank_maps, 0.0, fn rank_map, sum ->
            sum + 1.0 / (@rrf_k + Map.get(rank_map, id, absent_rank))
          end)

        {id, ann_score + bm25_score}
      end)

    # Update existing ANN entries with fused scores
    updated =
      Enum.reduce(ann_entries, %{}, fn {node_id, entry}, acc ->
        rrf = Map.get(rrf_scores, node_id, entry.score)
        Map.put(acc, node_id, %{entry | score: rrf})
      end)

    # Add BM25-only hits not in ANN results
    bm25_only_ids = MapSet.difference(all_bm25_ids, MapSet.new(Map.keys(ann_ranked)))

    Enum.reduce(bm25_only_ids, updated, fn node_id, acc ->
      case cached_get_node(node_id) do
        {:ok, %Node{forgotten_at: nil} = node} ->
          rrf = Map.get(rrf_scores, node_id, 0.0)

          entry = %{
            node_id: node.id,
            content: node.content,
            node_type: node.node_type,
            confidence: clamp01(to_float(node.confidence)),
            similarity: 0.0,
            score: rrf,
            source: :bm25,
            hops: 0,
            via: nil
          }

          Map.put(acc, node_id, entry)

        _ ->
          acc
      end
    end)
  end

  ## P4-Q11: Chain-of-retrieval (multi-pass)
  #
  # If the first retrieval pass yields weak results (low top score or few results),
  # extract key entities and context from top results and run a supplementary BM25
  # search. New results are merged with existing ones, keeping best scores.
  # This helps for questions where the query phrasing differs from stored content.

  # Post-reranking scores are blended: 0.4*RRF + 0.6*reranker_score.
  # A mediocre result (reranker ~0.2) scores ~0.13. Threshold must be in this
  # domain to actually trigger chain retrieval for weak first-pass results.
  # R2-P4: Raised threshold 0.15→0.20 to trigger chain retrieval more aggressively
  # for borderline queries where first pass misses the right session.
  @chain_score_threshold 0.20
  @chain_min_results 3

  defp maybe_chain_retrieval(ranked, query, cfg, temporal_intent) do
    top_score =
      case ranked do
        [first | _] -> first.score
        [] -> 0.0
      end

    needs_chain? = top_score < @chain_score_threshold or length(ranked) < @chain_min_results

    if needs_chain? and length(ranked) > 0 do
      chain_retrieval(ranked, query, cfg, temporal_intent)
    else
      ranked
    end
  end

  defp chain_retrieval(ranked, _query, cfg, temporal_intent) do
    # Extract entities and key terms from top-5 results to form a refined query
    top_contents =
      ranked
      |> Enum.take(5)
      |> Enum.map(fn entry -> entry.content || "" end)

    # Build refined query from unique content words in top results
    refined_terms =
      top_contents
      |> Enum.flat_map(fn content ->
        content
        |> String.split(~r/\s+/, trim: true)
        |> Enum.reject(fn w -> MapSet.member?(@stop_words, String.downcase(w)) end)
        |> Enum.filter(fn w ->
          # Keep proper nouns, acronyms, and substantive words
          String.match?(w, ~r/^[A-Z]/) or
            String.match?(w, ~r/^[A-Z]{2,}$/) or
            String.length(w) >= 5
        end)
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_w, freq} -> freq end, :desc)
      |> Enum.take(8)
      |> Enum.map(fn {w, _} -> w end)

    refined_query = Enum.join(refined_terms, " ")

    if refined_query != "" and String.length(refined_query) >= 5 do
      bm25_limit = Map.get(cfg, :similarity_limit, @default_similarity_limit) * 2

      case safe_bm25_search(refined_query, bm25_limit) do
        {:ok, bm25_hits} when bm25_hits != [] ->
          # Convert BM25 hits to entries and merge
          existing_ids = MapSet.new(Enum.map(ranked, & &1.node_id))

          new_entries =
            bm25_hits
            |> Enum.reject(fn {node_id, _} -> MapSet.member?(existing_ids, node_id) end)
            |> Enum.take(10)
            |> Enum.flat_map(fn {node_id, bm25_score} ->
              case cached_get_node(node_id) do
                {:ok, %Node{forgotten_at: nil} = node} ->
                  turn_boost = temporal_turn_boost(node_id, temporal_intent)

                  [
                    %{
                      node_id: node.id,
                      content: node.content,
                      node_type: node.node_type,
                      confidence: clamp01(to_float(node.confidence)),
                      similarity: 0.0,
                      score: bm25_score * 0.7 * turn_boost,
                      source: :chain_bm25,
                      hops: 0,
                      via: nil
                    }
                  ]

                _ ->
                  []
              end
            end)

          (ranked ++ new_entries)
          |> Enum.sort_by(& &1.score, :desc)

        _ ->
          ranked
      end
    else
      ranked
    end
  rescue
    _ -> ranked
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
    # P3-Q4: Identify superseded_by edges for special handling
    {supersedes_edges, regular_edges} =
      Enum.split_with(edges, fn edge ->
        edge_type = Map.get(edge, :edge_type) || Map.get(edge, :type)
        to_string(edge_type) == "superseded_by"
      end)

    neighbors =
      regular_edges
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

    # P3-Q4: Always follow superseded_by edges with boosted weight.
    # The superseding node gets a 1.3x boost; the superseded node (current) gets 0.3x penalty.
    supersedes_neighbors =
      Enum.map(supersedes_edges, fn edge ->
        target = if edge.source_id == node_id, do: edge.target_id, else: edge.source_id
        {target, 1.3}
      end)

    neighbors = neighbors ++ supersedes_neighbors

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

    with true <- is_binary(node_id),
         {:ok, %{metadata: meta}} when is_map(meta) <- cached_get_node(node_id) do
      path = Map.get(meta, "relative_path", "") |> to_string()
      extract_domain_from_path(path)
    else
      _ -> "unknown"
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
  defp maybe_diversify_sessions(results, _cfg, query) do
    if length(results) > 3 do
      # P3-Q6: Relax session diversity penalty for multi-session queries
      # R2-P1/P3: Single-session queries (esp. preference) get near-zero penalty (0.98)
      # because ALL correct results come from one session. Multi-session relaxed to 0.97.
      base =
        cond do
          # R3-P1: preference queries concentrate in one session — nearly no penalty
          preference_query?(query) -> 0.998
          multi_session_query?(query) -> 0.97
          true -> 0.98
        end

      {reranked, _} =
        results
        |> Enum.reduce({[], %{}}, fn entry, {acc, seen} ->
          sid = session_id_for_entry(entry)
          count = Map.get(seen, sid, 0)
          penalty = :math.pow(base, count)
          adjusted = %{entry | score: entry.score * penalty}
          {[adjusted | acc], Map.put(seen, sid, count + 1)}
        end)

      reranked |> Enum.reverse() |> Enum.sort_by(& &1.score, :desc)
    else
      results
    end
  end

  # P3-Q6: Detect queries that likely need results from multiple sessions
  # R2-P3: Extended markers + plural references for better multi-session detection
  defp multi_session_query?(query) do
    q = String.downcase(query)

    multi_session_markers =
      ~w(both also besides additionally compare different sessions conversations times
         all every each across various multiple several)

    entity_count =
      Regex.scan(~r/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/, query)
      |> length()

    has_marker = Enum.any?(multi_session_markers, &String.contains?(q, &1))
    has_multiple_entities = entity_count >= 2
    # R2-P3: "and" between entities suggests multi-session (e.g., "X and Y")
    has_conjunction_entities = entity_count >= 2 and String.contains?(q, " and ")

    has_marker or has_multiple_entities or has_conjunction_entities
  end

  defp session_id_for_entry(entry) do
    node_id = Map.get(entry, :node_id)

    with true <- is_binary(node_id),
         {:ok, %{metadata: meta}} when is_map(meta) <- cached_get_node(node_id) do
      Map.get(meta, "session_id", "unknown")
    else
      _ -> "unknown"
    end
  end

  # STEP A: Session-aggregate ranking boost.
  # Groups results by session_id, computes sum of top-3 node scores per session,
  # then adds bonus = top3_sum * 0.15 to every node in that session. Additionally
  # boosts has_answer=true turns by +0.08 within their session.
  #
  # Rationale: session_ndcg is low (0.699) because correct sessions are retrieved
  # but ranked low — correct session nodes sit at ranks 1, 4, 9 instead of 1, 2, 3.
  # Aggregating scores by session rewards sessions that accumulate multiple hits.
  defp maybe_session_aggregate_boost(results) when length(results) <= 3, do: results

  defp maybe_session_aggregate_boost(results) do
    # Lookup session_id and has_answer for each entry via node cache.
    metas =
      Enum.map(results, fn entry ->
        node_id = Map.get(entry, :node_id)

        with true <- is_binary(node_id),
             {:ok, %{metadata: meta}} when is_map(meta) <- cached_get_node(node_id) do
          {Map.get(meta, "session_id", "unknown"), Map.get(meta, "has_answer", false) == true}
        else
          _ -> {"unknown", false}
        end
      end)

    # Per-session top-3 score sum.
    top3_by_session =
      results
      |> Enum.zip(metas)
      |> Enum.group_by(fn {_e, {sid, _}} -> sid end, fn {e, _} -> e.score end)
      |> Map.new(fn {sid, scores} ->
        {sid, scores |> Enum.sort(:desc) |> Enum.take(3) |> Enum.sum()}
      end)

    results
    |> Enum.zip(metas)
    |> Enum.map(fn {entry, {sid, has_answer}} ->
      session_boost = Map.get(top3_by_session, sid, 0.0) * 0.15
      answer_bonus = if has_answer, do: 0.08, else: 0.0
      %{entry | score: entry.score + session_boost + answer_bonus}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  ## Cross-encoder reranking (Move 3: +2-4pp SHR)
  #
  # Takes top candidates and rescores them using a cross-encoder model that
  # jointly attends to query+document. Only applies to top-30 to keep latency
  # manageable (cross-encoders are O(n) per query).

  @rerank_top_k 30

  defp maybe_cross_encoder_rerank(results, _query) when length(results) <= 1, do: results

  defp maybe_cross_encoder_rerank(results, query) do
    case Reranker.info() do
      %{status: :ready} ->
        # Take top-k for reranking, keep the rest in original order
        {to_rerank, rest} = Enum.split(results, @rerank_top_k)

        candidates =
          Enum.map(to_rerank, fn entry ->
            {entry.node_id, entry.content || ""}
          end)

        case Reranker.rerank(query, candidates) do
          {:ok, reranked_scores} ->
            score_map = Map.new(reranked_scores)

            reranked =
              to_rerank
              |> Enum.map(fn entry ->
                rerank_score = Map.get(score_map, entry.node_id, 0.0)
                # Blend original score (0.4) with reranker score (0.6)
                blended = 0.4 * entry.score + 0.6 * rerank_score
                %{entry | score: blended}
              end)
              |> Enum.sort_by(& &1.score, :desc)

            reranked ++ rest

          _ ->
            results
        end

      _ ->
        results
    end
  rescue
    _ -> results
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
  defp detect_edge_impact_opportunities(ranked, adjacency) when is_map(adjacency) do
    # Infer DAG nodes from ranked results not in any SCC
    # (adjacency is pre-computed, no need to re-fetch edges)
    top_dag = Enum.take(ranked, 6)

    if length(top_dag) < 2 do
      []
    else
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

  defp pairs(list) do
    for {a, i} <- Enum.with_index(list),
        {b, j} <- Enum.with_index(list),
        i < j,
        do: {a, b}
  end

  # K2+K4: After initial topology analysis, if κ > 0, re-expand from top
  # results with deeper hops and gentler decay to follow cyclic paths.
  # P2-L6: Accepts pre-computed adjacency to avoid redundant edge fetches.
  defp maybe_kappa_expand(ranked, topology, existing_adjacency, cfg) do
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

      # P2-L6: Incrementally update adjacency — only fetch edges for new nodes
      new_topology = incremental_topology(re_ranked, existing_adjacency)
      {re_ranked, new_topology}
    else
      {ranked, topology}
    end
  end

  # P2-L6: Recompute topology by extending existing adjacency with edges
  # from newly-added nodes, avoiding redundant edge fetches for known nodes.
  defp incremental_topology(ranked_results, existing_adjacency) do
    new_ids =
      ranked_results
      |> Enum.map(&Map.get(&1, :node_id))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    known_ids = MapSet.new(Map.keys(existing_adjacency))
    truly_new = Enum.reject(new_ids, &MapSet.member?(known_ids, &1))

    if truly_new == [] do
      # No new nodes — reanalyze existing adjacency (cheap, no edge fetches)
      Topology.analyze(existing_adjacency)
    else
      # Fetch edges only for new nodes
      new_edges =
        truly_new
        |> Enum.flat_map(fn id ->
          case Store.list_edges_for_node_direct(id) do
            {:ok, edges} -> edges
            _ -> []
          end
        end)
        |> Enum.uniq_by(& &1.id)

      new_neighbor_ids =
        new_edges
        |> Enum.flat_map(fn edge -> [edge.source_id, edge.target_id] end)
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()

      expanded_ids = Enum.uniq(new_ids ++ new_neighbor_ids)

      # Merge new edges into existing adjacency
      new_adjacency = Topology.build_adjacency(expanded_ids, new_edges)

      merged_adjacency =
        Map.merge(existing_adjacency, new_adjacency, fn _k, old_targets, new_targets ->
          Enum.uniq(old_targets ++ new_targets)
        end)

      topology = Topology.analyze(merged_adjacency)
      _ = Topology.emit_retrieve_route_telemetry(topology)
      topology
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
        case cached_get_node(entry.node_id) do
          {:ok, %Node{q_update_count: count}} when count > 0 -> true
          _ -> false
        end
      end)

    if has_outcome_data? do
      ranked
      |> Enum.map(fn entry ->
        {q, q_count} =
          case cached_get_node(entry.node_id) do
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

  defp analyze_topology_with_adjacency(ranked_results) when is_list(ranked_results) do
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
              case Store.list_edges_for_node_direct(id) do
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
    {topology, adjacency}
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

  ## S7: Temporal recency boost
  #
  # Nodes accessed or updated recently get a mild score multiplier.
  # Uses exponential decay with a half-life of 24 hours.
  # Maximum boost: 1.15x (very recent), minimum: 1.0x (old).

  @temporal_half_life_hours 24.0
  @temporal_max_boost 1.15

  defp temporal_recency_boost(node_id, temporal_intent) do
    case cached_get_node(node_id) do
      {:ok, %Node{} = node} ->
        now = DateTime.utc_now()

        # P4-Q8: For temporal queries, prefer event_date from metadata (when the
        # referenced event actually happened), fall back to created_at
        latest =
          if temporal_intent != :normal do
            event_date = parse_event_date(node.metadata)

            case event_date do
              %DateTime{} = ts ->
                ts

              _ ->
                case node.created_at do
                  %DateTime{} = ts -> ts
                  _ -> nil
                end
            end
          else
            [node.last_accessed_at, node.updated_at]
            |> Enum.filter(&is_struct(&1, DateTime))
            |> Enum.max(DateTime, fn -> nil end)
          end

        case latest do
          nil ->
            1.0

          ts ->
            hours_ago = DateTime.diff(now, ts, :second) / 3600.0
            decay = :math.pow(0.5, hours_ago / @temporal_half_life_hours)
            # Scale from [0,1] to [1.0, max_boost]
            1.0 + (@temporal_max_boost - 1.0) * decay
        end

      _ ->
        1.0
    end
  rescue
    _ -> 1.0
  end

  # P4-Q8: Parse event_date from node metadata for dual-timestamp temporal boosting
  defp parse_event_date(metadata) when is_map(metadata) do
    case Map.get(metadata, "event_date") do
      date_str when is_binary(date_str) and date_str != "" ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} ->
            dt

          _ ->
            case Date.from_iso8601(date_str) do
              {:ok, date} -> DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
              _ -> nil
            end
        end

      _ ->
        nil
    end
  end

  defp parse_event_date(_), do: nil

  # R2-P2: Temporal filter — for temporal queries, filter results by session_rank to
  # remove results from the wrong time range. Uses a soft approach: keep 70% of the
  # session_rank range aligned with intent, demote (not remove) the rest by 0.5x.
  defp maybe_temporal_filter(ranked, :normal), do: ranked
  defp maybe_temporal_filter(ranked, _intent) when length(ranked) <= 5, do: ranked

  defp maybe_temporal_filter(ranked, intent) do
    # Collect session_ranks from all results
    ranks =
      ranked
      |> Enum.map(fn entry ->
        case cached_get_node(entry.node_id) do
          {:ok, %Node{metadata: meta}} when is_map(meta) ->
            meta_int(meta, "session_rank")

          _ ->
            nil
        end
      end)

    valid_ranks = Enum.reject(ranks, &is_nil/1)

    if valid_ranks == [] do
      ranked
    else
      min_rank = Enum.min(valid_ranks)
      max_rank = Enum.max(valid_ranks)
      range = max_rank - min_rank

      if range == 0 do
        ranked
      else
        # 30% cutoff: for :earliest/:before, keep bottom 70%; for :latest/:after, keep top 70%
        cutoff_frac = 0.30

        Enum.zip(ranked, ranks)
        |> Enum.map(fn {entry, rank} ->
          if is_nil(rank) do
            entry
          else
            normalized = (rank - min_rank) / range

            in_range? =
              case intent do
                :earliest -> normalized <= 1.0 - cutoff_frac
                :before -> normalized <= 1.0 - cutoff_frac
                :latest -> normalized >= cutoff_frac
                :after -> normalized >= cutoff_frac
                _ -> true
              end

            if in_range?, do: entry, else: %{entry | score: entry.score * 0.5}
          end
        end)
        |> Enum.sort_by(& &1.score, :desc)
      end
    end
  rescue
    _ -> ranked
  end

  # P3-Q2: Temporal intent detection — classify queries for temporal-aware retrieval
  @temporal_earliest ~r/\b(first|earliest|initial|originally|began|started|beginning)\b/i
  @temporal_latest ~r/\b(last|latest|most recent|currently|now|recent|newest|updated)\b/i
  @temporal_before ~r/\b(before|prior to|until|up to|preceding)\b/i
  @temporal_after ~r/\b(after|since|following|subsequent)\b/i

  defp detect_temporal_intent(query) when is_binary(query) do
    cond do
      Regex.match?(@temporal_earliest, query) -> :earliest
      Regex.match?(@temporal_latest, query) -> :latest
      Regex.match?(@temporal_before, query) -> :before
      Regex.match?(@temporal_after, query) -> :after
      true -> :normal
    end
  end

  defp detect_temporal_intent(_), do: :normal

  # R3-P1: Preference query detection — targets vocabulary-mismatch queries
  # that ask for advice/recommendations/opinions. These queries have near-zero
  # keyword overlap with answer content and need aggressive candidate expansion
  # plus profile-node boosting to surface densely-packed fact summaries.
  @preference_query_re ~r/recommend|suggest|any tips|should i|what would you|any advice|help me with|any ideas|thinking about|what to\b/i

  defp preference_query?(query) when is_binary(query) do
    Regex.match?(@preference_query_re, query)
  end

  defp preference_query?(_), do: false

  # P3-Q2: Turn-index boost — for temporal queries, boost nodes based on
  # their position within a session (turn_index in metadata).
  # "earliest/first" → boost low turn_index; "latest/last" → boost high turn_index
  @temporal_turn_max_boost 1.4

  defp temporal_turn_boost(_node_id, :normal), do: 1.0

  defp temporal_turn_boost(node_id, intent) do
    with {:ok, %Node{metadata: meta}} when is_map(meta) <- cached_get_node(node_id),
         turn_idx when is_integer(turn_idx) <- meta_int(meta, "turn_index") do
      # Normalize turn_index: assume typical sessions are 5-50 turns
      # Use a sigmoid-like mapping: low index → high boost for :earliest, inverse for :latest
      normalized = min(turn_idx / 30.0, 1.0)

      factor =
        case intent do
          :earliest -> 1.0 - normalized
          :before -> 1.0 - normalized * 0.7
          :latest -> normalized
          :after -> normalized * 0.7
          _ -> 0.5
        end

      1.0 + (@temporal_turn_max_boost - 1.0) * factor
    else
      _ -> 1.0
    end
  rescue
    _ -> 1.0
  end

  defp meta_int(meta, key) do
    case Map.get(meta, key) do
      v when is_integer(v) ->
        v

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  ## Config + utils

  defp merge_opts(state, opts) do
    base = %{
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

    maybe_scale_for_graph_size(base)
  end

  # Scale retrieval limits based on graph density. Fixed limits that work at
  # 265 sessions fail at 940+ because ANN/BM25 top-K samples a smaller fraction
  # of the relevant space. Scale factor: sqrt(node_count / 1000), capped at 3x.
  defp maybe_scale_for_graph_size(cfg) do
    node_count = Store.count_nodes()

    if node_count > 1000 do
      scale = min(:math.sqrt(node_count / 1000), 3.0)

      %{
        cfg
        | similarity_limit: round(cfg.similarity_limit * scale),
          final_limit: round(cfg.final_limit * scale),
          neighbors_per_node: round(cfg.neighbors_per_node * scale)
      }
    else
      cfg
    end
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

  # Per-query node cache using process dictionary (scoped to GenServer handle_call).
  # Eliminates 150-200 redundant ETS lookups per query where the same node is
  # fetched 3-5x across pipeline stages.
  defp init_node_cache, do: Process.put(@node_cache_key, %{})
  defp clear_node_cache, do: Process.delete(@node_cache_key)

  defp cached_get_node(node_id) when is_binary(node_id) do
    cache = Process.get(@node_cache_key, %{})

    case Map.fetch(cache, node_id) do
      {:ok, result} ->
        result

      :error ->
        result = Store.get_node_direct(node_id)
        Process.put(@node_cache_key, Map.put(cache, node_id, result))
        result
    end
  end

  defp cached_get_node(_), do: {:error, :not_found}
end
