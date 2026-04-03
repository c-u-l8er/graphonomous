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
    --neural   Use neural embeddings (requires EXLA/GPU)

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
    "Hindsight (Vectorize)" => 91.4,
    "Emergence AI (RAG)" => 87.0,
    "Zep/Graphiti" => 65.0,
    "Letta/MemGPT" => 65.0,
    "GPT-4 128K" => 63.5
  }

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [split: :string, limit: :integer, purge: :boolean, neural: :boolean]
      )

    split = Keyword.get(opts, :split, "oracle")
    limit = Keyword.get(opts, :limit, 500)
    purge = Keyword.get(opts, :purge, true)

    if opts[:neural], do: Application.put_env(:graphonomous, :benchmark_neural, true)

    Helpers.ensure_started()

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════════╗
    ║  LongMemEval Benchmark — Competitive Memory Evaluation   ║
    ║                                                          ║
    ║  Split:    #{String.pad_trailing(split, 46)}║
    ║  Limit:    #{String.pad_trailing("#{limit} questions", 46)}║
    ║  System:   Graphonomous v#{String.pad_trailing(Mix.Project.config()[:version] || "0.2.0", 33)}║
    ╚══════════════════════════════════════════════════════════╝
    """)

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

    # Purge graph for clean benchmark
    if purge do
      Mix.shell().info("Purging graph for clean benchmark...")
      Helpers.purge_graph()
    end

    # Phase 1: Ingest all unique sessions
    Mix.shell().info("\n━━━ Phase 1: Ingesting Chat Sessions ━━━")
    {ingest_us, ingest_stats} = Helpers.timed(fn -> ingest_sessions(questions, split) end)

    Mix.shell().info(
      "  Ingested #{ingest_stats.sessions_ingested} sessions " <>
        "(#{ingest_stats.turns_ingested} turns) in #{div(ingest_us, 1000)} ms"
    )

    # Phase 2: Evaluate each question
    Mix.shell().info("\n━━━ Phase 2: Evaluating #{total} Questions ━━━")

    {eval_us, question_results} =
      Helpers.timed(fn ->
        questions
        |> Enum.with_index(1)
        |> Enum.map(fn {q, idx} ->
          if rem(idx, 50) == 0 or idx == 1,
            do: Mix.shell().info("  Progress: #{idx}/#{total}...")

          evaluate_question(q)
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
        embedder: Application.get_env(:graphonomous, :embedder_backend, :auto) |> to_string(),
        retrieval_params: %{
          limit: 10,
          expansion_hops: 1,
          neighbors_per_node: 5
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

    total_turns =
      Enum.reduce(sessions, 0, fn {session_id, turns}, acc ->
        ingest_session(session_id, turns)
        acc + length(turns)
      end)

    %{sessions_ingested: length(sessions), turns_ingested: total_turns}
  end

  defp ingest_session(session_id, turns) when is_list(turns) do
    turns
    |> Enum.with_index()
    |> Enum.each(fn {turn, turn_idx} ->
      role = Map.get(turn, "role", "unknown")
      content = Map.get(turn, "content", "")
      has_answer = Map.get(turn, "has_answer", false)

      # Truncate very long turns for embedding efficiency
      content_for_node = String.slice(content, 0, 4096)

      node_content =
        "[#{role}] #{content_for_node}"

      Graphonomous.store_node(%{
        content: node_content,
        node_type: :episodic,
        confidence: 0.70,
        source: "longmemeval",
        metadata: %{
          "session_id" => session_id,
          "turn_index" => turn_idx,
          "role" => role,
          "has_answer" => has_answer,
          "benchmark" => "longmemeval"
        }
      })
    end)
  end

  defp ingest_session(_session_id, _), do: :ok

  # ── Question Evaluation ──────────────────────────────────────────

  defp evaluate_question(q) do
    question_id = Map.get(q, "question_id", "unknown")
    question_type = Map.get(q, "question_type", "unknown")
    question_text = Map.get(q, "question", "")
    expected_answer = Map.get(q, "answer", "") |> to_string()
    answer_session_ids = Map.get(q, "answer_session_ids", [])
    is_abstention = String.ends_with?(question_id, "_abs")

    ability = Map.get(@ability_map, question_type, :unknown)
    if is_abstention, do: :abstention, else: ability

    # Retrieve from Graphonomous
    {retrieval_us, retrieval} =
      Helpers.timed(fn ->
        Graphonomous.retrieve_context(question_text,
          limit: 10,
          expansion_hops: 1,
          neighbors_per_node: 5
        )
      end)

    results = Map.get(retrieval, :results, [])
    topology = Map.get(retrieval, :topology, %{})

    # Extract session_ids from retrieved nodes
    retrieved_session_ids = extract_session_ids(results)
    retrieved_has_answer_turns = count_evidence_turns(results)

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

    # Metric 5: Abstention Detection
    # For _abs questions: high score if retrieval returns low-confidence results
    abstention_correct =
      if is_abstention do
        avg_score =
          if results == [] do
            0.0
          else
            Enum.sum(Enum.map(results, & &1.score)) / length(results)
          end

        # Low average score or few results suggests correct abstention
        avg_score < 0.15 or length(results) < 3
      else
        nil
      end

    # Composite QA proxy score (weighted combination)
    # This approximates QA accuracy without requiring a judge LLM
    # Session hit is the strongest signal; keyword recall validates content relevance
    qa_proxy =
      cond do
        is_abstention ->
          if abstention_correct, do: 1.0, else: 0.0

        true ->
          # Weight: 40% session hit, 30% keyword recall, 20% session recall, 10% turn evidence
          w_hit = if session_hit, do: 1.0, else: 0.0

          0.40 * w_hit + 0.30 * keyword_recall + 0.20 * session_recall +
            0.10 * turn_evidence_recall
      end

    %{
      question_id: question_id,
      question_type: question_type,
      ability: if(is_abstention, do: :abstention, else: ability),
      is_abstention: is_abstention,
      retrieval_latency_us: retrieval_us,
      result_count: length(results),
      session_hit: session_hit,
      session_recall: Float.round(session_recall, 4),
      turn_evidence_recall: Float.round(turn_evidence_recall, 4),
      keyword_recall: Float.round(keyword_recall, 4),
      keyword_f1: Float.round(keyword_f1, 4),
      abstention_correct: abstention_correct,
      qa_proxy_score: Float.round(qa_proxy, 4),
      topology_routing: Map.get(topology, :routing),
      topology_kappa: Map.get(topology, :max_kappa, 0),
      answer_sessions_expected: length(answer_session_ids),
      answer_sessions_found: Enum.count(retrieved_session_ids, &(&1 in answer_session_ids)),
      retrieved_session_ids: Enum.uniq(retrieved_session_ids)
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

  defp count_evidence_turns(results) do
    Enum.count(results, fn r ->
      node_id = Map.get(r, :node_id)

      case Graphonomous.get_node(node_id) do
        %{metadata: meta} when is_map(meta) ->
          Map.get(meta, "has_answer", false) == true

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
      mean_qa_proxy: mean(question_results, :qa_proxy_score),
      qa_proxy_pct: Float.round(mean(question_results, :qa_proxy_score) * 100, 1),
      mean_latency_ms: div(round(mean(question_results, :retrieval_latency_us)), 1000),
      total_questions: length(question_results),
      non_abstention_count: length(non_abstention),
      abstention_count: length(abstention)
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

    %{
      overall: overall,
      abstention: abstention_metrics,
      by_ability: by_ability,
      by_question_type: by_type
    }
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

  # ── Output ───────────────────────────────────────────────────────

  defp print_results(metrics, split, total, path) do
    o = metrics.overall

    Mix.shell().info("""

    ╔══════════════════════════════════════════════════════════╗
    ║           LongMemEval BENCHMARK RESULTS                  ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Split: #{String.pad_trailing(split, 49)}║
    ║  Questions: #{String.pad_trailing("#{total}", 45)}║
    ║                                                          ║
    ║  OVERALL METRICS                                         ║
    ║  ─────────────────────────────────────                   ║
    ║  Session Hit Rate:      #{String.pad_trailing("#{o.session_hit_rate}%", 31)}║
    ║  Mean Session Recall:   #{String.pad_trailing("#{o.mean_session_recall}", 31)}║
    ║  Mean Turn Evidence:    #{String.pad_trailing("#{o.mean_turn_evidence_recall}", 31)}║
    ║  Mean Keyword Recall:   #{String.pad_trailing("#{o.mean_keyword_recall}", 31)}║
    ║  QA Proxy Score:        #{String.pad_trailing("#{o.qa_proxy_pct}%", 31)}║
    ║  Mean Latency:          #{String.pad_trailing("#{o.mean_latency_ms} ms", 31)}║
    ╠══════════════════════════════════════════════════════════╣
    ║  COMPETITIVE COMPARISON (QA Proxy %)                     ║
    ║  ─────────────────────────────────────                   ║
    """)

    # Sort baselines + our result for comparison
    all_scores =
      @competitive_baselines
      |> Map.put("Graphonomous v0.2.0", o.qa_proxy_pct)
      |> Enum.sort_by(fn {_, v} -> -v end)

    Enum.each(all_scores, fn {name, score} ->
      marker = if name == "Graphonomous v0.2.0", do: " ◀ YOU", else: ""
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
    ╠══════════════════════════════════════════════════════════╣
    ║  Output: #{String.pad_trailing(path, 48)}║
    ╚══════════════════════════════════════════════════════════╝
    """)
  end
end
