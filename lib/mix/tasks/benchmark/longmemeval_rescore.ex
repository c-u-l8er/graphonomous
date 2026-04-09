defmodule Mix.Tasks.Benchmark.LongmemevalRescore do
  @moduledoc """
  Re-scores an existing LongMemEval results JSON with LLM judge evaluation.

  This avoids the expensive ingest phase entirely by reconstructing context
  from the dataset using the `retrieved_session_ids` in the prior results.

  ## Usage

      GRAPHONOMOUS_JUDGE_BACKEND=openrouter \\
        OPENROUTER_API_KEY=sk-... \\
        OPENROUTER_MODEL=google/gemma-3-27b-it \\
        mix benchmark.longmemeval_rescore --input longmemeval_20260405_234227_ppr0.18_L500.json

  ## Options

    * `--input` — filename in benchmark_results/ to rescore (required)
    * `--limit` — max questions to rescore (default: all)
    * `--concurrency` — parallel judge calls (default: 4)
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers
  alias Mix.Tasks.Benchmark.LlmJudge

  @shortdoc "Re-score LongMemEval results with LLM judge (no ingest needed)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          input: :string,
          limit: :integer,
          concurrency: :integer
        ]
      )

    input_file = Keyword.get(opts, :input)
    limit = Keyword.get(opts, :limit, 99_999)
    concurrency = Keyword.get(opts, :concurrency, 4)

    unless input_file do
      Mix.shell().error("--input is required. Pass the results filename from benchmark_results/")
      exit({:shutdown, 1})
    end

    Application.put_env(:graphonomous, :benchmark_judge, true)

    unless LlmJudge.available?() do
      Mix.shell().error("""
      LLM judge not available. Set one of:
        OPENROUTER_API_KEY (with GRAPHONOMOUS_JUDGE_BACKEND=openrouter)
        ANTHROPIC_API_KEY
        GRAPHONOMOUS_JUDGE_BACKEND=lmstudio
      """)

      exit({:shutdown, 1})
    end

    # Load prior results
    results_dir =
      Path.join([Helpers.portfolio_root(), "graphonomous", "benchmark_results"])

    input_path = Path.join(results_dir, input_file)

    unless File.exists?(input_path) do
      Mix.shell().error("Results file not found: #{input_path}")
      exit({:shutdown, 1})
    end

    prior = input_path |> File.read!() |> Jason.decode!()
    questions_results = Map.get(prior, "questions", [])

    Mix.shell().info("Loaded #{length(questions_results)} question results from #{input_file}")

    # Load dataset to get actual session text
    dataset = load_dataset(Map.get(prior, "dataset_split", "oracle"))

    unless dataset do
      Mix.shell().error("Cannot load LongMemEval dataset")
      exit({:shutdown, 1})
    end

    # Build session text index: session_id -> list of turns
    session_index = build_session_index(dataset)
    Mix.shell().info("Built session index: #{map_size(session_index)} sessions")

    # Build question index: question_id -> dataset question
    question_index =
      dataset
      |> Enum.map(fn q -> {Map.get(q, "question_id"), q} end)
      |> Map.new()

    Mix.shell().info("Built question index: #{map_size(question_index)} questions")

    # Filter to questions that need judging
    to_rescore =
      questions_results
      |> Enum.filter(fn q -> q["judge_score"] == nil end)
      |> Enum.take(limit)

    already_scored = length(questions_results) - length(to_rescore)

    Mix.shell().info(
      "Rescoring #{length(to_rescore)} questions (#{already_scored} already have judge scores)"
    )

    # Streaming output
    streaming_path = Path.join(results_dir, "longmemeval_rescore_streaming.jsonl")
    File.write!(streaming_path, "")

    # Rescore with concurrency
    scored_map =
      to_rescore
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {q_result, idx} ->
          if rem(idx, 10) == 0 or idx == 1 do
            Mix.shell().info("  Progress: #{idx}/#{length(to_rescore)}...")
          end

          question_id = q_result["question_id"]
          dataset_q = Map.get(question_index, question_id)

          if dataset_q == nil do
            Mix.shell().info("  ⚠ #{question_id}: not found in dataset, skipping")
            {question_id, nil, nil, nil}
          else
            question_text = Map.get(dataset_q, "question", "")
            expected_answer = Map.get(dataset_q, "answer", "") |> to_string()
            ability = parse_ability(q_result["ability"])
            is_abstention = q_result["is_abstention"] == true

            # Reconstruct context from retrieved session IDs
            retrieved_ids = parse_session_ids(q_result["retrieved_session_ids"])
            context = build_context_from_sessions(retrieved_ids, session_index, ability)

            judge_ability = if is_abstention, do: "abstention", else: ability_to_string(ability)

            case LlmJudge.judge_answer(question_text, context, expected_answer,
                   ability: judge_ability
                 ) do
              {:ok, %{answer: ans, score: score, reasoning: reasoning}} ->
                # Stream result
                line =
                  Jason.encode!(%{
                    idx: idx,
                    question_id: question_id,
                    ability: q_result["ability"],
                    session_hit: q_result["session_hit"],
                    qa_proxy_score: q_result["qa_proxy_score"],
                    judge_score: score,
                    judge_answer: ans
                  })

                File.write!(streaming_path, line <> "\n", [:append])
                {question_id, score, ans, reasoning}

              {:error, reason} ->
                Mix.shell().info("  ⚠ #{question_id}: judge error #{inspect(reason)}")
                {question_id, nil, nil, nil}
            end
          end
        end,
        max_concurrency: concurrency,
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{}, fn
        {:ok, {qid, score, answer, reasoning}}, acc when score != nil ->
          Map.put(acc, qid, %{score: score, answer: answer, reasoning: reasoning})

        _, acc ->
          acc
      end)

    Mix.shell().info("\nJudged #{map_size(scored_map)} questions successfully")

    # Merge judge scores into prior results
    updated_questions =
      questions_results
      |> Enum.map(fn q ->
        qid = q["question_id"]

        case Map.get(scored_map, qid) do
          %{score: score, answer: answer, reasoning: reasoning} ->
            q
            |> Map.put("judge_score", score)
            |> Map.put("judge_answer", answer)
            |> Map.put("judge_reasoning", reasoning)

          _ ->
            q
        end
      end)

    # Recompute metrics with judge scores
    judged = Enum.filter(updated_questions, fn q -> q["judge_score"] != nil end)

    judge_accuracy =
      if judged == [] do
        nil
      else
        mean = Enum.sum(Enum.map(judged, & &1["judge_score"])) / length(judged)
        Float.round(mean * 100, 1)
      end

    # Per-ability judge scores
    by_ability =
      updated_questions
      |> Enum.group_by(& &1["ability"])
      |> Enum.map(fn {ability, qs} ->
        scored = Enum.filter(qs, fn q -> q["judge_score"] != nil end)

        judge_acc =
          if scored == [] do
            nil
          else
            mean = Enum.sum(Enum.map(scored, & &1["judge_score"])) / length(scored)
            Float.round(mean * 100, 1)
          end

        {ability, %{count: length(qs), judged: length(scored), judge_qa_accuracy: judge_acc}}
      end)
      |> Map.new()

    Mix.shell().info("\n━━━ LongMemEval Rescore Results ━━━")
    Mix.shell().info("  Overall Judge QA Accuracy: #{judge_accuracy}%")
    Mix.shell().info("  Questions judged: #{length(judged)}/#{length(updated_questions)}")
    Mix.shell().info("")

    for {ability, stats} <- Enum.sort(by_ability) do
      Mix.shell().info(
        "  #{String.pad_trailing(to_string(ability), 28)} " <>
          "n=#{stats.count} judged=#{stats.judged} judge=#{stats.judge_qa_accuracy}%"
      )
    end

    # Update metrics in prior results
    updated_metrics =
      prior
      |> get_in(["metrics"])
      |> put_in(["overall", "judge_qa_accuracy"], judge_accuracy)

    updated_metrics =
      Enum.reduce(by_ability, updated_metrics, fn {ability, stats}, acc ->
        ability_str = to_string(ability)

        case get_in(acc, ["by_ability", ability_str]) do
          nil ->
            acc

          existing ->
            put_in(
              acc,
              ["by_ability", ability_str],
              Map.merge(existing, %{"judge_qa_accuracy" => stats.judge_qa_accuracy})
            )
        end
      end)

    # Write updated results
    updated_results =
      prior
      |> Map.put("questions", updated_questions)
      |> Map.put("metrics", updated_metrics)
      |> Map.put("rescore_timestamp", DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put("judge_backend", System.get_env("GRAPHONOMOUS_JUDGE_BACKEND", "claude"))
      |> Map.put("judge_model", System.get_env("OPENROUTER_MODEL", "unknown"))

    ts = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
    result_name = "longmemeval_rescore_#{ts}_L#{length(updated_questions)}"
    path = Helpers.write_results(result_name, updated_results)
    _ = Helpers.write_results("longmemeval", updated_results)

    Mix.shell().info("\n  Results written to: #{path}")
    Mix.shell().info("  Streaming log: #{streaming_path}")
  end

  # ── Helpers ──────────────────────────────────────────────────────

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

  defp build_session_index(dataset) do
    dataset
    |> Enum.flat_map(fn q ->
      session_ids = Map.get(q, "haystack_session_ids", [])
      sessions = Map.get(q, "haystack_sessions", [])
      dates = Map.get(q, "haystack_dates", [])
      padded_dates = dates ++ List.duplicate(nil, max(length(session_ids) - length(dates), 0))

      Enum.zip([session_ids, sessions, padded_dates])
      |> Enum.map(fn {sid, turns, date} -> {sid, turns, date} end)
    end)
    |> Enum.uniq_by(fn {sid, _, _} -> sid end)
    |> Enum.reduce(%{}, fn {sid, turns, date}, acc ->
      Map.put(acc, sid, %{turns: turns, date: date})
    end)
  end

  defp parse_session_ids(ids) when is_list(ids), do: ids

  defp parse_session_ids(ids) when is_binary(ids) do
    # Handle stringified list: "['sid1', 'sid2']"
    ids
    |> String.replace(~r/[\[\]']/, "")
    |> String.split(", ")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_session_ids(_), do: []

  defp build_context_from_sessions(session_ids, session_index, ability) do
    # Take top sessions (same as retrieval would return)
    chunks =
      session_ids
      |> Enum.take(20)
      |> Enum.flat_map(fn sid ->
        case Map.get(session_index, sid) do
          %{turns: turns, date: date} when is_list(turns) ->
            turns
            |> Enum.with_index()
            |> Enum.map(fn {turn, idx} ->
              role = Map.get(turn, "role", "unknown")
              content = Map.get(turn, "content", "")

              %{
                text: String.slice(content, 0, 2000),
                speaker: role,
                turn: idx,
                session_id: sid,
                document_date: date
              }
            end)

          _ ->
            []
        end
      end)

    format_context(chunks, ability)
  end

  defp format_context([], _), do: "No relevant context found."

  defp format_context(chunks, :temporal_reasoning) do
    sorted =
      Enum.sort_by(chunks, fn c ->
        {c.document_date || "", c.turn}
      end)

    header = "TEMPORAL CONTEXT (strict chronological order):\n\n"

    body =
      sorted
      |> Enum.map(fn c ->
        date_str = if c.document_date, do: " [#{c.document_date}]", else: ""
        "[#{String.upcase(c.speaker)} Turn #{c.turn}#{date_str}] #{c.text}"
      end)
      |> Enum.join("\n\n")

    header <> body
  end

  defp format_context(chunks, :multi_session_reasoning) do
    grouped = Enum.group_by(chunks, & &1.session_id)
    header = "MULTI-SESSION CONTEXT (grouped by session):\n\n"

    body =
      grouped
      |> Enum.sort_by(fn {sid, _} -> sid end)
      |> Enum.map(fn {session_id, session_chunks} ->
        sorted = Enum.sort_by(session_chunks, fn c -> c.turn end)

        lines =
          sorted
          |> Enum.map(fn c ->
            "  [#{String.upcase(c.speaker)} Turn #{c.turn}] #{c.text}"
          end)
          |> Enum.join("\n")

        "## Session #{session_id}\n#{lines}"
      end)
      |> Enum.join("\n\n")

    header <> body
  end

  defp format_context(chunks, :knowledge_update) do
    sorted =
      Enum.sort_by(chunks, fn c ->
        {c.document_date || "", c.turn}
      end)

    header = "KNOWLEDGE UPDATE CONTEXT (chronological — latest statement wins):\n\n"

    body =
      sorted
      |> Enum.map(fn c ->
        date_str = if c.document_date, do: " (#{c.document_date})", else: ""
        "[#{String.upcase(c.speaker)} Turn #{c.turn}#{date_str}] #{c.text}"
      end)
      |> Enum.join("\n\n")

    header <> body
  end

  defp format_context(chunks, :abstention) do
    # For abstention, provide minimal context
    if chunks == [] do
      "No relevant context found."
    else
      chunks
      |> Enum.take(10)
      |> Enum.map(fn c ->
        "[#{String.upcase(c.speaker)} Turn #{c.turn}] #{c.text}"
      end)
      |> Enum.join("\n\n")
    end
  end

  defp format_context(chunks, _ability) do
    sorted =
      Enum.sort_by(chunks, fn c ->
        {c.document_date || "", c.turn}
      end)

    sorted
    |> Enum.map(fn c ->
      "[#{String.upcase(c.speaker)} Turn #{c.turn}] #{c.text}"
    end)
    |> Enum.join("\n\n")
  end

  defp parse_ability(ability_str) when is_binary(ability_str) do
    case ability_str do
      "temporal_reasoning" -> :temporal_reasoning
      "multi_session_reasoning" -> :multi_session_reasoning
      "information_extraction" -> :information_extraction
      "knowledge_update" -> :knowledge_update
      "abstention" -> :abstention
      _ -> :unknown
    end
  end

  defp parse_ability(ability) when is_atom(ability), do: ability
  defp parse_ability(_), do: :unknown

  defp ability_to_string(:temporal_reasoning), do: "temporal_reasoning"
  defp ability_to_string(:multi_session_reasoning), do: "multi_session_reasoning"
  defp ability_to_string(:information_extraction), do: "information_extraction"
  defp ability_to_string(:knowledge_update), do: "knowledge_update"
  defp ability_to_string(:abstention), do: "abstention"
  defp ability_to_string(_), do: nil
end
