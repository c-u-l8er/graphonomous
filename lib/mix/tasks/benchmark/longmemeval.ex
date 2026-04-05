defmodule Mix.Tasks.Benchmark.Longmemeval do
  @moduledoc """
  LongMemEval Benchmark: Competitive Memory Evaluation

  Runs the LongMemEval benchmark (ICLR 2025, Xiao Wu et al.) against
  Graphonomous for direct competitive comparison with Hindsight (91.4%),
  Zep/Graphiti (~63-67%), Letta/MemGPT (~50-80%), and vanilla RAG baselines.

  LongMemEval evaluates 5 core long-term memory abilities across 500 questions:
    1. Information Extraction (single-session-user, single-session-assistant,
       single-session-preference)
    2. Multi-Session Reasoning (multi-session)
    3. Temporal Reasoning (temporal-reasoning)
    4. Knowledge Updates (knowledge-update)
    5. Abstention (question_id ending in _abs)

  Evaluation metrics (GPT-4o-free, self-contained):
    - Session Hit Rate (SHR): primary — did retrieval find answer sessions?
    - Turn Evidence Recall (TER): did retrieval find has_answer=true turns?
    - Answer Keyword F1: keyword overlap between retrieved text and expected answer
    - Abstention Accuracy: correctly low-confidence on unanswerable questions

  Prerequisites:
    1. Download data: cd graphonomous/priv/longmemeval && bash download.sh
    2. Run: mix benchmark.longmemeval [--split oracle|s] [--limit N] [--purge]

  Options:
    --split    Dataset split: "oracle" (evidence-only, fast) or "s" (full haystack).
               Default: oracle
    --limit    Max questions to evaluate (default: all 500)
    --purge    Purge graph before ingestion (default: true)
    --neural        Use neural embeddings (requires EXLA/GPU)
    --skip-ingest   Skip ingestion, reuse cached graph from previous run (~100x faster)

  Competitive baselines (from published literature):
    - Hindsight (Vectorize, 2026): 91.4% QA accuracy
    - Emergence AI (RAG, 2025): ~87% (SOTA on LongMemEval with RAG)
    - Mastra Observational Memory (2025): ~95% (claimed)
    - Zep/Graphiti (2025): ~63-67% QA accuracy
    - Letta/MemGPT (2023): ~50-80% (varies by task)
    - GPT-4 128K context: ~62-65%
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Run LongMemEval benchmark for competitive memory comparison"

  # Map question_types to the 5 core LongMemEval abilities
  @ability_map %{
    "single-session-user" => :information_extraction,
    "single-session-assistant" => :information_extraction,
    "single-session-preference" => :information_extraction,
    "multi-session" => :multi_session_reasoning,
    "temporal-reasoning" => :temporal_reasoning,
    "knowledge-update" => :knowledge_update
  }

  @competitive_baselines %{
    "agentmemory V4 (Opus 4.6)" => 96.2,
    "OMEGA (GPT-4.1)" => 95.4,
    "Mastra OM (GPT-5-mini)" => 94.87,
    "Hindsight v0.4.19" => 94.6,
    "Emergence AI (RAG)" => 87.0,
    "Supermemory (Gemini-3)" => 85.2,
    "Mastra OM (GPT-4o)" => 84.23,
    "Zep/Graphiti" => 71.2,
    "Letta/MemGPT" => 65.0,
    "GPT-4 128K (full ctx)" => 63.5
  }

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          split: :string,
          limit: :integer,
          purge: :boolean,
          neural: :boolean,
          skip_ingest: :boolean,
          skip_topology: :boolean,
          judge: :boolean,
          reflect: :boolean
        ]
      )

    split = Keyword.get(opts, :split, "oracle")
    limit = Keyword.get(opts, :limit, 500)
    purge = Keyword.get(opts, :purge, true)
    skip_ingest = Keyword.get(opts, :skip_ingest, false)
    skip_topology = Keyword.get(opts, :skip_topology, false)
    judge = Keyword.get(opts, :judge, false)
    reflect = Keyword.get(opts, :reflect, false)

    if opts[:neural], do: Application.put_env(:graphonomous, :benchmark_neural, true)
    if judge, do: Application.put_env(:graphonomous, :benchmark_judge, true)

    if judge and not Mix.Tasks.Benchmark.LlmJudge.available?() do
      Mix.shell().error("--judge requires ANTHROPIC_API_KEY environment variable")
      exit({:shutdown, 1})
    end

    {embedder_info, embedder_runtime} = ensure_neural_embedder_for_benchmark()

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════════╗
    ║  LongMemEval Benchmark — Competitive Memory Evaluation   ║
    ║                                                          ║
    ║  Split:    #{String.pad_trailing(split, 46)}║
    ║  Limit:    #{String.pad_trailing("#{limit} questions", 46)}║
    ║  System:   Graphonomous v#{String.pad_trailing(Mix.Project.config()[:version] || "0.2.0", 33)}║
    ║  Embedder: #{String.pad_trailing(to_string(embedder_runtime), 46)}║
    ╚══════════════════════════════════════════════════════════╝
    """)

    if skip_topology do
      Mix.shell().info("""
      ⚠️  WARNING: Topology is DISABLED for this run (--skip-topology)
          κ-routing, SCC confidence propagation, fault-line boosts, and
          deliberation enrichment are bypassed. Accuracy may be reduced.
      """)
    end

    if limit < 50 do
      Mix.shell().info("""
      ⚠️  WARNING: Very small sample size (limit=#{limit})
          Results may be noisy and unrepresentative, especially since
          questions are evaluated in dataset order.
      """)
    end

    # Load dataset
    dataset = load_dataset(split)

    if dataset == nil or dataset == [] do
      Mix.shell().error("""
      Dataset not found. Download first:
        cd graphonomous/priv/longmemeval && bash download.sh
      """)

      exit({:shutdown, 1})
    end

    questions = Enum.take(dataset, limit)
    total = length(questions)
    Mix.shell().info("Loaded #{total} questions from longmemeval_#{split}")

    # Purge graph for clean benchmark (skip if --skip-ingest)
    if purge and not skip_ingest do
      Mix.shell().info("Purging graph for clean benchmark...")
      Helpers.purge_graph()
    end

    # Phase 1: Ingest all unique sessions (skip if --skip-ingest)
    {ingest_us, ingest_stats} =
      if skip_ingest do
        Mix.shell().info("\n━━━ Phase 1: SKIPPED (--skip-ingest, reusing cached graph) ━━━")
        {0, %{sessions_ingested: 0, turns_ingested: 0}}
      else
        Mix.shell().info("\n━━━ Phase 1: Ingesting Chat Sessions ━━━")
        {us, stats} = Helpers.timed(fn -> ingest_sessions(questions, split) end)

        Mix.shell().info(
          "  Ingested #{stats.sessions_ingested} sessions " <>
            "(#{stats.turns_ingested} turns) in #{div(us, 1000)} ms"
        )

        {us, stats}
      end

    # Phase 1.5: Reflector pass (optional --reflect flag)
    if reflect and not skip_ingest do
      Mix.shell().info("\n━━━ Phase 1.5: Reflector Pass ━━━")

      {reflect_us, reflect_result} =
        Helpers.timed(fn -> Graphonomous.Reflector.reflect() end)

      case reflect_result do
        {:ok, r} ->
          Mix.shell().info(
            "  Reflector: #{r.clusters_created} clusters, #{r.insights_extracted} insights, " <>
              "#{r.sessions_distilled} distilled in #{div(reflect_us, 1000)} ms"
          )

        {:error, reason} ->
          Mix.shell().info("  Reflector failed: #{inspect(reason)}")
      end
    end

    # Phase 2: Evaluate each question
    Mix.shell().info("\n━━━ Phase 2: Evaluating #{total} Questions ━━━")

    {eval_us, question_results} =
      Helpers.timed(fn ->
        questions
        |> Enum.with_index(1)
        |> Enum.map(fn {q, idx} ->
          if rem(idx, 50) == 0 or idx == 1,
            do: Mix.shell().info("  Progress: #{idx}/#{total}...")

          evaluate_question(q, skip_topology)
        end)
      end)

    Mix.shell().info("  Evaluation complete in #{div(eval_us, 1_000_000)} sec")

    # Phase 3: Compute aggregate metrics
    Mix.shell().info("\n━━━ Phase 3: Computing Metrics ━━━")
    metrics = compute_metrics(question_results)

    # Build results
    results = %{
      benchmark: "LongMemEval",
      version: "1.0.0",
      reference: "arXiv:2410.10813 (ICLR 2025)",
      dataset_split: split,
      questions_evaluated: total,
      system: %{
        engine: "Graphonomous",
        engine_version: Mix.Project.config()[:version] || "0.2.0",
        embedder: to_string(embedder_runtime),
        embedder_runtime: %{
          backend: to_string(Map.get(embedder_info, :backend, :unknown)),
          status: to_string(Map.get(embedder_info, :status, :unknown)),
          model_id: Map.get(embedder_info, :model_id)
        },
        retrieval_params: %{
          similarity_limit: "adaptive (15-25)",
          final_limit: "adaptive (30-50)",
          expansion_hops: "adaptive (1-2)",
          neighbors_per_node: 8,
          topology_mode: if(skip_topology, do: "disabled", else: "enabled")
        }
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      ingest: %{
        sessions: ingest_stats.sessions_ingested,
        turns: ingest_stats.turns_ingested,
        duration_ms: div(ingest_us, 1000)
      },
      evaluation: %{
        duration_ms: div(eval_us, 1000),
        mean_query_ms: div(div(eval_us, 1000), max(total, 1))
      },
      metrics: metrics,
      competitive_baselines: @competitive_baselines,
      questions: question_results
    }

    path = Helpers.write_results("longmemeval", results)

    # Print competitive comparison
    print_results(metrics, split, total, path)
  end

  # Ordered preference: best model first.
  # nomic-v2-moe: MoE architecture, 768D, highest quality. Uses dense-forward ONNX export.
  # nomic-v1.5: standard transformer fallback, same 768D, ONNX-stable.
  # MiniLM: last resort, 384D.
  @benchmark_model_cascade [
    {"nomic-ai/nomic-embed-text-v2-moe", 768,
     %{query: "search_query: ", document: "search_document: "}},
    {"nomic-ai/nomic-embed-text-v1.5", 768,
     %{query: "search_query: ", document: "search_document: "}},
    {"sentence-transformers/all-MiniLM-L6-v2", 384, nil}
  ]

  defp ensure_neural_embedder_for_benchmark do
    Enum.reduce_while(@benchmark_model_cascade, nil, fn {model, dim, prefixes}, _acc ->
      Mix.shell().info("  Trying benchmark embedder: #{model} (#{dim}D)")

      Application.put_env(:graphonomous, :embedding_model_id, model)
      Application.put_env(:graphonomous, :embedding_dimension, dim)
      Application.put_env(:graphonomous, :embedding_task_prefixes, prefixes)

      Helpers.ensure_started(backend: :onnx)

      embedder_info = Graphonomous.Embedder.info()
      backend = Map.get(embedder_info, :backend, :unknown)

      if backend in [:onnx, :bumblebee] and inference_smoke_test?() do
        Mix.shell().info("  ✓ #{model} ready (#{backend}, inference verified)")
        {:halt, {embedder_info, backend}}
      else
        Mix.shell().info("  ✗ #{model} failed (backend=#{backend}, inference broken)")
        {:cont, nil}
      end
    end)
    |> case do
      nil ->
        Mix.shell().info("  ⚠️  All neural models failed — running with fallback embedder")
        embedder_info = Graphonomous.Embedder.info()
        {embedder_info, :fallback}

      result ->
        result
    end
  end

  # Smoke-test actual inference, not just model loading.
  defp inference_smoke_test? do
    case Graphonomous.Embedder.embed("benchmark smoke test") do
      {:ok, vec} when is_list(vec) ->
        # Verify it's not a deterministic fallback (all values near-uniform)
        unique_vals = vec |> Enum.take(20) |> Enum.uniq() |> length()
        unique_vals > 5

      _ ->
        false
    end
  end

  # ── Dataset Loading ──────────────────────────────────────────────

  defp load_dataset(split) do
    filename =
      case split do
        "oracle" -> "longmemeval_oracle.json"
        "s" -> "longmemeval_s_cleaned.json"
        other -> "longmemeval_#{other}.json"
      end

    data_path =
      Path.join([Helpers.portfolio_root(), "graphonomous", "priv", "longmemeval", filename])

    case File.read(data_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} when is_list(data) -> data
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ── Session Ingestion ────────────────────────────────────────────

  defp ingest_sessions(questions, _split) do
    # Collect all unique sessions across questions
    # Key: session_id, Value: list of turns
    sessions =
      questions
      |> Enum.flat_map(fn q ->
        session_ids = Map.get(q, "haystack_session_ids", [])
        sessions = Map.get(q, "haystack_sessions", [])

        Enum.zip(session_ids, sessions)
      end)
      |> Enum.uniq_by(fn {sid, _} -> sid end)

    Mix.shell().info("  Found #{length(sessions)} unique sessions to ingest")

    # Phase 1: Ingest sessions in parallel, collect entity index for cross-session linking (S2)
    # P2-I2: Parallel session ingestion via Task.async_stream (sessions are independent)
    # P3-Q2: Track session_rank for cross-session temporal ordering
    max_concurrency = System.schedulers_online() |> min(8)

    {total_turns, entity_index} =
      sessions
      |> Enum.with_index()
      |> Task.async_stream(
        fn {{session_id, turns}, session_rank} ->
          {_node_ids, entities_by_node} = ingest_session(session_id, turns, session_rank)
          {session_id, length(turns), entities_by_node}
        end,
        max_concurrency: max_concurrency,
        timeout: 120_000,
        ordered: false
      )
      |> Enum.reduce({0, %{}}, fn {:ok, {session_id, turn_count, entities_by_node}},
                                  {turn_acc, ent_acc} ->
        ent_acc =
          Enum.reduce(entities_by_node, ent_acc, fn {node_id, entities}, acc ->
            Enum.reduce(entities, acc, fn ent, inner ->
              Map.update(inner, ent, [{node_id, session_id}], &[{node_id, session_id} | &1])
            end)
          end)

        {turn_acc + turn_count, ent_acc}
      end)

    # Phase 1.5 (S2): Cross-session entity edges
    cross_edges = build_cross_session_edges(entity_index)
    Mix.shell().info("  Created #{cross_edges} cross-session entity edges")

    %{sessions_ingested: length(sessions), turns_ingested: total_turns}
  end

  defp ingest_session(session_id, turns, session_rank) when is_list(turns) do
    # P2-I1: Batch-embed all turn contents up front instead of per-turn embedding.
    # Graphonomous.store_node skips embedding when :embedding key is already present.
    turn_contents =
      Enum.map(turns, fn turn ->
        role = Map.get(turn, "role", "unknown")
        content = Map.get(turn, "content", "")
        content_for_node = String.slice(content, 0, 4096)
        "[#{role}] #{content_for_node}"
      end)

    embeddings =
      case Graphonomous.Embedder.embed_many_binary(turn_contents, task: :document) do
        {:ok, embs} -> embs
        {:error, _} -> List.duplicate(nil, length(turns))
      end

    # P2-I3: Batch store all turns with a single HNSW batch_add call
    all_attrs =
      turns
      |> Enum.with_index()
      |> Enum.map(fn {turn, turn_idx} ->
        role = Map.get(turn, "role", "unknown")
        content = Map.get(turn, "content", "")
        has_answer = Map.get(turn, "has_answer", false)

        node_content = Enum.at(turn_contents, turn_idx)
        embedding = Enum.at(embeddings, turn_idx)

        # P4-Q7: Extract structured facts for BM25 key expansion
        bm25_facts = extract_facts(content, role)

        # P4-Q8: Dual timestamps — document_date (ingestion) + event_date (content)
        event_date = extract_event_date(content)

        attrs = %{
          content: node_content,
          node_type: :episodic,
          confidence: 0.70,
          source: "longmemeval",
          metadata:
            %{
              "session_id" => session_id,
              "turn_index" => turn_idx,
              "session_rank" => session_rank,
              "role" => role,
              "has_answer" => has_answer,
              "benchmark" => "longmemeval",
              "document_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "event_date" => event_date
            }
            |> then(fn m ->
              if bm25_facts != [], do: Map.put(m, "bm25_facts", bm25_facts), else: m
            end)
        }

        if embedding, do: Map.put(attrs, :embedding, embedding), else: attrs
      end)

    nodes = Graphonomous.store_nodes_batch(all_attrs)

    {node_ids, entities_by_node} =
      turns
      |> Enum.zip(nodes)
      |> Enum.reduce({[], []}, fn {turn, node}, {id_acc, ent_acc} ->
        content = Map.get(turn, "content", "")
        entities = extract_entities(content)
        {[node.id | id_acc], [{node.id, entities} | ent_acc]}
      end)
      |> then(fn {ids, ents} -> {Enum.reverse(ids), Enum.reverse(ents)} end)

    # P3-Q4: Detect knowledge updates within the session.
    # When a user turn contains correction markers, create :superseded_by edge
    # from the previous assistant turn to the corrected version, and reduce confidence.
    detect_knowledge_updates(turns, node_ids)

    # S1: Sequential :follows edges between consecutive turns
    node_ids
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [prev, curr] ->
      Graphonomous.link_nodes(prev, curr, %{
        edge_type: :follows,
        weight: 0.9,
        metadata: %{"session_id" => session_id, "link_type" => "intra_session"}
      })
    end)

    # S3: Session-level summary node (two-level hierarchy like LiCoMemory)
    summary_content =
      turns
      |> Enum.map(fn t ->
        "[#{Map.get(t, "role", "?")}] #{String.slice(Map.get(t, "content", ""), 0, 200)}"
      end)
      |> Enum.join(" | ")

    # P4-Q7: Collect all facts from session turns for summary-level BM25 indexing
    all_session_facts =
      turns
      |> Enum.flat_map(fn t ->
        extract_facts(Map.get(t, "content", ""), Map.get(t, "role", ""))
      end)
      |> Enum.uniq()
      |> Enum.take(20)

    summary_meta =
      %{
        "session_id" => session_id,
        "is_summary" => true,
        "turn_count" => length(turns),
        "session_rank" => session_rank,
        "benchmark" => "longmemeval"
      }
      |> then(fn m ->
        if all_session_facts != [], do: Map.put(m, "bm25_facts", all_session_facts), else: m
      end)

    summary =
      Graphonomous.store_node(%{
        content: "Session #{session_id} summary: #{String.slice(summary_content, 0, 4096)}",
        node_type: :semantic,
        confidence: 0.80,
        source: "longmemeval",
        metadata: summary_meta
      })

    Enum.each(node_ids, fn nid ->
      Graphonomous.link_nodes(summary.id, nid, %{
        edge_type: :part_of,
        weight: 0.85,
        metadata: %{"session_id" => session_id}
      })
    end)

    {node_ids, entities_by_node}
  end

  defp ingest_session(_session_id, _, _session_rank), do: {[], []}

  # S2: Cross-session entity edges — link turns in different sessions
  # that mention the same proper nouns (people, places, topics).
  defp build_cross_session_edges(entity_index) do
    entity_index
    |> Enum.filter(fn {_ent, nodes} ->
      sessions = nodes |> Enum.map(fn {_, sid} -> sid end) |> Enum.uniq()
      length(sessions) >= 2
    end)
    |> Enum.reduce(0, fn {_entity, node_infos}, edge_count ->
      cross_pairs =
        for {n1, s1} <- node_infos,
            {n2, s2} <- node_infos,
            s1 < s2,
            n1 != n2,
            do: {n1, n2}

      pairs = cross_pairs |> Enum.uniq() |> Enum.take(3)

      Enum.each(pairs, fn {n1, n2} ->
        Graphonomous.link_nodes(n1, n2, %{
          edge_type: :related,
          weight: 0.7,
          metadata: %{"link_type" => "cross_session_entity"}
        })
      end)

      edge_count + length(pairs)
    end)
  end

  # P3-Q5: Enhanced entity extraction — captures proper nouns, acronyms,
  # preferences, compound concepts, and hyphenated names. The original only
  # caught capitalized words, missing "Thai food", "GPT-4", "video editing", etc.
  # This directly addresses the 65.1% single-session-preference score (worst category).

  @preference_verbs ~r/\b(?:prefer|like|love|enjoy|hate|dislike|favor|favourite|favorite)\b/i
  @acronym_pattern ~r/\b[A-Z]{2,}(?:-\d+(?:\.\d+)*)?\b/

  defp extract_entities(text) when is_binary(text) do
    sentences = String.split(text, ~r/[.!?\n]+/)

    # 1. Original: capitalized words (proper nouns), skip sentence-initial
    proper_nouns =
      Enum.flat_map(sentences, fn sentence ->
        words = String.split(String.trim(sentence), ~r/\s+/)

        words
        |> Enum.drop(1)
        |> Enum.filter(fn word ->
          byte_size(word) >= 3 and String.match?(word, ~r/^[A-Z][a-z]/)
        end)
      end)

    # 2. Acronyms: GPT-4, NASA, API, HNSW, etc.
    acronyms = Regex.scan(@acronym_pattern, text) |> Enum.map(&hd/1)

    # 3. Hyphenated names: Johnson-Smith, etc.
    hyphenated =
      Regex.scan(~r/\b[A-Z][a-z]+-[A-Z][a-z]+\b/, text)
      |> Enum.map(&hd/1)

    # 4. Preference objects: "I prefer Thai food" → "thai food"
    preference_objects =
      Enum.flat_map(sentences, fn sentence ->
        if Regex.match?(@preference_verbs, sentence) do
          # Extract the object after the preference verb
          case Regex.run(
                 ~r/(?:prefer|like|love|enjoy|hate|dislike|favor|favourite|favorite)\s+(.{3,40}?)(?:\.|,|$|\band\b|\bbut\b|\bbecause\b)/i,
                 sentence
               ) do
            [_, object] -> [String.trim(object)]
            _ -> []
          end
        else
          []
        end
      end)

    # 5. Compound bigrams: consecutive capitalized words → "New York", "San Francisco"
    bigrams =
      Enum.flat_map(sentences, fn sentence ->
        words = String.split(String.trim(sentence), ~r/\s+/)

        words
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [a, b] ->
          String.match?(a, ~r/^[A-Z][a-z]/) and String.match?(b, ~r/^[A-Z][a-z]/)
        end)
        |> Enum.map(fn [a, b] -> "#{a} #{b}" end)
      end)

    (proper_nouns ++ acronyms ++ hyphenated ++ preference_objects ++ bigrams)
    |> Enum.map(fn w ->
      w |> String.replace(~r/[^\w\s-]/, "") |> String.downcase() |> String.trim()
    end)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
  end

  defp extract_entities(_), do: []

  # P4-Q7: Fact-augmented key expansion — extract structured facts from turn content
  # that should be indexed as BM25 keywords. This captures:
  #   1. Preference statements: "I prefer Thai food" → "preference: thai food"
  #   2. Self-descriptions: "I am a teacher" → "identity: teacher"
  #   3. Named entities with context: "My cat Max" → "pet: Max"
  #   4. Activity/hobby mentions: "I enjoy hiking" → "hobby: hiking"
  #   5. Location references: "I live in Seattle" → "location: Seattle"
  # These facts become BM25-searchable even when the original content uses different phrasing.

  @fact_preference_re ~r/(?:I|i) (?:prefer|like|love|enjoy|hate|dislike|favor|want|choose)\s+(.{3,60}?)(?:\.|,|$|\band\b|\bbut\b|\bbecause\b|\bover\b)/
  # Fix 2: "my favorite X is Y" / "X is my favorite"
  @fact_favorite_re ~r/(?:my |the )(?:favorite|favourite|preferred|go-to)\s+(.{2,30}?)\s+(?:is|are|was|would be)\s+(.{2,40}?)(?:\.|,|$|\band\b)/i
  @fact_reverse_favorite_re ~r/(.{3,40}?)\s+(?:is|are|was) (?:my|the) (?:favorite|favourite|preferred|go-to)(?:\s+(.{2,30}?))?(?:\.|,|$)/i
  @fact_identity_re ~r/(?:I am|I'm|i am|i'm) (?:a |an )?(.{3,40}?)(?:\.|,|$|\band\b|\bbut\b|\bwho\b)/
  @fact_location_re ~r/(?:I live|I'm from|I moved to|I'm based|I stay|I reside)\s+(?:in |at |near )?(.{3,40}?)(?:\.|,|$|\band\b|\bbut\b)/i
  @fact_hobby_re ~r/(?:I enjoy|I like to|my hobby is|I usually|I often|I always)\s+(.{3,50}?)(?:\.|,|$|\band\b|\bbut\b)/i
  @fact_possession_re ~r/(?:my |I have a |I own a )(.{3,40}?)(?:\.|,|$|\band\b|\bbut\b|\bnamed\b|\bcalled\b)/i
  @fact_name_re ~r/(?:my name is|I'm called|call me|I go by)\s+(.{2,30}?)(?:\.|,|$|\band\b)/i

  defp extract_facts(content, _role) when is_binary(content) do
    facts = []

    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_preference_re, content), fn
          [_, obj] ->
            trimmed = String.trim(obj)
            ["preference: #{trimmed}", "user prefers #{trimmed}"]

          _ ->
            []
        end)

    # Fix 2: "My favorite food is Thai"
    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_favorite_re, content), fn
          [_, category, value] ->
            cat = String.trim(category)
            val = String.trim(value)
            ["preference: #{val}", "favorite #{cat}: #{val}"]

          _ ->
            []
        end)

    # Fix 2: "Thai food is my favorite"
    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_reverse_favorite_re, content), fn
          [_, subject | _rest] ->
            subj = String.trim(subject)
            ["preference: #{subj}", "user favorite: #{subj}"]

          _ ->
            []
        end)

    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_identity_re, content), fn
          [_, obj] -> ["identity: #{String.trim(obj)}"]
          _ -> []
        end)

    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_location_re, content), fn
          [_, obj] -> ["location: #{String.trim(obj)}"]
          _ -> []
        end)

    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_hobby_re, content), fn
          [_, obj] -> ["hobby: #{String.trim(obj)}"]
          _ -> []
        end)

    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_possession_re, content), fn
          [_, obj] -> ["possession: #{String.trim(obj)}"]
          _ -> []
        end)

    facts =
      facts ++
        Enum.flat_map(Regex.scan(@fact_name_re, content), fn
          [_, obj] -> ["name: #{String.trim(obj)}"]
          _ -> []
        end)

    facts |> Enum.uniq() |> Enum.take(10)
  end

  defp extract_facts(_, _), do: []

  # P4-Q8: Extract event dates from turn content for dual timestamp storage
  @date_iso_re ~r/\b(\d{4}-\d{2}-\d{2})\b/
  @date_month_day_re ~r/\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{4})?\b/i

  defp extract_event_date(content) when is_binary(content) do
    cond do
      # ISO date: 2024-01-15
      match = Regex.run(@date_iso_re, content) ->
        List.last(match) |> validate_date_string()

      # Month Day Year: "January 15, 2024" or "January 15th"
      match = Regex.run(@date_month_day_re, content) ->
        format_month_date(match)

      true ->
        nil
    end
  end

  defp extract_event_date(_), do: nil

  defp validate_date_string(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, _} -> date_str
      _ -> nil
    end
  end

  @month_map %{
    "january" => "01",
    "february" => "02",
    "march" => "03",
    "april" => "04",
    "may" => "05",
    "june" => "06",
    "july" => "07",
    "august" => "08",
    "september" => "09",
    "october" => "10",
    "november" => "11",
    "december" => "12"
  }

  defp format_month_date([_, month, day | rest]) do
    month_num = Map.get(@month_map, String.downcase(month))

    year =
      case rest do
        [y] when is_binary(y) and y != "" -> y
        _ -> "2024"
      end

    day_padded = String.pad_leading(day, 2, "0")
    date_str = "#{year}-#{month_num}-#{day_padded}"
    validate_date_string(date_str)
  end

  defp format_month_date(_), do: nil

  # P3-Q4: Detect knowledge updates within a session during ingestion.
  # When a user turn contains correction markers ("actually", "I changed my mind", etc.),
  # create :superseded_by edges from the most recent assistant turn to the assistant turn
  # following the correction, reducing the old node's confidence.
  # "actually" removed — fires 298/338 times on casual usage ("I actually prefer..."),
  # not corrections. "instead of" removed — common in preference statements.
  # Kept only high-precision correction markers.
  @update_markers_re ~r/\b(?:correction|I changed my mind|I was mistaken|I no longer|I meant|changed to|switched to)\b/i

  defp detect_knowledge_updates(turns, node_ids) do
    paired = Enum.zip(turns, node_ids)

    paired
    |> Enum.with_index()
    |> Enum.each(fn {{turn, _node_id}, idx} ->
      role = Map.get(turn, "role", "")
      content = Map.get(turn, "content", "")

      if role == "user" and Regex.match?(@update_markers_re, content) do
        # Find the most recent assistant turn before this correction
        prev_assistant =
          paired
          |> Enum.take(idx)
          |> Enum.reverse()
          |> Enum.find(fn {t, _id} -> Map.get(t, "role") == "assistant" end)

        # Find the next assistant turn (the corrected response)
        next_assistant =
          paired
          |> Enum.drop(idx + 1)
          |> Enum.find(fn {t, _id} -> Map.get(t, "role") == "assistant" end)

        if prev_assistant && next_assistant do
          {_prev_turn, prev_id} = prev_assistant
          {_next_turn, next_id} = next_assistant

          # Create superseded_by edge: old → new
          Graphonomous.link_nodes(prev_id, next_id, %{
            edge_type: :superseded_by,
            weight: 0.9,
            metadata: %{"source" => "knowledge_update_detection", "automated" => true}
          })

          # Reduce confidence on the superseded node
          Graphonomous.Store.update_node(prev_id, %{
            superseded_by: next_id,
            confidence: 0.21
          })
        end
      end
    end)
  rescue
    _ -> :ok
  end

  # ── Question Evaluation ──────────────────────────────────────────

  defp evaluate_question(q, skip_topology) do
    question_id = Map.get(q, "question_id", "unknown")
    question_type = Map.get(q, "question_type", "unknown")
    question_text = Map.get(q, "question", "")
    expected_answer = Map.get(q, "answer", "") |> to_string()
    answer_session_ids = Map.get(q, "answer_session_ids", [])
    is_abstention = String.ends_with?(question_id, "_abs")

    ability = Map.get(@ability_map, question_type, :unknown)
    if is_abstention, do: :abstention, else: ability

    # S4+S6: Adaptive retrieval limits — multi-session needs wider net
    {sim_limit, final_limit, exp_hops} =
      case question_type do
        "multi-session" -> {25, 50, 2}
        "temporal-reasoning" -> {20, 40, 1}
        _ -> {15, 30, 1}
      end

    # Retrieve from Graphonomous
    {retrieval_us, retrieval} =
      Helpers.timed(fn ->
        Graphonomous.retrieve_context(question_text,
          similarity_limit: sim_limit,
          final_limit: final_limit,
          expansion_hops: exp_hops,
          neighbors_per_node: 8,
          skip_topology: skip_topology
        )
      end)

    # Handle timeout / error from retrieve_context
    {retrieval, timed_out?} =
      case retrieval do
        {:error, _reason} -> {%{results: [], topology: %{}}, true}
        map when is_map(map) -> {map, false}
      end

    results = Map.get(retrieval, :results, [])
    topology = Map.get(retrieval, :topology, %{})

    # Extract session_ids from retrieved nodes
    retrieved_session_ids = extract_session_ids(results)
    retrieved_has_answer_turns = count_evidence_turns(results, answer_session_ids)

    # Metric 1: Session Hit Rate (SHR)
    # Did any retrieved node come from an answer session?
    session_hit =
      if answer_session_ids == [] do
        # Abstention: hit if we correctly retrieved nothing relevant
        if is_abstention, do: true, else: false
      else
        Enum.any?(retrieved_session_ids, &(&1 in answer_session_ids))
      end

    # Metric 2: Session Recall
    # What fraction of answer sessions were retrieved?
    session_recall =
      if answer_session_ids == [] do
        if is_abstention and retrieved_session_ids == [], do: 1.0, else: 0.0
      else
        hits =
          Enum.count(answer_session_ids, fn sid ->
            sid in retrieved_session_ids
          end)

        hits / length(answer_session_ids)
      end

    # Metric 3: Turn Evidence Recall (TER)
    # How many has_answer=true turns were in the retrieved set?
    total_evidence_turns = count_total_evidence_turns(q)

    turn_evidence_recall =
      if total_evidence_turns == 0 do
        if is_abstention, do: 1.0, else: 0.0
      else
        min(retrieved_has_answer_turns / total_evidence_turns, 1.0)
      end

    # Metric 4: Answer Keyword Recall
    # Check if answer keywords appear anywhere in retrieved text
    # Use recall (not F1) because retrieved text is much longer than answer
    retrieved_text = Enum.map(results, & &1.content) |> Enum.join(" ")
    keyword_recall = keyword_recall(expected_answer, retrieved_text)
    keyword_f1 = keyword_f1(expected_answer, retrieved_text)

    # Metric 5: Abstention Detection (Fix 1+4 — learned threshold + retrieval confidence)
    # Use retriever's statistical signals combined with legacy heuristics.
    retrieval_stats = Map.get(retrieval, :stats, %{})

    abstention_correct =
      if is_abstention do
        cond do
          results == [] ->
            true

          # Primary: use retriever's learned abstention signal (ANN stats + confidence)
          Map.get(retrieval_stats, :abstention_signal, false) ->
            true

          # Low retrieval confidence
          Map.get(retrieval_stats, :retrieval_confidence, 1.0) < 0.3 ->
            true

          # Low max ANN similarity — raw cosine signal before reranking
          (Map.get(retrieval_stats, :max_ann_similarity, 1.0) || 1.0) < 0.45 ->
            true

          # Score uniformity — all results are similarly scored (no clear winner)
          length(results) >= 10 and score_uniformity_abstention?(results) ->
            true

          # Legacy fallbacks
          length(results) < 3 ->
            true

          true ->
            # Legacy gap heuristic as final fallback
            scores = Enum.map(results, & &1.score)
            top_score = Enum.max(scores)
            mean_score = Enum.sum(scores) / length(scores)
            gap = top_score - mean_score
            gap < 0.05 or mean_score < 0.25
        end
      else
        nil
      end

    # P4-Q9: Session-level NDCG — measures ranking quality, not just hit/miss.
    # A result is "relevant" (gain=1) if its session_id is in answer_session_ids.
    # Ideal ranking would place all relevant results at the top.
    session_ndcg =
      if answer_session_ids == [] do
        if is_abstention, do: 1.0, else: 0.0
      else
        answer_set = MapSet.new(answer_session_ids)
        compute_session_ndcg(results, answer_set)
      end

    # Composite QA proxy score (weighted combination)
    # This approximates QA accuracy without requiring a judge LLM
    # Session hit is the strongest signal; keyword recall validates content relevance
    qa_proxy =
      cond do
        is_abstention ->
          if abstention_correct, do: 1.0, else: 0.0

        true ->
          # Weight: 35% session hit, 25% keyword recall, 20% session recall,
          #         10% turn evidence, 10% NDCG ranking quality
          w_hit = if session_hit, do: 1.0, else: 0.0

          0.35 * w_hit + 0.25 * keyword_recall + 0.20 * session_recall +
            0.10 * turn_evidence_recall + 0.10 * session_ndcg
      end

    # P3-Q1: LLM judge scoring (optional --judge flag)
    {judge_score, judge_answer, judge_reasoning} =
      if Application.get_env(:graphonomous, :benchmark_judge, false) do
        retrieved_text_for_judge = Enum.map(results, & &1.content) |> Enum.join("\n\n")

        case Mix.Tasks.Benchmark.LlmJudge.judge_answer(
               question_text,
               retrieved_text_for_judge,
               expected_answer
             ) do
          {:ok, %{answer: ans, score: score, reasoning: reasoning}} ->
            {score, ans, reasoning}

          {:error, _} ->
            {nil, nil, nil}
        end
      else
        {nil, nil, nil}
      end

    %{
      question_id: question_id,
      question_type: question_type,
      ability: if(is_abstention, do: :abstention, else: ability),
      is_abstention: is_abstention,
      timed_out: timed_out?,
      retrieval_latency_us: retrieval_us,
      result_count: length(results),
      session_hit: session_hit,
      session_recall: Float.round(session_recall, 4),
      turn_evidence_recall: Float.round(turn_evidence_recall, 4),
      keyword_recall: Float.round(keyword_recall, 4),
      keyword_f1: Float.round(keyword_f1, 4),
      session_ndcg: Float.round(session_ndcg, 4),
      abstention_correct: abstention_correct,
      qa_proxy_score: Float.round(qa_proxy, 4),
      topology_routing: Map.get(topology, :routing),
      topology_kappa: Map.get(topology, :max_kappa, 0),
      answer_sessions_expected: length(answer_session_ids),
      answer_sessions_found: Enum.count(retrieved_session_ids, &(&1 in answer_session_ids)),
      retrieved_session_ids: Enum.uniq(retrieved_session_ids),
      stage_timings: Map.get(retrieval, :stage_timings),
      # Fix 1+4: Retrieval confidence diagnostics
      retrieval_confidence: Map.get(retrieval_stats, :retrieval_confidence),
      max_ann_similarity: Map.get(retrieval_stats, :max_ann_similarity),
      abstention_signal: Map.get(retrieval_stats, :abstention_signal),
      judge_score: judge_score,
      judge_answer: judge_answer,
      judge_reasoning: judge_reasoning
    }
  end

  defp extract_session_ids(results) do
    Enum.flat_map(results, fn r ->
      node_id = Map.get(r, :node_id)

      case Graphonomous.get_node(node_id) do
        %{metadata: meta} when is_map(meta) ->
          sid = Map.get(meta, "session_id")
          if sid, do: [sid], else: []

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp count_evidence_turns(results, answer_session_ids) do
    answer_set = MapSet.new(answer_session_ids)

    Enum.count(results, fn r ->
      node_id = Map.get(r, :node_id)

      case Graphonomous.get_node(node_id) do
        %{metadata: meta} when is_map(meta) ->
          Map.get(meta, "has_answer", false) == true and
            MapSet.member?(answer_set, Map.get(meta, "session_id", ""))

        _ ->
          false
      end
    end)
  end

  defp count_total_evidence_turns(q) do
    sessions = Map.get(q, "haystack_sessions", [])

    Enum.reduce(sessions, 0, fn session, acc ->
      if is_list(session) do
        acc + Enum.count(session, fn turn -> Map.get(turn, "has_answer", false) == true end)
      else
        acc
      end
    end)
  end

  # ── Session-level NDCG (P4-Q9) ─────────────────────────────────
  # Normalized Discounted Cumulative Gain using binary relevance:
  # A result at rank i is relevant (gain=1) if its session_id ∈ answer_session_ids.
  # DCG = Σ gain_i / log2(i+1), NDCG = DCG / ideal_DCG

  defp compute_session_ndcg(results, answer_set) when is_list(results) do
    relevance =
      Enum.map(results, fn r ->
        node_id = Map.get(r, :node_id)

        sid =
          case Graphonomous.get_node(node_id) do
            %{metadata: meta} when is_map(meta) -> Map.get(meta, "session_id")
            _ -> nil
          end

        if sid && MapSet.member?(answer_set, sid), do: 1.0, else: 0.0
      end)

    dcg = compute_dcg(relevance)
    ideal = relevance |> Enum.sort(:desc) |> compute_dcg()

    if ideal > 0.0, do: min(dcg / ideal, 1.0), else: 0.0
  end

  defp compute_dcg(gains) do
    gains
    |> Enum.with_index(1)
    |> Enum.reduce(0.0, fn {gain, rank}, sum ->
      sum + gain / :math.log2(rank + 1)
    end)
  end

  # Fix 1+4: Score uniformity check for abstention detection.
  # When top 10 results have very similar scores (low CV), no clear match exists.
  defp score_uniformity_abstention?(results) when length(results) >= 10 do
    top_scores = results |> Enum.take(10) |> Enum.map(& &1.score)
    mean = Enum.sum(top_scores) / length(top_scores)
    top_score = List.first(top_scores, 0.0)

    if mean > 0.0 do
      variance =
        Enum.sum(Enum.map(top_scores, fn s -> (s - mean) * (s - mean) end)) / length(top_scores)

      stddev = :math.sqrt(variance)
      cv = stddev / mean

      score_10 = List.last(top_scores, 0.0)
      ratio = if score_10 > 0.0, do: top_score / score_10, else: 10.0

      cv < 0.15 and ratio < 1.3
    else
      true
    end
  end

  defp score_uniformity_abstention?(_), do: false

  # ── Keyword Metrics ──────────────────────────────────────────────

  defp keyword_recall(answer, retrieved_text)
       when is_binary(answer) and is_binary(retrieved_text) do
    if answer == "" or retrieved_text == "" do
      0.0
    else
      answer_tokens = tokenize(answer)
      retrieved_tokens = tokenize(retrieved_text)

      if MapSet.size(answer_tokens) == 0 do
        0.0
      else
        overlap = MapSet.intersection(answer_tokens, retrieved_tokens)
        MapSet.size(overlap) / MapSet.size(answer_tokens)
      end
    end
  end

  defp keyword_recall(_, _), do: 0.0

  defp keyword_f1(answer, retrieved_text) when is_binary(answer) and is_binary(retrieved_text) do
    if answer == "" or retrieved_text == "", do: 0.0, else: do_keyword_f1(answer, retrieved_text)
  end

  defp keyword_f1(_, _), do: 0.0

  defp do_keyword_f1(answer, retrieved_text) do
    answer_tokens = tokenize(answer)
    retrieved_tokens = tokenize(retrieved_text)

    if MapSet.size(answer_tokens) == 0, do: 0.0, else: compute_f1(answer_tokens, retrieved_tokens)
  end

  defp compute_f1(answer_tokens, retrieved_tokens) do
    overlap = MapSet.intersection(answer_tokens, retrieved_tokens)
    overlap_size = MapSet.size(overlap)

    if overlap_size == 0 do
      0.0
    else
      precision = overlap_size / max(MapSet.size(retrieved_tokens), 1)
      recall = overlap_size / MapSet.size(answer_tokens)
      2.0 * precision * recall / (precision + recall)
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in stopwords()))
    |> MapSet.new()
  end

  defp stopwords do
    ~w(the a an is are was were be been being have has had do does did
       will would shall should may might can could of in to for with on
       at by from as into about between through after before above below
       it its i me my we our they them their this that these those and
       or but not no nor so yet both either neither each every all any
       few more most some such than too very just also how what which
       who whom when where why there here)
  end

  # ── Aggregate Metrics ────────────────────────────────────────────

  defp compute_metrics(question_results) do
    non_abstention = Enum.reject(question_results, & &1.is_abstention)
    abstention = Enum.filter(question_results, & &1.is_abstention)

    overall = %{
      session_hit_rate: pct(non_abstention, :session_hit),
      mean_session_recall: mean(non_abstention, :session_recall),
      mean_turn_evidence_recall: mean(non_abstention, :turn_evidence_recall),
      mean_keyword_recall: mean(non_abstention, :keyword_recall),
      mean_keyword_f1: mean(non_abstention, :keyword_f1),
      mean_session_ndcg: mean(non_abstention, :session_ndcg),
      mean_qa_proxy: mean(question_results, :qa_proxy_score),
      qa_proxy_pct: Float.round(mean(question_results, :qa_proxy_score) * 100, 1),
      mean_latency_ms: div(round(mean(question_results, :retrieval_latency_us)), 1000),
      total_questions: length(question_results),
      non_abstention_count: length(non_abstention),
      abstention_count: length(abstention),
      timeout_count: Enum.count(question_results, & &1.timed_out),
      judge_qa_accuracy: judge_accuracy(question_results)
    }

    abstention_metrics =
      if abstention != [] do
        %{
          accuracy: pct(abstention, :abstention_correct),
          count: length(abstention)
        }
      else
        %{accuracy: 0.0, count: 0}
      end

    # By ability
    by_ability =
      question_results
      |> Enum.group_by(& &1.ability)
      |> Enum.map(fn {ability, items} ->
        {ability,
         %{
           count: length(items),
           session_hit_rate: pct(items, :session_hit),
           mean_session_recall: mean(items, :session_recall),
           mean_keyword_f1: mean(items, :keyword_f1),
           mean_qa_proxy: mean(items, :qa_proxy_score),
           qa_proxy_pct: Float.round(mean(items, :qa_proxy_score) * 100, 1)
         }}
      end)
      |> Map.new()

    # By question_type
    by_type =
      question_results
      |> Enum.group_by(& &1.question_type)
      |> Enum.map(fn {type, items} ->
        {type,
         %{
           count: length(items),
           session_hit_rate: pct(items, :session_hit),
           mean_keyword_f1: mean(items, :keyword_f1),
           mean_qa_proxy: mean(items, :qa_proxy_score),
           qa_proxy_pct: Float.round(mean(items, :qa_proxy_score) * 100, 1)
         }}
      end)
      |> Map.new()

    # Aggregate stage timings (P0 instrumentation)
    stage_timing_agg =
      question_results
      |> Enum.map(& &1.stage_timings)
      |> Enum.reject(&is_nil/1)
      |> aggregate_stage_timings()

    %{
      overall: overall,
      abstention: abstention_metrics,
      by_ability: by_ability,
      by_question_type: by_type,
      stage_timings: stage_timing_agg
    }
  end

  defp aggregate_stage_timings([]), do: %{}

  defp aggregate_stage_timings(all_timings) do
    stages =
      all_timings
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    n = length(all_timings)

    Map.new(stages, fn stage ->
      values =
        all_timings
        |> Enum.map(&Map.get(&1, stage, 0))
        |> Enum.sort()

      {stage,
       %{
         mean_ms: Float.round(Enum.sum(values) / n / 1000, 1),
         p50_ms: Float.round(percentile(values, 50) / 1000, 1),
         p95_ms: Float.round(percentile(values, 95) / 1000, 1),
         max_ms: Float.round(Enum.max(values) / 1000, 1)
       }}
    end)
  end

  defp percentile(sorted, p) when is_list(sorted) and length(sorted) > 0 do
    k = max(0, (p / 100 * length(sorted) - 1) |> Float.ceil() |> trunc())
    Enum.at(sorted, min(k, length(sorted) - 1))
  end

  defp pct(items, field) when items != [] do
    hits = Enum.count(items, fn item -> Map.get(item, field) == true end)
    Float.round(hits / length(items) * 100, 1)
  end

  defp pct(_, _), do: 0.0

  defp mean(items, field) when items != [] do
    values = Enum.map(items, fn item -> Map.get(item, field, 0) end)
    sum = Enum.sum(values)

    val =
      if is_float(sum) or is_float(hd(values)) do
        sum / length(values)
      else
        sum / length(values)
      end

    if is_float(val), do: Float.round(val, 4), else: val
  end

  defp mean(_, _), do: 0.0

  defp judge_accuracy(results) do
    judged = Enum.filter(results, fn r -> r[:judge_score] != nil end)

    if judged == [] do
      nil
    else
      mean_score = Enum.sum(Enum.map(judged, & &1.judge_score)) / length(judged)
      Float.round(mean_score * 100, 1)
    end
  end

  # ── Output ───────────────────────────────────────────────────────

  defp print_results(metrics, split, total, path) do
    o = metrics.overall

    Mix.shell().info("""

    ╔══════════════════════════════════════════════════════════╗
    ║           LongMemEval BENCHMARK RESULTS                  ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Split: #{String.pad_trailing(split, 49)}║
    ║  Questions: #{String.pad_trailing("#{total}", 45)}║
    ║  Timeouts:  #{String.pad_trailing("#{o.timeout_count}", 45)}║
    ║  Embedder:  #{String.pad_trailing(Application.get_env(:graphonomous, :embedder_backend, :auto) |> to_string(), 45)}║
    ║                                                          ║
    ║  OVERALL METRICS                                         ║
    ║  ─────────────────────────────────────                   ║
    ║  Session Hit Rate:      #{String.pad_trailing("#{o.session_hit_rate}%", 31)}║
    ║  Mean Session Recall:   #{String.pad_trailing("#{o.mean_session_recall}", 31)}║
    ║  Mean Turn Evidence:    #{String.pad_trailing("#{o.mean_turn_evidence_recall}", 31)}║
    ║  Mean Keyword Recall:   #{String.pad_trailing("#{o.mean_keyword_recall}", 31)}║
    ║  QA Proxy Score:        #{String.pad_trailing("#{o.qa_proxy_pct}%", 31)}║
    ║  Mean Latency:          #{String.pad_trailing("#{o.mean_latency_ms} ms", 31)}║
    """)

    if o.judge_qa_accuracy do
      Mix.shell().info(
        "    ║  Judge QA Accuracy:     #{String.pad_trailing("#{o.judge_qa_accuracy}%", 31)}║"
      )
    end

    Mix.shell().info("""
    ╠══════════════════════════════════════════════════════════╣
    ║  COMPETITIVE COMPARISON (QA Proxy %)                     ║
    ║  ─────────────────────────────────────                   ║
    """)

    # Sort baselines + our result for comparison
    all_scores =
      @competitive_baselines
      |> Map.put("Graphonomous v0.3.2", o.qa_proxy_pct)
      |> Enum.sort_by(fn {_, v} -> -v end)

    Enum.each(all_scores, fn {name, score} ->
      marker = if name == "Graphonomous v0.3.2", do: " ◀ YOU", else: ""
      formatted = "#{score}%#{marker}"

      Mix.shell().info(
        "    ║  #{String.pad_trailing(name, 28)} #{String.pad_trailing(formatted, 27)}║"
      )
    end)

    Mix.shell().info("""
    ╠══════════════════════════════════════════════════════════╣
    ║  BY ABILITY                                              ║
    ║  ─────────────────────────────────────                   ║
    """)

    metrics.by_ability
    |> Enum.sort_by(fn {_, v} -> -v.qa_proxy_pct end)
    |> Enum.each(fn {ability, v} ->
      label = "#{ability} (#{v.count})"
      score = "SHR=#{v.session_hit_rate}% QA=#{v.qa_proxy_pct}%"

      Mix.shell().info(
        "    ║  #{String.pad_trailing(label, 32)} #{String.pad_trailing(score, 23)}║"
      )
    end)

    abs = metrics.abstention

    Mix.shell().info("""
    ║                                                          ║
    ║  ABSTENTION: #{String.pad_trailing("#{abs.accuracy}% accuracy (#{abs.count} questions)", 44)}║
    """)

    if metrics.stage_timings != %{} do
      Mix.shell().info("""
      ╠══════════════════════════════════════════════════════════╣
      ║  STAGE TIMINGS (mean / p50 / p95 ms)                     ║
      ║  ─────────────────────────────────────                   ║
      """)

      metrics.stage_timings
      |> Enum.sort_by(fn {_, v} -> -v.mean_ms end)
      |> Enum.each(fn {stage, v} ->
        label = stage |> to_string() |> String.pad_trailing(22)
        vals = "#{v.mean_ms} / #{v.p50_ms} / #{v.p95_ms}"

        Mix.shell().info("    ║  #{label} #{String.pad_trailing(vals, 33)}║")
      end)
    end

    Mix.shell().info("""
    ╠══════════════════════════════════════════════════════════╣
    ║  Output: #{String.pad_trailing(path, 48)}║
    ╚══════════════════════════════════════════════════════════╝
    """)
  end
end
