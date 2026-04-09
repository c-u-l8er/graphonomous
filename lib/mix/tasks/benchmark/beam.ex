defmodule Mix.Tasks.Benchmark.Beam do
  @moduledoc """
  BEAM Benchmark: Beyond a Million Tokens (ICLR 2026)

  Evaluates Graphonomous against the BEAM benchmark — the industry standard
  for long-context memory systems. 100 conversations, 2,000 questions across
  10 memory abilities at 4 token-length scales (128K/500K/1M/10M).

  Paper: https://arxiv.org/abs/2510.27246
  Repo:  https://github.com/mohammadtavakoli78/BEAM

  Dataset format (per conversation directory):
    chat.json — list of batches, each with nested turn pairs
    topic.json — conversation metadata (category, title, theme)
    probing_questions/probing_questions.json — dict keyed by ability name
    Each question has: question, answer/ideal_response, rubric, source_chat_ids

  Memory abilities tested:
    1. Information Extraction (IE)     6. Contradiction Resolution (CR)
    2. Multi-hop Reasoning (MR)        7. Event Ordering (EO)
    3. Knowledge Update (KU)           8. Instruction Following (IF)
    4. Temporal Reasoning (TR)         9. Preference Following (PF)
    5. Abstention (ABS)               10. Summarization (SUM)

  Prerequisites:
    1. Download data: cd graphonomous/priv/beam && bash download.sh 128k
    2. Run: mix benchmark.beam [--tier 128k] [--limit N] [--purge]

  Options:
    --tier         Token scale: 128k, 500k, 1m, 10m (default: 128k)
    --limit        Max conversations to evaluate (default: all)
    --purge        Purge graph before ingestion (default: true)
    --skip-ingest  Reuse cached graph from previous run
    --judge        Use LLM judge for nugget scoring (requires API key)
    --diagnose     Emit per-question diagnostics

  Competitive baselines (BEAM published + Hindsight blog):
    Tier     | Hindsight | Honcho  | LIGHT   | RAG
    128K     | 73.4%     | 63.0%   | 35.8%   | 32.3%
    500K     | 71.1%     | 64.9%   | 35.9%   | 33.0%
    1M       | 73.9%     | 63.1%   | 33.6%   | 30.7%
    10M      | 64.1%     | 40.6%   | 26.6%   | 24.9%
  """

  use Mix.Task

  alias Graphonomous.{EntityResolver, Store}
  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Run BEAM benchmark for competitive long-context memory evaluation"

  @ability_labels %{
    "abstention" => "Abstention",
    "contradiction_resolution" => "Contradiction Resolution",
    "event_ordering" => "Event Ordering",
    "information_extraction" => "Information Extraction",
    "instruction_following" => "Instruction Following",
    "knowledge_update" => "Knowledge Update",
    "multi_session_reasoning" => "Multi-hop Reasoning",
    "preference_following" => "Preference Following",
    "summarization" => "Summarization",
    "temporal_reasoning" => "Temporal Reasoning"
  }

  # Short codes for display
  @ability_short %{
    "abstention" => "ABS",
    "contradiction_resolution" => "CR",
    "event_ordering" => "EO",
    "information_extraction" => "IE",
    "instruction_following" => "IF",
    "knowledge_update" => "KU",
    "multi_session_reasoning" => "MR",
    "preference_following" => "PF",
    "summarization" => "SUM",
    "temporal_reasoning" => "TR"
  }

  @competitive_baselines %{
    "100k" => %{
      "Hindsight" => 73.4,
      "Honcho" => 63.0,
      "LIGHT (Llama-4)" => 35.8,
      "RAG baseline" => 32.3
    },
    "500k" => %{
      "Hindsight" => 71.1,
      "Honcho" => 64.9,
      "LIGHT (Llama-4)" => 35.9,
      "RAG baseline" => 33.0
    },
    "1m" => %{
      "Hindsight" => 73.9,
      "Honcho" => 63.1,
      "LIGHT (Llama-4)" => 33.6,
      "RAG baseline" => 30.7
    },
    "10m" => %{
      "Hindsight" => 64.1,
      "Honcho" => 40.6,
      "LIGHT (Llama-4)" => 26.6,
      "RAG baseline" => 24.9
    }
  }

  # Map CLI tier args to BEAM directory names (BEAM uses uppercase K/M)
  @tier_dir_map %{
    "128k" => "100K",
    "100k" => "100K",
    "500k" => "500K",
    "1m" => "1M",
    "10m" => "10M"
  }

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          tier: :string,
          limit: :integer,
          purge: :boolean,
          skip_ingest: :boolean,
          judge: :boolean,
          diagnose: :boolean
        ]
      )

    tier = Keyword.get(opts, :tier, "100k") |> String.downcase()
    limit = Keyword.get(opts, :limit, 999)
    purge = Keyword.get(opts, :purge, true)
    skip_ingest = Keyword.get(opts, :skip_ingest, false)
    judge = Keyword.get(opts, :judge, false)
    diagnose = Keyword.get(opts, :diagnose, false)

    if diagnose, do: Application.put_env(:graphonomous, :benchmark_diagnose, true)
    if judge, do: Application.put_env(:graphonomous, :benchmark_judge, true)

    if judge and not Mix.Tasks.Benchmark.LlmJudge.available?() do
      Mix.shell().error(
        "--judge requires ANTHROPIC_API_KEY, OR set GRAPHONOMOUS_JUDGE_BACKEND=lmstudio"
      )

      exit({:shutdown, 1})
    end

    {embedder_info, embedder_runtime} = ensure_neural_embedder()

    tier_label = String.upcase(tier)

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════════╗
    ║  BEAM Benchmark — Beyond a Million Tokens (ICLR 2026)   ║
    ║                                                          ║
    ║  Tier:     #{String.pad_trailing(tier_label, 46)}║
    ║  Limit:    #{String.pad_trailing("#{limit} conversations", 46)}║
    ║  System:   Graphonomous v#{String.pad_trailing(Mix.Project.config()[:version] || "0.3.3", 33)}║
    ║  Embedder: #{String.pad_trailing(to_string(embedder_runtime), 46)}║
    ╚══════════════════════════════════════════════════════════╝
    """)

    # Load dataset
    conversations = load_conversations(tier)

    if conversations == [] do
      Mix.shell().error("""
      No BEAM data found for tier #{tier}. Download first:
        cd graphonomous/priv/beam && bash download.sh
      Then copy: cp -r priv/beam/_beam_repo/chats/#{Map.get(@tier_dir_map, tier, "100K")} priv/beam/#{Map.get(@tier_dir_map, tier, "100K")}
      """)

      exit({:shutdown, 1})
    end

    conversations = Enum.take(conversations, limit)
    total_convos = length(conversations)

    total_questions =
      conversations |> Enum.flat_map(fn c -> Map.get(c, :questions, []) end) |> length()

    Mix.shell().info(
      "Loaded #{total_convos} conversations with #{total_questions} probing questions (#{tier_label} tier)"
    )

    # Purge graph for clean benchmark
    if purge and not skip_ingest do
      Mix.shell().info("Purging graph for clean benchmark...")
      Helpers.purge_graph()
    end

    # Phase 1: Ingest conversations
    {ingest_us, ingest_stats} =
      if skip_ingest do
        Mix.shell().info("\n━━━ Phase 1: SKIPPED (--skip-ingest) ━━━")
        {0, %{conversations_ingested: 0, turns_ingested: 0}}
      else
        Mix.shell().info("\n━━━ Phase 1: Ingesting #{total_convos} Conversations ━━━")

        {us, stats} =
          Helpers.timed(fn -> ingest_conversations(conversations) end)

        Mix.shell().info(
          "  Ingested #{stats.conversations_ingested} conversations " <>
            "(#{stats.turns_ingested} turns) in #{div(us, 1000)} ms"
        )

        {us, stats}
      end

    # Phase 2: Evaluate probing questions
    Mix.shell().info("\n━━━ Phase 2: Evaluating #{total_questions} Probing Questions ━━━")

    {eval_us, question_results} =
      Helpers.timed(fn ->
        conversations
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {convo, convo_idx} ->
          if rem(convo_idx, 5) == 0 or convo_idx == 1,
            do: Mix.shell().info("  Progress: conversation #{convo_idx}/#{total_convos}...")

          evaluate_conversation(convo, diagnose)
        end)
      end)

    Mix.shell().info("  Evaluation complete in #{div(eval_us, 1_000_000)} sec")

    # Phase 3: Compute metrics
    Mix.shell().info("\n━━━ Phase 3: Computing Metrics ━━━")
    metrics = compute_metrics(question_results)

    # Build results
    results = %{
      benchmark: "BEAM",
      version: "1.0.0",
      reference: "arXiv:2510.27246 (ICLR 2026)",
      tier: tier,
      conversations_evaluated: total_convos,
      questions_evaluated: length(question_results),
      system: %{
        engine: "Graphonomous",
        engine_version: Mix.Project.config()[:version] || "0.3.3",
        embedder: to_string(embedder_runtime),
        embedder_info: %{
          backend: to_string(Map.get(embedder_info, :backend, :unknown)),
          model_id: Map.get(embedder_info, :model_id)
        }
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      ingest: %{
        conversations: ingest_stats.conversations_ingested,
        turns: ingest_stats.turns_ingested,
        duration_ms: div(ingest_us, 1000)
      },
      evaluation: %{
        duration_ms: div(eval_us, 1000),
        mean_query_ms: div(div(eval_us, 1000), max(length(question_results), 1))
      },
      metrics: metrics,
      competitive_baselines: Map.get(@competitive_baselines, tier, %{}),
      questions: question_results
    }

    ts = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
    result_name = "beam_#{tier}_#{ts}_C#{total_convos}"
    _ = Helpers.write_results("beam_#{tier}", results)
    path = Helpers.write_results(result_name, results)

    print_results(metrics, tier, total_convos, length(question_results), path)
  end

  # ── Neural Embedder Setup ──────────────────────────────────────

  @benchmark_model_cascade [
    {"nomic-ai/nomic-embed-text-v2-moe", 768,
     %{query: "search_query: ", document: "search_document: "}},
    {"nomic-ai/nomic-embed-text-v1.5", 768,
     %{query: "search_query: ", document: "search_document: "}},
    {"sentence-transformers/all-MiniLM-L6-v2", 384, nil}
  ]

  defp ensure_neural_embedder do
    Enum.reduce_while(@benchmark_model_cascade, nil, fn {model, dim, prefixes}, _acc ->
      Mix.shell().info("  Trying benchmark embedder: #{model} (#{dim}D)")

      Application.put_env(:graphonomous, :embedding_model_id, model)
      Application.put_env(:graphonomous, :embedding_dimension, dim)
      Application.put_env(:graphonomous, :embedding_task_prefixes, prefixes)

      Helpers.ensure_started(backend: :onnx)

      embedder_info = Graphonomous.Embedder.info()
      backend = Map.get(embedder_info, :backend, :unknown)

      if backend in [:onnx, :bumblebee] and inference_smoke_test?() do
        Mix.shell().info("  ✓ #{model} ready (#{backend})")
        {:halt, {embedder_info, backend}}
      else
        Mix.shell().info("  ✗ #{model} failed (backend=#{backend})")
        {:cont, nil}
      end
    end)
    |> case do
      nil ->
        Mix.shell().info("  All neural models failed — running with fallback embedder")
        Helpers.ensure_started(backend: :fallback)
        {Graphonomous.Embedder.info(), :fallback}

      result ->
        result
    end
  end

  defp inference_smoke_test? do
    case Graphonomous.Embedder.embed("benchmark smoke test") do
      {:ok, vec} when is_list(vec) ->
        vec |> Enum.take(20) |> Enum.uniq() |> length() > 5

      _ ->
        false
    end
  end

  # ── Dataset Loading ──────────────────────────────────────────────
  # BEAM format: chats/<TIER>/<N>/ with chat.json, topic.json,
  # probing_questions/probing_questions.json per conversation.
  # chat.json: [{batch_number, turns: [[{role,content,...},...]], time_anchor}]
  # probing_questions.json: {ability_name: [{question, answer, rubric, ...}]}

  defp load_conversations(tier) do
    tier_dir_name = Map.get(@tier_dir_map, tier, String.upcase(tier))

    beam_base = Path.join([Helpers.portfolio_root(), "graphonomous", "priv", "beam"])

    # Try multiple directory layouts
    candidates = [
      Path.join(beam_base, tier_dir_name),
      Path.join([beam_base, "chats_#{tier}"]),
      Path.join([beam_base, "chats", tier_dir_name])
    ]

    convo_dir =
      Enum.find(candidates, fn dir ->
        File.dir?(dir) and
          dir |> File.ls!() |> Enum.any?(fn f -> File.dir?(Path.join(dir, f)) end)
      end)

    if convo_dir == nil do
      []
    else
      convo_dir
      |> File.ls!()
      |> Enum.filter(fn name -> File.dir?(Path.join(convo_dir, name)) end)
      |> Enum.sort_by(fn name ->
        case Integer.parse(name) do
          {n, _} -> n
          :error -> 999_999
        end
      end)
      |> Enum.map(fn dir_name ->
        dir_path = Path.join(convo_dir, dir_name)
        load_single_conversation(dir_path, dir_name)
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  defp load_single_conversation(dir_path, dir_name) do
    chat_path = Path.join(dir_path, "chat.json")
    topic_path = Path.join(dir_path, "topic.json")
    pq_path = Path.join([dir_path, "probing_questions", "probing_questions.json"])

    unless File.exists?(chat_path) and File.exists?(pq_path) do
      nil
    else
      # Load chat turns
      turns = load_chat_turns(chat_path)

      # Load topic
      topic =
        case File.read(topic_path) do
          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, data} -> data
              _ -> %{}
            end

          _ ->
            %{}
        end

      # Load probing questions
      questions = load_probing_questions(pq_path)

      %{
        conversation_id: "beam_#{dir_name}",
        dir_name: dir_name,
        turns: turns,
        topic: Map.get(topic, "title", "unknown"),
        category: Map.get(topic, "category", "unknown"),
        questions: questions
      }
    end
  end

  # Flatten BEAM's nested batch/turn-pair structure into a flat list of turns
  defp load_chat_turns(chat_path) do
    case File.read(chat_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, batches} when is_list(batches) ->
            Enum.flat_map(batches, fn batch ->
              batch_turns = Map.get(batch, "turns", [])
              time_anchor = Map.get(batch, "time_anchor")
              batch_num = Map.get(batch, "batch_number", "0")

              # turns is a list of turn-pairs (each pair is [user_turn, assistant_turn])
              batch_turns
              |> Enum.with_index()
              |> Enum.flat_map(fn {turn_or_pair, pair_idx} ->
                cond do
                  is_list(turn_or_pair) ->
                    # List of turns in a pair
                    Enum.map(turn_or_pair, fn t ->
                      if is_map(t) do
                        Map.merge(t, %{
                          "batch_number" => batch_num,
                          "time_anchor" => time_anchor,
                          "pair_index" => pair_idx
                        })
                      else
                        nil
                      end
                    end)
                    |> Enum.reject(&is_nil/1)

                  is_map(turn_or_pair) ->
                    [
                      Map.merge(turn_or_pair, %{
                        "batch_number" => batch_num,
                        "time_anchor" => time_anchor,
                        "pair_index" => pair_idx
                      })
                    ]

                  true ->
                    []
                end
              end)
            end)

          _ ->
            []
        end

      _ ->
        []
    end
  end

  # Load probing questions from the ability-keyed dict format
  defp load_probing_questions(pq_path) do
    case File.read(pq_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} when is_map(data) ->
            Enum.flat_map(data, fn {ability, questions} ->
              Enum.map(questions, fn q ->
                Map.put(q, "ability", ability)
              end)
            end)

          {:ok, data} when is_list(data) ->
            data

          _ ->
            []
        end

      _ ->
        []
    end
  end

  # ── Conversation Ingestion ────────────────────────────────────────

  defp ingest_conversations(conversations) do
    max_concurrency = System.schedulers_online() |> min(8)

    total_turns =
      conversations
      |> Task.async_stream(
        fn convo ->
          convo_id = convo.conversation_id
          turns = convo.turns
          topic = convo.topic

          ingest_single_conversation(convo_id, turns, topic)
          length(turns)
        end,
        max_concurrency: max_concurrency,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce(0, fn {:ok, count}, acc -> acc + count end)

    %{conversations_ingested: length(conversations), turns_ingested: total_turns}
  end

  defp ingest_single_conversation(convo_id, turns, topic) when is_list(turns) and turns != [] do
    # Batch-embed all turn contents
    turn_contents =
      Enum.map(turns, fn turn ->
        role = Map.get(turn, "role", "unknown")
        content = Map.get(turn, "content", "")
        "[#{role}] #{String.slice(content, 0, 4096)}"
      end)

    embeddings =
      case Graphonomous.Embedder.embed_many_binary(turn_contents, task: :document) do
        {:ok, embs} -> embs
        {:error, _} -> List.duplicate(nil, length(turns))
      end

    all_attrs =
      turns
      |> Enum.with_index()
      |> Enum.map(fn {turn, turn_idx} ->
        role = Map.get(turn, "role", "unknown")
        content = Map.get(turn, "content", "")
        node_content = Enum.at(turn_contents, turn_idx)
        embedding = Enum.at(embeddings, turn_idx)
        chat_id = Map.get(turn, "id", turn_idx)

        bm25_facts = extract_facts(content)

        attrs = %{
          content: node_content,
          node_type: :episodic,
          confidence: 0.70,
          source: "beam",
          metadata:
            %{
              "conversation_id" => convo_id,
              "turn_index" => turn_idx,
              "chat_id" => chat_id,
              "role" => role,
              "topic" => topic,
              "benchmark" => "beam",
              "batch_number" => Map.get(turn, "batch_number"),
              "time_anchor" => Map.get(turn, "time_anchor")
            }
            |> then(fn m ->
              if bm25_facts != [], do: Map.put(m, "bm25_facts", bm25_facts), else: m
            end)
        }

        if embedding, do: Map.put(attrs, :embedding, embedding), else: attrs
      end)

    nodes =
      case Graphonomous.store_nodes_batch(all_attrs) do
        result when is_list(result) -> result
        _error -> []
      end

    unless nodes == [] do
      node_ids = Enum.map(nodes, & &1.id)

      # Sequential :follows edges
      node_ids
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [prev, curr] ->
        Graphonomous.link_nodes(prev, curr, %{
          edge_type: :follows,
          weight: 0.9,
          metadata: %{"conversation_id" => convo_id}
        })
      end)

      # Summary node — keep very compact for large BEAM conversations
      summary_text =
        "BEAM conversation #{convo_id}: #{topic}. " <>
          "#{length(turns)} turns. " <>
          "Topics: #{turns |> Enum.take(5) |> Enum.map(fn t -> String.slice(Map.get(t, "content", ""), 0, 50) end) |> Enum.join("; ")}"

      summary_text = String.slice(summary_text, 0, 512)

      # Pre-embed summary — catch timeout exits from embedder contention
      summary_embedding =
        try do
          case Graphonomous.Embedder.embed_binary(summary_text, task: :document) do
            {:ok, emb} -> emb
            _ -> nil
          end
        catch
          :exit, _ -> nil
        end

      # Only create summary node if pre-embedding succeeded (avoids Graph GenServer crash)
      if summary_embedding do
        try do
          summary =
            Graphonomous.store_node(%{
              content: summary_text,
              node_type: :semantic,
              confidence: 0.80,
              source: "beam",
              embedding: summary_embedding,
              metadata: %{
                "conversation_id" => convo_id,
                "is_summary" => true,
                "turn_count" => length(turns),
                "topic" => topic,
                "benchmark" => "beam"
              }
            })

          # Link summary to sampled turns (every Nth) to avoid edge explosion
          step = max(div(length(node_ids), 20), 1)

          node_ids
          |> Enum.take_every(step)
          |> Enum.take(20)
          |> Enum.each(fn nid ->
            Graphonomous.link_nodes(summary.id, nid, %{
              edge_type: :part_of,
              weight: 0.85,
              metadata: %{"conversation_id" => convo_id}
            })
          end)

          summary
        rescue
          _ -> nil
        catch
          :exit, _ -> nil
        end
      end
    end
  end

  defp ingest_single_conversation(_convo_id, _turns, _topic), do: :ok

  # ── Fact Extraction for BM25 ────────────────────────────────────

  @fact_preference_re ~r/(?:I|i) (?:prefer|like|love|enjoy|hate|dislike|favor|want|choose)\s+(.{3,60}?)(?:\.|,|$|\band\b|\bbut\b)/
  @fact_identity_re ~r/(?:I am|I'm|i am|i'm) (?:a |an )?(.{3,40}?)(?:\.|,|$|\band\b|\bbut\b)/
  @fact_location_re ~r/(?:I live|I'm from|I moved to|I'm based)\s+(?:in |at |near )?(.{3,40}?)(?:\.|,|$|\band\b|\bbut\b)/i

  defp extract_facts(content) when is_binary(content) do
    facts =
      Enum.flat_map(Regex.scan(@fact_preference_re, content), fn
        [_, obj] -> ["preference: #{String.trim(obj)}"]
        _ -> []
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

    facts |> Enum.uniq() |> Enum.take(15)
  end

  defp extract_facts(_), do: []

  # ── Context Distillation Pipeline ──────────────────────────────────
  # Three-layer pipeline (zero LLM calls) that converts raw retrieved chunks
  # into structured, ability-aware context for the generator prompt.
  #
  # Layer 1: FACT EXTRACTION — annotate chunks with [Speaker] [Turn#] metadata
  # Layer 2: RELEVANCE FILTERING — rank by retrieval score, keep top-K chunks
  # Layer 3: ABILITY-AWARE FORMATTING — sort/group/mark based on question type

  # Max chars per chunk — keep generous to preserve full turn content
  @max_chunk_chars 2_000
  # Max total distilled context chars — matches a reasonable prompt budget
  # Override with GRAPHONOMOUS_DISTILL_MAX_CHARS env var for local models
  @default_distill_chars 64_000

  defp distill_context(results, question, ability) when results != [] do
    # Layer 1: Annotate each chunk with structured metadata, cap per-chunk size
    chunks =
      results
      |> Enum.map(&annotate_chunk/1)
      |> Enum.reject(fn c -> c.text == "" end)
      |> Enum.uniq_by(fn c -> c.node_id end)
      |> Enum.map(fn c -> %{c | text: String.slice(c.text, 0, @max_chunk_chars)} end)

    # Layer 2: Ability-aware filtering
    # For abstention: only include high-similarity chunks so the model can
    # correctly identify when relevant info is missing
    filtered =
      case ability do
        "abstention" ->
          high_sim = Enum.filter(chunks, fn c -> c.similarity >= 0.45 end)
          if high_sim == [], do: [], else: Enum.take(high_sim, 10)

        _ ->
          chunks
      end

    # Layer 3: Ability-aware formatting, then truncate to budget
    max_chars = distill_char_limit()
    formatted = format_for_ability(filtered, ability, question)
    String.slice(formatted, 0, max_chars)
  end

  defp distill_context([], _question, _ability), do: "No relevant context found."

  defp distill_char_limit do
    case System.get_env("GRAPHONOMOUS_DISTILL_MAX_CHARS") do
      nil ->
        @default_distill_chars

      val ->
        case Integer.parse(val) do
          {n, _} -> n
          :error -> @default_distill_chars
        end
    end
  end

  # Annotate a retrieval result with speaker/turn metadata
  defp annotate_chunk(result) do
    content = Map.get(result, :content, "")
    similarity = Map.get(result, :similarity, 0.0)
    score = Map.get(result, :score, similarity)
    node_id = Map.get(result, :node_id)

    # Get node metadata for speaker/turn info
    meta =
      case Graphonomous.get_node(node_id) do
        %{metadata: m} when is_map(m) -> m
        _ -> %{}
      end

    role = Map.get(meta, "role", "unknown")
    turn_idx = Map.get(meta, "turn_index", "?")
    batch = Map.get(meta, "batch_number", "?")
    time_anchor = Map.get(meta, "time_anchor")

    # Strip the "[role] " prefix we added during ingestion
    raw_text =
      case Regex.run(~r/^\[(?:user|assistant|system|unknown)\]\s*/i, content) do
        [prefix] -> String.slice(content, String.length(prefix)..-1//1)
        _ -> content
      end

    # Light cleanup: strip pure filler lines but keep substantive content intact
    cleaned =
      raw_text
      |> String.split(~r/\n+/, trim: true)
      |> Enum.reject(fn line ->
        trimmed = String.trim(line)

        byte_size(trimmed) < 5 or
          Regex.match?(
            ~r/^(?:okay|sure|thanks|thank you|hi|hello|hey|um|uh|well|yeah|yes|no|right|got it|I see|hmm|alright|great)[.!?]?$/i,
            trimmed
          )
      end)
      |> Enum.join(" ")
      |> String.trim()

    %{
      text: cleaned,
      speaker: role,
      turn: turn_idx,
      batch: batch,
      time_anchor: time_anchor,
      similarity: similarity,
      score: score,
      node_id: node_id
    }
  end

  # ── Ability-Aware Formatting ──────────────────────────────────────

  defp format_for_ability(chunks, "event_ordering", _question) do
    # Sort chronologically — present as conversation transcript for ordering
    sorted = sort_chronologically(chunks)

    # Build entity chains: group claims by entity and show temporal progression
    entity_chains = build_entity_chains(sorted)

    header =
      "CONVERSATION TRANSCRIPT (in exact chronological order, earliest first):\n" <>
        "Each entry shows [Turn N] — use turn numbers to determine the order of events.\n\n"

    body =
      sorted
      |> Enum.map(fn c ->
        time_str = if c.time_anchor, do: " [#{c.time_anchor}]", else: ""
        "--- Turn #{c.turn}#{time_str} (#{c.speaker}) ---\n#{c.text}"
      end)
      |> Enum.join("\n\n")

    chain_section =
      if entity_chains != "" do
        "\n\n══ ENTITY TIMELINES (use these to track how each topic/person evolved) ══\n#{entity_chains}"
      else
        ""
      end

    footer =
      "\n\n---\nIMPORTANT: The turns above are in EXACT chronological order (Turn 1 = earliest). " <>
        "When answering about order of events/topics, follow the turn numbers exactly. " <>
        "Lower turn number = happened FIRST. Higher turn number = happened LATER. " <>
        "List items directly without preamble."

    header <> body <> chain_section <> footer
  end

  defp format_for_ability(chunks, "multi_session_reasoning", question) do
    # Group by resolved entity using EntityResolver for alias/fuzzy matching
    mentions = EntityResolver.extract_mentions(question)
    {resolved, _unresolved} = EntityResolver.resolve(mentions)

    # Build entity_id -> entity_name map from resolved mentions
    entity_names = Map.new(resolved, fn r -> {r.entity_id, r.entity_name} end)

    grouped =
      if resolved == [] do
        # Fallback: no resolved entities, use simple proper noun extraction
        entities = extract_question_entities(question)

        if entities == [] do
          %{"Context" => chunks}
        else
          Enum.group_by(chunks, fn c ->
            text_lower = String.downcase(c.text)

            Enum.find(entities, "Other", fn e ->
              String.contains?(text_lower, String.downcase(e))
            end)
          end)
        end
      else
        # Build node_id -> entity_name lookup from entity_node_links
        node_entity_map =
          chunks
          |> Enum.reduce(%{}, fn c, acc ->
            if c.node_id do
              links = Store.entities_for_node(c.node_id)

              case Enum.find(links, fn link -> Map.has_key?(entity_names, link.entity_id) end) do
                %{entity_id: eid} -> Map.put(acc, c.node_id, Map.get(entity_names, eid, "Other"))
                nil -> acc
              end
            else
              acc
            end
          end)

        Enum.group_by(chunks, fn c ->
          Map.get(node_entity_map, c.node_id, "Other")
        end)
      end

    header = "MULTI-HOP REASONING CONTEXT (grouped by entity):\n\n"

    body =
      grouped
      |> Enum.sort_by(fn {name, _} -> if name == "Other", do: "zzz", else: name end)
      |> Enum.map(fn {entity, entity_chunks} ->
        sorted = Enum.sort_by(entity_chunks, fn c -> parse_int(c.turn, 0) end)

        lines =
          sorted
          |> Enum.map(fn c ->
            "  - [#{String.upcase(c.speaker)} Turn #{c.turn}] #{c.text}"
          end)
          |> Enum.join("\n")

        "## #{entity}\n#{lines}"
      end)
      |> Enum.join("\n\n")

    header <> body
  end

  defp format_for_ability(chunks, "contradiction_resolution", _question) do
    # Sort chronologically, then cluster by entity to surface per-entity conflicts
    sorted = sort_chronologically(chunks)

    # Primary: entity-based clustering
    entity_groups = group_chunks_by_entity(sorted)

    # Track which chunks are entity-grouped
    entity_grouped_node_ids =
      entity_groups
      |> Enum.flat_map(fn {_eid, cs} -> Enum.map(cs, & &1.node_id) end)
      |> MapSet.new()

    # Ungrouped chunks fall back to token-overlap clustering
    ungrouped = Enum.reject(sorted, fn c -> MapSet.member?(entity_grouped_node_ids, c.node_id) end)
    fallback_clusters = cluster_by_topic(ungrouped)

    # Look up entity names
    all_entities = Store.list_entities()
    entity_name_map = Map.new(all_entities, fn e -> {e.id, e.name} end)

    header =
      "CONTEXT FOR CONTRADICTION ANALYSIS (grouped by entity, chronological within each group).\n" <>
        "IMPORTANT: Look for statements that CONFLICT with each other. " <>
        "Later turns (higher numbers) OVERRIDE earlier turns. " <>
        "Claims marked ⚠ UPDATE represent the CURRENT truth.\n\n"

    # Entity-grouped claims (primary)
    entity_body =
      entity_groups
      |> Enum.map(fn {eid, cluster_chunks} ->
        name = Map.get(entity_name_map, eid, "Unknown")
        max_turn = cluster_chunks |> Enum.map(fn x -> parse_int(x.turn, 0) end) |> Enum.max()

        lines =
          cluster_chunks
          |> Enum.sort_by(fn c -> parse_int(c.turn, 0) end)
          |> Enum.map(fn c ->
            turn_val = parse_int(c.turn, 0)

            update_marker =
              if turn_val == max_turn and length(cluster_chunks) > 1,
                do: " ⚠ UPDATE",
                else: ""

            "  [Turn #{c.turn}] [#{String.upcase(c.speaker)}]#{update_marker} #{c.text}"
          end)
          |> Enum.join("\n")

        ">>> ENTITY \"#{name}\" — CLAIMS (later turns may override earlier ones):\n#{lines}"
      end)
      |> Enum.join("\n\n")

    # Fallback token-overlap clusters
    fallback_body =
      fallback_clusters
      |> Enum.map(fn {_topic, cluster_chunks} ->
        if length(cluster_chunks) > 1 do
          sorted_cluster = Enum.sort_by(cluster_chunks, fn c -> parse_int(c.turn, 0) end)
          max_turn = sorted_cluster |> Enum.map(fn c -> parse_int(c.turn, 0) end) |> Enum.max()

          lines =
            sorted_cluster
            |> Enum.map(fn c ->
              turn_val = parse_int(c.turn, 0)

              update_marker =
                if turn_val == max_turn,
                  do: " ⚠ UPDATE",
                  else: ""

              "  [Turn #{c.turn}] [#{String.upcase(c.speaker)}]#{update_marker} #{c.text}"
            end)
            |> Enum.join("\n")

          ">>> RELATED CLAIMS (later turns override earlier ones):\n#{lines}"
        else
          c = hd(cluster_chunks)
          "- [Turn #{c.turn}] [#{String.upcase(c.speaker)}] #{c.text}"
        end
      end)
      |> Enum.join("\n\n")

    body =
      [entity_body, fallback_body]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    header <> body
  end

  defp format_for_ability(chunks, "summarization", _question) do
    # Use all available chunks sorted chronologically for comprehensive summary
    sorted = sort_chronologically(chunks)

    header =
      "FULL CONVERSATION CONTEXT (use all of this to build your summary):\n\n"

    body =
      sorted
      |> Enum.map(fn c ->
        "[#{String.upcase(c.speaker)} Turn #{c.turn}] #{c.text}"
      end)
      |> Enum.join("\n\n")

    footer =
      "\n\n---\nThe above is the complete retrieved conversation. " <>
        "Summarize the key topics, decisions, technical details, and outcomes discussed."

    header <> body <> footer
  end

  defp format_for_ability(chunks, "temporal_reasoning", _question) do
    # Sort by time, include temporal markers prominently
    sorted = sort_chronologically(chunks)

    # Build entity chains for temporal progression
    entity_chains = build_entity_chains(sorted)

    header =
      "TEMPORAL CONTEXT (ordered by conversation time, Turn 1 = earliest):\n" <>
        "Use turn numbers to determine WHEN things happened. Lower turn = earlier.\n\n"

    body =
      sorted
      |> Enum.map(fn c ->
        time_str = if c.time_anchor, do: " @#{c.time_anchor}", else: ""
        "- [Turn #{c.turn}#{time_str}] [#{String.upcase(c.speaker)}] #{c.text}"
      end)
      |> Enum.join("\n")

    chain_section =
      if entity_chains != "" do
        "\n\n══ ENTITY TIMELINES (how each topic/person changed over time) ══\n#{entity_chains}"
      else
        ""
      end

    footer =
      "\n\n---\nIMPORTANT: Turn numbers indicate temporal order. " <>
        "Lower turn = happened FIRST. When asked about timing, sequence, or changes over time, " <>
        "use turn numbers as the authoritative timeline."

    header <> body <> chain_section <> footer
  end

  defp format_for_ability(chunks, "knowledge_update", _question) do
    # Sort chronologically, then mark latest values for each entity when conflicts exist
    sorted = sort_chronologically(chunks)

    # Group chunks by entity to detect per-entity updates
    entity_chunks_map = group_chunks_by_entity(sorted)

    # Build a set of node_ids that are "latest" for their entity (highest turn)
    latest_node_ids =
      entity_chunks_map
      |> Enum.flat_map(fn {_eid, ecs} ->
        if length(ecs) > 1 do
          latest = Enum.max_by(ecs, fn c -> parse_int(c.turn, 0) end)
          [latest.node_id]
        else
          []
        end
      end)
      |> MapSet.new()

    header =
      "KNOWLEDGE UPDATE CONTEXT (chronological order — later turns override earlier ones):\n" <>
        "When the same topic/entity has multiple values, the ⚠ UPDATE marker shows the latest.\n\n"

    body =
      sorted
      |> Enum.map(fn c ->
        update_marker =
          if MapSet.member?(latest_node_ids, c.node_id),
            do: " ⚠ UPDATE",
            else: ""

        "[Turn #{c.turn}] [#{String.upcase(c.speaker)}]#{update_marker} #{c.text}"
      end)
      |> Enum.join("\n\n")

    footer =
      "\n\n---\nIMPORTANT: When facts conflict across turns, the LATEST turn (highest number) " <>
        "with ⚠ UPDATE is the current truth. Earlier values are superseded."

    header <> body <> footer
  end

  # Default: structured chunks with speaker attribution, sorted by relevance
  defp format_for_ability(chunks, _ability, _question) do
    header = "RETRIEVED CONTEXT:\n\n"

    body =
      chunks
      |> Enum.map(fn c ->
        "- [#{String.upcase(c.speaker)} Turn #{c.turn}] #{c.text}"
      end)
      |> Enum.join("\n")

    header <> body
  end

  defp sort_chronologically(chunks) do
    Enum.sort_by(chunks, fn c ->
      batch = parse_int(c.batch, 0)
      turn = parse_int(c.turn, 0)
      {batch, turn}
    end)
  end

  # Build per-entity temporal chains from chronologically sorted chunks.
  # Returns a formatted string showing entity timelines, or "" if no entities found.
  defp build_entity_chains(sorted_chunks) do
    # Map each chunk to its linked entities
    entity_groups =
      sorted_chunks
      |> Enum.flat_map(fn c ->
        if c.node_id do
          links = Store.entities_for_node(c.node_id)

          case links do
            [] -> []
            _ -> Enum.map(links, fn link -> {link.entity_id, c} end)
          end
        else
          []
        end
      end)
      |> Enum.group_by(fn {eid, _} -> eid end, fn {_, chunk} -> chunk end)
      |> Enum.reject(fn {_eid, chunks} -> length(chunks) < 2 end)

    if entity_groups == [] do
      ""
    else
      # Look up entity names
      all_entities = Store.list_entities()
      entity_name_map = Map.new(all_entities, fn e -> {e.id, e.name} end)

      entity_groups
      |> Enum.map(fn {eid, chunks} ->
        name = Map.get(entity_name_map, eid, "Unknown")

        chain =
          chunks
          |> Enum.uniq_by(fn c -> c.node_id end)
          |> Enum.sort_by(fn c -> parse_int(c.turn, 0) end)
          |> Enum.map(fn c ->
            "[Turn #{c.turn}] #{name}: #{String.slice(c.text, 0, 400)}"
          end)
          |> Enum.join("\n  → ")

        "▸ #{name} (#{length(chunks)} mentions):\n  #{chain}"
      end)
      |> Enum.join("\n\n")
    end
  end

  # Group chunks by entity_id using Store.entities_for_node.
  # Returns a map of entity_id -> [chunks] (only entities with 2+ chunks).
  defp group_chunks_by_entity(chunks) do
    chunks
    |> Enum.flat_map(fn c ->
      if c.node_id do
        links = Store.entities_for_node(c.node_id)
        Enum.map(links, fn link -> {link.entity_id, c} end)
      else
        []
      end
    end)
    |> Enum.group_by(fn {eid, _} -> eid end, fn {_, chunk} -> chunk end)
    |> Enum.filter(fn {_eid, cs} -> length(cs) >= 2 end)
    |> Map.new()
  end

  # Extract proper nouns / entities from question text
  defp extract_question_entities(question) do
    names =
      Regex.scan(~r/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b/, question)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.reject(fn name ->
        String.downcase(name) in ~w(what when where who how which does did do is are was were
          the and but for not with has have had can could would should may might will shall
          based during after before between)
      end)
      |> Enum.uniq()

    Enum.take(names, 5)
  end

  # Cluster chunks by topic overlap for contradiction detection
  defp cluster_by_topic(chunks) do
    chunks
    |> Enum.reduce(%{}, fn chunk, clusters ->
      chunk_tokens = tokenize_simple(chunk.text)

      # Find existing cluster with >25% token overlap
      match =
        Enum.find(clusters, fn {_key, cluster_chunks} ->
          cluster_tokens =
            cluster_chunks
            |> Enum.flat_map(fn c -> tokenize_simple(c.text) |> MapSet.to_list() end)
            |> MapSet.new()

          overlap = MapSet.intersection(chunk_tokens, cluster_tokens)

          MapSet.size(chunk_tokens) > 0 and
            MapSet.size(overlap) / MapSet.size(chunk_tokens) > 0.25
        end)

      case match do
        {key, _} -> Map.update!(clusters, key, fn existing -> existing ++ [chunk] end)
        nil -> Map.put(clusters, chunk.text, [chunk])
      end
    end)
    |> Enum.to_list()
  end

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  # ── Question Evaluation ──────────────────────────────────────────

  defp evaluate_conversation(convo, diagnose) do
    convo_id = convo.conversation_id
    questions = Map.get(convo, :questions, [])

    Enum.map(questions, fn q ->
      evaluate_question(q, convo_id, diagnose)
    end)
  end

  defp evaluate_question(q, convo_id, diagnose) do
    question_text = Map.get(q, "question", "")
    ability = Map.get(q, "ability", "unknown")
    is_abstention = ability == "abstention"

    # Get the expected answer — BEAM uses different keys per ability
    expected_answer = get_expected_answer(q)

    # Get rubric criteria for scoring
    rubric = Map.get(q, "rubric", []) |> List.wrap()

    # Get source chat IDs for conversation-hit scoring
    source_ids = get_source_chat_ids(q)

    # Adaptive retrieval limits
    {sim_limit, final_limit, exp_hops} =
      case ability do
        "multi_session_reasoning" -> {25, 50, 2}
        "temporal_reasoning" -> {22, 45, 1}
        "event_ordering" -> {22, 45, 1}
        "contradiction_resolution" -> {25, 50, 2}
        "summarization" -> {20, 40, 1}
        _ -> {18, 35, 1}
      end

    # Retrieve from Graphonomous
    {retrieval_us, retrieval} =
      Helpers.timed(fn ->
        Graphonomous.retrieve_context(question_text,
          similarity_limit: sim_limit,
          final_limit: final_limit,
          expansion_hops: exp_hops,
          neighbors_per_node: 8
        )
      end)

    {retrieval, timed_out?} =
      case retrieval do
        {:error, _} -> {%{results: [], stats: %{}}, true}
        map when is_map(map) -> {map, false}
      end

    results = Map.get(retrieval, :results, [])
    retrieval_stats = Map.get(retrieval, :stats, %{})
    retrieved_text = Enum.map(results, &Map.get(&1, :content, "")) |> Enum.join(" ")

    # Context distillation for LLM judge (3-layer pipeline, zero LLM calls)
    distilled_context = distill_context(results, question_text, ability)

    # Check if retrieved nodes come from the correct conversation
    retrieved_convo_ids = extract_conversation_ids(results)
    convo_hit = convo_id in retrieved_convo_ids

    # Check if specific source chat_ids are hit
    source_hit_count = count_source_hits(results, source_ids, convo_id)

    # Rubric-based scoring: check how many rubric criteria are satisfied
    rubric_score = score_rubric(rubric, retrieved_text)

    # Keyword-based scoring
    keyword_recall = keyword_recall(expected_answer, retrieved_text)

    # Nugget proxy: 0/0.5/1 scoring
    # For BEAM, abstention questions test whether the system recognizes that
    # specific details are NOT in the conversation — use rubric scoring when
    # available since the rubric checks for "no information" phrases.
    nugget_proxy =
      cond do
        # Rubric-based scoring (primary for all abilities including abstention)
        rubric != [] ->
          rubric_score

        is_abstention ->
          abstention_score(results, retrieval_stats)

        # Fallback: keyword + conversation hit
        keyword_recall >= 0.6 and convo_hit ->
          1.0

        keyword_recall >= 0.3 or convo_hit ->
          0.5

        true ->
          0.0
      end

    # LLM judge (optional) — use distilled context instead of raw text
    {judge_score, judge_reasoning} =
      if Application.get_env(:graphonomous, :benchmark_judge, false) do
        case Mix.Tasks.Benchmark.LlmJudge.judge_answer(
               question_text,
               distilled_context,
               expected_answer,
               ability: ability
             ) do
          {:ok, %{score: score, reasoning: reasoning}} -> {score, reasoning}
          {:error, _} -> {nil, nil}
        end
      else
        {nil, nil}
      end

    if diagnose and nugget_proxy == 0.0 do
      short = Map.get(@ability_short, ability, ability)

      Mix.shell().info(
        "    MISS [#{short}] #{String.slice(question_text, 0, 80)}... " <>
          "(kw=#{Float.round(keyword_recall, 2)}, rubric=#{Float.round(rubric_score, 2)}, hit=#{convo_hit})"
      )
    end

    %{
      question_id: Map.get(q, "question_id", "#{convo_id}_#{ability}"),
      conversation_id: convo_id,
      ability: ability,
      is_abstention: is_abstention,
      timed_out: timed_out?,
      retrieval_latency_us: retrieval_us,
      result_count: length(results),
      convo_hit: convo_hit,
      source_hit_count: source_hit_count,
      keyword_recall: Float.round(keyword_recall, 4),
      rubric_score: Float.round(rubric_score, 4),
      nugget_proxy: nugget_proxy,
      retrieval_confidence: Map.get(retrieval_stats, :retrieval_confidence),
      max_ann_similarity: Map.get(retrieval_stats, :max_ann_similarity),
      judge_score: judge_score,
      judge_reasoning: judge_reasoning
    }
  end

  # Get expected answer from various BEAM field names
  defp get_expected_answer(q) do
    (Map.get(q, "answer") ||
       Map.get(q, "ideal_response") ||
       Map.get(q, "ideal_answer") ||
       Map.get(q, "ideal_summary") ||
       Map.get(q, "expected_compliance") ||
       "")
    |> to_string()
  end

  # Extract source_chat_ids from various formats
  defp get_source_chat_ids(q) do
    case Map.get(q, "source_chat_ids") do
      ids when is_list(ids) -> ids
      ids when is_map(ids) -> ids |> Map.values() |> List.flatten()
      _ -> []
    end
    |> Enum.map(fn
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_conversation_ids(results) do
    Enum.flat_map(results, fn r ->
      case Graphonomous.get_node(Map.get(r, :node_id)) do
        %{metadata: meta} when is_map(meta) ->
          cid = Map.get(meta, "conversation_id")
          if cid, do: [cid], else: []

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  # Count how many source_chat_ids have nodes in the retrieval results
  defp count_source_hits(results, source_ids, convo_id) when source_ids != [] do
    source_set = MapSet.new(source_ids)

    Enum.count(results, fn r ->
      case Graphonomous.get_node(Map.get(r, :node_id)) do
        %{metadata: meta} when is_map(meta) ->
          Map.get(meta, "conversation_id") == convo_id and
            MapSet.member?(source_set, Map.get(meta, "chat_id"))

        _ ->
          false
      end
    end)
  end

  defp count_source_hits(_, _, _), do: 0

  defp abstention_score(results, retrieval_stats) do
    cond do
      results == [] -> 1.0
      Map.get(retrieval_stats, :abstention_signal, false) -> 1.0
      Map.get(retrieval_stats, :retrieval_confidence, 1.0) < 0.3 -> 1.0
      (Map.get(retrieval_stats, :max_ann_similarity, 1.0) || 1.0) < 0.45 -> 1.0
      length(results) < 3 -> 1.0
      true -> 0.0
    end
  end

  # Score against BEAM rubric: each rubric item is a string that should appear
  # in the retrieved text. Score = fraction of rubric items satisfied.
  defp score_rubric([], _retrieved_text), do: 0.0

  defp score_rubric(rubric, retrieved_text) when is_list(rubric) do
    retrieved_lower = String.downcase(retrieved_text)

    hits =
      Enum.count(rubric, fn criterion ->
        criterion_str = to_string(criterion)
        # Extract the key phrase after "should state:" or "should contain:"
        key_phrase =
          case Regex.run(
                 ~r/should (?:state|contain|mention|include)[:\s]+(.+)/i,
                 criterion_str
               ) do
            [_, phrase] -> String.trim(phrase) |> String.downcase()
            _ -> String.downcase(criterion_str)
          end

        # Check if key phrase or its significant tokens appear in retrieved text
        key_tokens = tokenize_simple(key_phrase)

        if MapSet.size(key_tokens) == 0 do
          false
        else
          retrieved_tokens = tokenize_simple(retrieved_lower)
          overlap = MapSet.intersection(key_tokens, retrieved_tokens)
          MapSet.size(overlap) / MapSet.size(key_tokens) >= 0.5
        end
      end)

    case hits do
      0 -> 0.0
      n when n == length(rubric) -> 1.0
      _ -> 0.5
    end
  end

  defp tokenize_simple(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in stopwords()))
    |> MapSet.new()
  end

  # ── Keyword Metrics ──────────────────────────────────────────────

  defp keyword_recall(answer, retrieved_text)
       when is_binary(answer) and is_binary(retrieved_text) do
    if answer == "" or retrieved_text == "" do
      0.0
    else
      answer_tokens = tokenize_simple(answer)
      retrieved_tokens = tokenize_simple(retrieved_text)

      if MapSet.size(answer_tokens) == 0 do
        0.0
      else
        overlap = MapSet.intersection(answer_tokens, retrieved_tokens)
        MapSet.size(overlap) / MapSet.size(answer_tokens)
      end
    end
  end

  defp keyword_recall(_, _), do: 0.0

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
    overall = %{
      mean_nugget_proxy: mean(question_results, :nugget_proxy),
      nugget_proxy_pct: Float.round(mean(question_results, :nugget_proxy) * 100, 1),
      mean_keyword_recall: mean(question_results, :keyword_recall),
      mean_rubric_score: mean(question_results, :rubric_score),
      convo_hit_rate: pct(question_results, :convo_hit),
      mean_latency_ms: div(round(mean(question_results, :retrieval_latency_us)), 1000),
      total_questions: length(question_results),
      timeout_count: Enum.count(question_results, & &1.timed_out),
      judge_mean: judge_mean(question_results)
    }

    by_ability =
      question_results
      |> Enum.group_by(& &1.ability)
      |> Enum.map(fn {ability, items} ->
        {ability,
         %{
           count: length(items),
           mean_nugget_proxy: mean(items, :nugget_proxy),
           nugget_pct: Float.round(mean(items, :nugget_proxy) * 100, 1),
           convo_hit_rate: pct(items, :convo_hit),
           mean_keyword_recall: mean(items, :keyword_recall),
           mean_rubric_score: mean(items, :rubric_score),
           judge_mean: judge_mean(items)
         }}
      end)
      |> Map.new()

    %{overall: overall, by_ability: by_ability}
  end

  defp mean(items, field) when items != [] do
    vals = Enum.map(items, fn item -> Map.get(item, field, 0) || 0 end)
    Enum.sum(vals) / length(vals)
  end

  defp mean([], _), do: 0.0

  defp pct(items, field) when items != [] do
    hits = Enum.count(items, fn item -> Map.get(item, field) == true end)
    Float.round(hits / length(items) * 100, 1)
  end

  defp pct([], _), do: 0.0

  defp judge_mean(items) do
    scored = Enum.filter(items, fn i -> i.judge_score != nil end)
    if scored == [], do: nil, else: Float.round(mean(scored, :judge_score) * 100, 1)
  end

  # ── Results Printing ──────────────────────────────────────────────

  defp print_results(metrics, tier, total_convos, total_questions, path) do
    overall = metrics.overall
    by_ability = metrics.by_ability
    baselines = Map.get(@competitive_baselines, tier, %{})

    tier_label = String.upcase(tier)

    judge_line =
      if overall.judge_mean,
        do: "║  E2E Judge:     #{String.pad_trailing("#{overall.judge_mean}%", 40)}║\n",
        else: ""

    Mix.shell().info("""

    ╔══════════════════════════════════════════════════════════╗
    ║              BEAM BENCHMARK RESULTS (#{String.pad_trailing(tier_label, 5)})              ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Conversations: #{String.pad_trailing("#{total_convos}", 40)}║
    ║  Questions:     #{String.pad_trailing("#{total_questions}", 40)}║
    ║  Retrieval:     #{String.pad_trailing("#{overall.nugget_proxy_pct}% (nugget proxy)", 40)}║
    #{judge_line}║  Convo Hit:     #{String.pad_trailing("#{overall.convo_hit_rate}%", 40)}║
    ║  Latency:       #{String.pad_trailing("#{overall.mean_latency_ms} ms/query", 40)}║
    ╚══════════════════════════════════════════════════════════╝
    """)

    has_judge = overall.judge_mean != nil

    if has_judge do
      Mix.shell().info("  Per-Ability Breakdown (Retrieval / E2E Judge):")
      Mix.shell().info("  ─────────────────────────────────────────────────────────")
    else
      Mix.shell().info("  Per-Ability Breakdown (Retrieval Recall):")
      Mix.shell().info("  ─────────────────────────────────────────────────")
    end

    ability_order =
      ~w(information_extraction multi_session_reasoning knowledge_update
         temporal_reasoning abstention contradiction_resolution event_ordering
         instruction_following preference_following summarization)

    Enum.each(ability_order, fn ability ->
      case Map.get(by_ability, ability) do
        nil ->
          :ok

        data ->
          label = Map.get(@ability_labels, ability, ability)
          short = Map.get(@ability_short, ability, "??")

          judge_col =
            if has_judge and data.judge_mean,
              do: " │ E2E #{data.judge_mean}%",
              else: ""

          Mix.shell().info(
            "  [#{short}] #{String.pad_trailing(label, 25)} #{String.pad_trailing("#{data.nugget_pct}%", 8)}#{judge_col} (n=#{data.count})"
          )
      end
    end)

    # Use judge score for competitive comparison when available (apples-to-apples)
    # Baselines like Hindsight use end-to-end LLM judge scoring
    graphonomous_score =
      if overall.judge_mean,
        do: overall.judge_mean,
        else: overall.nugget_proxy_pct

    score_type = if overall.judge_mean, do: "E2E Judge", else: "Retrieval Proxy"
    version = Mix.Project.config()[:version]

    Mix.shell().info("\n  Competitive Comparison (#{tier_label} tier, #{score_type}):")

    Mix.shell().info("  ─────────────────────────────────────────────────")

    sorted =
      [{"Graphonomous v#{version}", graphonomous_score} | Enum.to_list(baselines)]
      |> Enum.sort_by(fn {_, v} -> v end, :desc)

    Enum.each(sorted, fn {name, score} ->
      marker = if String.starts_with?(name, "Graphonomous"), do: " <<<", else: ""

      Mix.shell().info(
        "  #{String.pad_trailing(name, 28)} #{String.pad_trailing("#{score}%", 8)}#{marker}"
      )
    end)

    if overall.judge_mean do
      Mix.shell().info(
        "\n  Note: Graphonomous scores above use end-to-end LLM judge (generate + judge)."
      )

      Mix.shell().info("  Retrieval recall (nugget proxy): #{overall.nugget_proxy_pct}%")
    end

    Mix.shell().info("\n  Results: #{path}")
  end
end
