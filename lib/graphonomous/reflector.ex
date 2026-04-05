defmodule Graphonomous.Reflector do
  @moduledoc """
  Reflector-style progressive consolidation for Graphonomous (P4-Q10).

  Inspired by Mastra's Observational Memory pattern: periodically re-examines
  stored nodes to extract higher-level patterns and create derived knowledge.

  Unlike the Consolidator (which focuses on graph health: decay, pruning, merging),
  the Reflector creates *new* knowledge by:

    1. **Near-duplicate clustering** — finds groups of nodes with high semantic
       similarity and creates a unified summary node linking them.
    2. **Pattern extraction** — identifies recurring themes across episodic nodes
       and creates semantic "insight" nodes capturing the pattern.
    3. **Session distillation** — for sessions with many turns, creates a
       distilled fact-node capturing the key information.

  The Reflector is designed to be called after ingestion batches or periodically
  during benchmarks to improve retrieval surface area.

  Telemetry events:
    - `[:graphonomous, :reflector, :cycle]`
    - `[:graphonomous, :reflector, :cluster_created]`
    - `[:graphonomous, :reflector, :insight_created]`
    - `[:graphonomous, :reflector, :distilled]`
  """

  require Logger

  alias Graphonomous.{Graph, HNSWIndex}
  alias Graphonomous.Types.Node

  @default_cluster_similarity 0.88
  @default_min_cluster_size 3
  @default_max_clusters 50
  @default_max_session_turns_for_distill 8

  @type opts :: [
          cluster_similarity: float(),
          min_cluster_size: pos_integer(),
          max_clusters: pos_integer()
        ]

  @type result :: %{
          clusters_created: non_neg_integer(),
          insights_extracted: non_neg_integer(),
          sessions_distilled: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @doc """
  Run a full reflector cycle over the current graph.

  Options:
    - `:cluster_similarity` — minimum cosine similarity for clustering (default: 0.88)
    - `:min_cluster_size` — minimum nodes to form a cluster (default: 3)
    - `:max_clusters` — cap on clusters created per cycle (default: 50)
  """
  @spec reflect(opts()) :: {:ok, result()} | {:error, term()}
  def reflect(opts \\ []) do
    started_at = System.monotonic_time(:millisecond)

    cfg = %{
      cluster_similarity: Keyword.get(opts, :cluster_similarity, @default_cluster_similarity),
      min_cluster_size: Keyword.get(opts, :min_cluster_size, @default_min_cluster_size),
      max_clusters: Keyword.get(opts, :max_clusters, @default_max_clusters)
    }

    # Load all active nodes
    nodes =
      case Graph.list_nodes(%{}) do
        {:ok, n} when is_list(n) -> Enum.filter(n, &is_nil(&1.forgotten_at))
        _ -> []
      end

    # Stage 1: Near-duplicate clustering
    clusters_created = stage_cluster_near_duplicates(nodes, cfg)

    # Stage 2: Pattern extraction from episodic nodes
    insights_extracted = stage_extract_patterns(nodes)

    # Stage 3: Session distillation
    sessions_distilled = stage_distill_sessions(nodes)

    duration_ms = System.monotonic_time(:millisecond) - started_at

    result = %{
      clusters_created: clusters_created,
      insights_extracted: insights_extracted,
      sessions_distilled: sessions_distilled,
      duration_ms: duration_ms
    }

    :telemetry.execute(
      [:graphonomous, :reflector, :cycle],
      result,
      %{node_count: length(nodes)}
    )

    Logger.info(
      "Reflector cycle: clusters=#{clusters_created} insights=#{insights_extracted} " <>
        "distilled=#{sessions_distilled} duration=#{duration_ms}ms"
    )

    {:ok, result}
  rescue
    e ->
      Logger.error("Reflector cycle failed: #{inspect(e)}")
      {:error, e}
  end

  # ── Stage 1: Near-duplicate clustering ─────────────────────────────
  #
  # Find groups of nodes with high embedding similarity that haven't already
  # been clustered. Create a summary node for each cluster, linked via
  # :derived_from edges.

  defp stage_cluster_near_duplicates(nodes, cfg) do
    # Only cluster nodes that have embeddings and aren't already cluster summaries
    candidates =
      nodes
      |> Enum.filter(fn node ->
        is_binary(node.embedding) and byte_size(node.embedding) > 0 and
          not is_cluster_summary?(node)
      end)

    if length(candidates) < cfg.min_cluster_size do
      0
    else
      clusters = build_clusters(candidates, cfg.cluster_similarity, cfg.min_cluster_size)

      clusters
      |> Enum.take(cfg.max_clusters)
      |> Enum.reduce(0, fn cluster, count ->
        case create_cluster_summary(cluster) do
          :ok -> count + 1
          :skip -> count
        end
      end)
    end
  end

  defp is_cluster_summary?(%Node{metadata: meta}) when is_map(meta) do
    Map.get(meta, "reflector_type") != nil
  end

  defp is_cluster_summary?(_), do: false

  defp build_clusters(candidates, similarity_threshold, min_size) do
    # Greedy single-linkage clustering using HNSW for neighbor lookup
    # For each unassigned node, find similar nodes and form a cluster
    indexed = Enum.with_index(candidates)
    assigned = MapSet.new()

    {clusters, _} =
      Enum.reduce(indexed, {[], assigned}, fn {node, _idx}, {clusters, assigned} ->
        if MapSet.member?(assigned, node.id) do
          {clusters, assigned}
        else
          # Find neighbors via HNSW
          neighbors =
            case HNSWIndex.query(Graph.decode_embedding_blob(node.embedding), 20) do
              {:ok, hits} ->
                hits
                |> Enum.filter(fn {nid, dist} ->
                  sim = 1.0 - dist

                  nid != node.id and sim >= similarity_threshold and
                    not MapSet.member?(assigned, nid)
                end)
                |> Enum.map(fn {nid, _} -> nid end)

              _ ->
                []
            end

          # Resolve neighbor IDs to actual node structs from our candidate list
          neighbor_nodes =
            Enum.filter(candidates, fn c ->
              c.id in neighbors and not MapSet.member?(assigned, c.id)
            end)

          cluster = [node | neighbor_nodes]

          if length(cluster) >= min_size do
            new_assigned =
              Enum.reduce(cluster, assigned, fn n, acc -> MapSet.put(acc, n.id) end)

            {[cluster | clusters], new_assigned}
          else
            {clusters, assigned}
          end
        end
      end)

    clusters
  end

  defp create_cluster_summary(cluster) do
    member_ids = Enum.map(cluster, & &1.id)

    # Check if a summary already exists for this cluster
    existing_marker = cluster_marker(member_ids)

    case Graph.list_nodes(%{node_type: :semantic}) do
      {:ok, semantics} ->
        already_exists? =
          Enum.any?(semantics, fn n ->
            String.contains?(n.content || "", existing_marker)
          end)

        if already_exists? do
          :skip
        else
          do_create_cluster_summary(cluster, member_ids, existing_marker)
        end

      _ ->
        :skip
    end
  end

  defp do_create_cluster_summary(cluster, member_ids, marker) do
    # Build summary content from cluster members
    snippets =
      cluster
      |> Enum.take(5)
      |> Enum.map(fn node ->
        String.slice(node.content || "", 0, 200)
      end)
      |> Enum.join(" | ")

    avg_confidence =
      cluster
      |> Enum.map(& &1.confidence)
      |> then(fn confs -> Enum.sum(confs) / length(confs) end)

    summary_content =
      "#{marker} Cluster of #{length(cluster)} related nodes: #{String.slice(snippets, 0, 2048)}"

    # Get source from first node
    source = (hd(cluster).source || "reflector") <> "/reflector"

    case Graph.store_node(%{
           content: summary_content,
           node_type: :semantic,
           confidence: min(avg_confidence + 0.05, 0.95),
           source: source,
           creation_source: :consolidation,
           metadata: %{
             "reflector_type" => "cluster_summary",
             "cluster_size" => length(cluster),
             "member_ids" => Enum.take(member_ids, 10)
           }
         }) do
      {:ok, summary} ->
        # Link summary to cluster members
        Enum.each(member_ids, fn mid ->
          Graph.create_edge(%{
            source_id: summary.id,
            target_id: mid,
            edge_type: :derived_from,
            weight: 0.8,
            metadata: %{"source" => "reflector"}
          })
        end)

        :telemetry.execute(
          [:graphonomous, :reflector, :cluster_created],
          %{cluster_size: length(cluster)},
          %{summary_id: summary.id}
        )

        :ok

      _ ->
        :skip
    end
  end

  defp cluster_marker(member_ids) do
    # Deterministic marker from sorted member IDs (first 3)
    sig =
      member_ids
      |> Enum.sort()
      |> Enum.take(3)
      |> Enum.join(",")
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    "[Cluster:#{sig}]"
  end

  # ── Stage 2: Pattern extraction ────────────────────────────────────
  #
  # Look for recurring themes in episodic nodes grouped by source/session.
  # If 5+ episodic nodes from different sessions share similar content
  # patterns, create a semantic "insight" node.

  defp stage_extract_patterns(nodes) do
    episodic =
      nodes
      |> Enum.filter(&(&1.node_type == :episodic and not is_cluster_summary?(&1)))

    if length(episodic) < 5 do
      0
    else
      # Group by content keywords (simple approach: extract top nouns/entities)
      # Find nodes that share entities across different sessions
      entity_groups = group_by_shared_entities(episodic)

      entity_groups
      |> Enum.take(20)
      |> Enum.reduce(0, fn {entity, group_nodes}, count ->
        if length(group_nodes) >= 5 and cross_session?(group_nodes) do
          case create_insight_node(entity, group_nodes) do
            :ok -> count + 1
            :skip -> count
          end
        else
          count
        end
      end)
    end
  end

  defp group_by_shared_entities(episodic_nodes) do
    episodic_nodes
    |> Enum.flat_map(fn node ->
      entities = extract_content_entities(node.content || "")
      Enum.map(entities, fn ent -> {ent, node} end)
    end)
    |> Enum.group_by(fn {ent, _} -> ent end, fn {_, node} -> node end)
    |> Enum.filter(fn {_ent, nodes} -> length(nodes) >= 5 end)
    |> Enum.sort_by(fn {_ent, nodes} -> -length(nodes) end)
  end

  defp extract_content_entities(text) when is_binary(text) do
    # Extract capitalized proper nouns (skip sentence-initial words)
    sentences = String.split(text, ~r/[.!?\n]+/)

    Enum.flat_map(sentences, fn sentence ->
      words = String.split(String.trim(sentence), ~r/\s+/)

      words
      |> Enum.drop(1)
      |> Enum.filter(fn word ->
        byte_size(word) >= 3 and String.match?(word, ~r/^[A-Z][a-z]/)
      end)
      |> Enum.map(&String.downcase/1)
    end)
    |> Enum.uniq()
  end

  defp extract_content_entities(_), do: []

  defp cross_session?(nodes) do
    sessions =
      nodes
      |> Enum.map(fn n ->
        case n.metadata do
          %{"session_id" => sid} when is_binary(sid) -> sid
          _ -> n.id
        end
      end)
      |> Enum.uniq()

    length(sessions) >= 2
  end

  defp create_insight_node(entity, nodes) do
    marker = "[Insight:#{entity}]"

    case Graph.list_nodes(%{node_type: :semantic}) do
      {:ok, semantics} ->
        already_exists? =
          Enum.any?(semantics, fn n ->
            String.contains?(n.content || "", marker)
          end)

        if already_exists? do
          :skip
        else
          session_count =
            nodes
            |> Enum.map(&get_in(&1.metadata, ["session_id"]))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()
            |> length()

          snippets =
            nodes
            |> Enum.take(3)
            |> Enum.map(fn n -> String.slice(n.content || "", 0, 150) end)
            |> Enum.join(" | ")

          content =
            "#{marker} Entity '#{entity}' appears across #{session_count} sessions " <>
              "(#{length(nodes)} mentions). Context: #{String.slice(snippets, 0, 1024)}"

          case Graph.store_node(%{
                 content: content,
                 node_type: :semantic,
                 confidence: 0.65,
                 source: "reflector/pattern",
                 creation_source: :consolidation,
                 metadata: %{
                   "reflector_type" => "insight",
                   "entity" => entity,
                   "mention_count" => length(nodes),
                   "session_count" => session_count
                 }
               }) do
            {:ok, insight} ->
              # Link to a sample of source nodes
              nodes
              |> Enum.take(5)
              |> Enum.each(fn n ->
                Graph.create_edge(%{
                  source_id: insight.id,
                  target_id: n.id,
                  edge_type: :derived_from,
                  weight: 0.7,
                  metadata: %{"source" => "reflector_pattern"}
                })
              end)

              :telemetry.execute(
                [:graphonomous, :reflector, :insight_created],
                %{mention_count: length(nodes), session_count: session_count},
                %{insight_id: insight.id, entity: entity}
              )

              :ok

            _ ->
              :skip
          end
        end

      _ ->
        :skip
    end
  end

  # ── Stage 3: Session distillation ──────────────────────────────────
  #
  # For sessions with many turns, create a distilled "key facts" node that
  # captures the most important information. This improves retrieval for
  # questions about specific facts buried in long sessions.

  defp stage_distill_sessions(nodes) do
    # Group episodic nodes by session
    sessions =
      nodes
      |> Enum.filter(fn n ->
        n.node_type == :episodic and
          is_map(n.metadata) and
          Map.has_key?(n.metadata, "session_id") and
          Map.get(n.metadata, "is_summary") != true
      end)
      |> Enum.group_by(fn n -> n.metadata["session_id"] end)
      |> Enum.filter(fn {_sid, turns} ->
        length(turns) >= @default_max_session_turns_for_distill
      end)

    Enum.reduce(sessions, 0, fn {session_id, turns}, count ->
      case distill_session(session_id, turns) do
        :ok -> count + 1
        :skip -> count
      end
    end)
  end

  defp distill_session(session_id, turns) do
    marker = "[Distilled:#{session_id}]"

    # Check if already distilled
    case Graph.list_nodes(%{node_type: :semantic}) do
      {:ok, semantics} ->
        already_exists? =
          Enum.any?(semantics, fn n ->
            String.contains?(n.content || "", marker)
          end)

        if already_exists? do
          :skip
        else
          do_distill_session(session_id, turns, marker)
        end

      _ ->
        :skip
    end
  end

  defp do_distill_session(session_id, turns, marker) do
    # Sort by turn_index
    sorted =
      turns
      |> Enum.sort_by(fn n ->
        case n.metadata do
          %{"turn_index" => idx} when is_integer(idx) -> idx
          _ -> 0
        end
      end)

    # Extract key facts: preference statements, identity claims, specific answers
    key_facts =
      sorted
      |> Enum.flat_map(fn node ->
        content = node.content || ""
        facts = extract_key_facts(content)
        Enum.map(facts, fn fact -> {fact, node.id} end)
      end)
      |> Enum.take(15)

    if key_facts == [] do
      :skip
    else
      facts_text =
        key_facts
        |> Enum.map(fn {fact, _} -> "- #{fact}" end)
        |> Enum.join("\n")

      content =
        "#{marker} Key facts from session #{session_id} (#{length(turns)} turns):\n#{String.slice(facts_text, 0, 2048)}"

      case Graph.store_node(%{
             content: content,
             node_type: :semantic,
             confidence: 0.75,
             source: "reflector/distill",
             creation_source: :consolidation,
             metadata: %{
               "reflector_type" => "distilled",
               "session_id" => session_id,
               "turn_count" => length(turns),
               "fact_count" => length(key_facts)
             }
           }) do
        {:ok, distilled} ->
          # Link to source nodes that contributed facts
          key_facts
          |> Enum.map(fn {_, nid} -> nid end)
          |> Enum.uniq()
          |> Enum.take(10)
          |> Enum.each(fn nid ->
            Graph.create_edge(%{
              source_id: distilled.id,
              target_id: nid,
              edge_type: :derived_from,
              weight: 0.75,
              metadata: %{"source" => "reflector_distill"}
            })
          end)

          :telemetry.execute(
            [:graphonomous, :reflector, :distilled],
            %{turn_count: length(turns), fact_count: length(key_facts)},
            %{distilled_id: distilled.id, session_id: session_id}
          )

          :ok

        _ ->
          :skip
      end
    end
  end

  # Extract preference, identity, and factual statements from content
  @fact_preference_re ~r/(?:I|i) (?:prefer|like|love|enjoy|hate|dislike)\s+(.{3,80}?)(?:\.|,|$)/
  @fact_identity_re ~r/(?:I am|I'm|i am|i'm) (?:a |an )?(.{3,60}?)(?:\.|,|$)/
  @fact_personal_re ~r/(?:My|my) (?:name|favorite|pet|cat|dog|car|job|hobby|address|phone|email)\s+(?:is\s+)?(.{2,60}?)(?:\.|,|$)/
  @fact_location_re ~r/(?:I live|I'm from|I moved to)\s+(?:in |at |near )?(.{3,60}?)(?:\.|,|$)/i
  @fact_work_re ~r/(?:I work|I'm working)\s+(?:at |for |as )?(.{3,60}?)(?:\.|,|$)/i

  defp extract_key_facts(content) when is_binary(content) do
    facts =
      scan_facts(@fact_preference_re, content, "Preference") ++
        scan_facts(@fact_identity_re, content, "Identity") ++
        scan_facts(@fact_personal_re, content, "Personal") ++
        scan_facts(@fact_location_re, content, "Location") ++
        scan_facts(@fact_work_re, content, "Work")

    Enum.uniq(facts)
  end

  defp extract_key_facts(_), do: []

  defp scan_facts(pattern, content, label) do
    Regex.scan(pattern, content)
    |> Enum.map(fn
      [_, obj] -> "#{label}: #{String.trim(obj)}"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
