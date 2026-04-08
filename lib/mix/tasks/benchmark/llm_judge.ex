defmodule Mix.Tasks.Benchmark.LlmJudge do
  @moduledoc """
  LLM-based answer generation and judging for BEAM benchmark.

  Supports split generator/judge: generate answers with one backend, judge with another.

  ## Environment variables

  Generator (answer generation):
    * `GRAPHONOMOUS_JUDGE_BACKEND` — `lmstudio` | `openrouter` | `claude` (default)
    * `LMSTUDIO_MODEL` — model for LMStudio (default `gemma-4-e4b-it`)
    * `OPENROUTER_MODEL` — model for OpenRouter (default `google/gemma-4-12b-a4b-it:free`)

  Judge (answer scoring) — defaults to same as generator:
    * `GRAPHONOMOUS_JUDGE_SCORER` — `lmstudio` | `openrouter` | `claude` | unset (same as generator)
    * `OPENROUTER_JUDGE_MODEL` — separate model for judging via OpenRouter
    * `LMSTUDIO_JUDGE_MODEL` — separate model for judging via LMStudio

  Example: generate locally, judge in cloud:
    GRAPHONOMOUS_JUDGE_BACKEND=lmstudio LMSTUDIO_MODEL=gemma-4-e4b-it \\
    GRAPHONOMOUS_JUDGE_SCORER=openrouter OPENROUTER_API_KEY=sk-... \\
    OPENROUTER_JUDGE_MODEL=google/gemma-4-26b-a4b-it \\
    mix benchmark.beam --tier 100k --limit 1 --judge --purge
  """

  require Logger

  @api_url ~c"https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @lmstudio_url_default "http://localhost:1234/v1/chat/completions"
  @lmstudio_model_default "gemma-4-e4b-it"
  @openrouter_url_default "https://openrouter.ai/api/v1/chat/completions"
  @openrouter_model_default "google/gemma-4-12b-a4b-it:free"
  @max_tokens 8192
  @judge_max_tokens 4096
  # Default context chars passed to generator (~32K tokens for cloud models, ~8K for local)
  # Override with GRAPHONOMOUS_JUDGE_CONTEXT_CHARS env var
  @default_context_chars 128_000

  @doc "Check if judge mode is available"
  def available? do
    generator_backend() == :lmstudio or
      generator_backend() == :openrouter or
      judge_backend() == :openrouter or
      System.get_env("ANTHROPIC_API_KEY") != nil
  end

  defp generator_backend do
    case System.get_env("GRAPHONOMOUS_JUDGE_BACKEND") do
      "lmstudio" -> :lmstudio
      "openrouter" -> :openrouter
      _ -> :claude
    end
  end

  defp judge_backend do
    case System.get_env("GRAPHONOMOUS_JUDGE_SCORER") do
      "lmstudio" -> :lmstudio
      "openrouter" -> :openrouter
      "claude" -> :claude
      nil -> generator_backend()
      _ -> generator_backend()
    end
  end

  @doc """
  Generate an answer from retrieved context and judge it.

  Returns {:ok, %{answer: String.t(), score: 0.0 | 0.5 | 1.0, reasoning: String.t()}}
  or {:error, reason}.

  Options:
    * `:ability` - BEAM ability type for ability-aware prompt tuning
  """
  def judge_answer(question, retrieved_context, expected_answer, opts \\ []) do
    ability = Keyword.get(opts, :ability)

    with {:ok, generated} <- generate_answer(question, retrieved_context, ability),
         {:ok, score, reasoning} <- score_answer(question, generated, expected_answer) do
      {:ok, %{answer: generated, score: score, reasoning: reasoning}}
    else
      {:error, reason} ->
        Logger.warning("LLM judge failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_answer(question, context, ability) do
    max_chars = context_char_limit()
    trimmed_context = String.slice(context, 0, max_chars)

    ability_instruction = ability_specific_instruction(ability)

    prompt = """
    You are answering a question based ONLY on the structured evidence below.

    CONTEXT SCHEMA — the evidence may contain these sections (check them in this order):
    - FACT TABLE: Structured entity-attribute-value rows with session, turn, date, and CURRENT/OUTDATED status. This is the fastest way to find specific facts. Always check this FIRST.
    - USER CLAIMS / USER STATEMENTS: Pre-extracted first-person facts from the user. Claims marked [UPDATE] mean the user changed or corrected earlier info. Claims tagged [S<id>] and [date] show which session and when.
    - ENTITY CROSS-REFERENCE: Shows which named entities appear across multiple sessions — use this to connect information across sessions.
    - TIMELINE: Chronological list of dated events — use for temporal/duration questions.
    - EVIDENCE / SUPPORTING EVIDENCE: Raw conversation turns attributed as [SPEAKER Turn N (date)]. Higher turn numbers = later in conversation. Later dates = more recent information.

    HOW TO READ ATTRIBUTIONS:
    - [USER Turn 5 (2023-03-01)] = the user said this in turn 5, on March 1st 2023
    - [ASSISTANT Turn 6] = the assistant's response in turn 6
    - When information conflicts, the LATEST date/turn wins
    #{ability_instruction}
    RULES:
    1. Base your answer ONLY on the evidence provided. Do not add outside knowledge.
    2. Check USER CLAIMS / USER STATEMENTS first — the answer is usually there.
    3. NEVER refuse to answer. The evidence almost certainly contains the answer. Only say "I don't have enough information" if the context is completely empty or about a 100% unrelated topic. Even partial or indirect evidence must produce an answer — guess from the evidence rather than refusing.
    4. Be precise with names, dates, numbers, and technical terms — copy them exactly from the evidence.
    5. When counting or listing items, FIRST enumerate every matching item you find (write them out), THEN state the total count.

    Evidence:
    #{trimmed_context}

    Question: #{question}

    Answer directly and concisely:
    """

    call_generator(prompt, @max_tokens)
  end

  # Ability-specific prompt instructions (zero LLM cost, just text)
  @doc false
  def ability_specific_instruction("event_ordering") do
    """

    TASK TYPE: Event Ordering
    - List events/topics in the EXACT order they appear by turn number.
    - Output ONLY the ordered list — no preamble, no explanation, no summary.
    - If asked for N items, list exactly N items.
    """
  end

  @doc false
  def ability_specific_instruction("contradiction_resolution") do
    """

    TASK TYPE: Contradiction Resolution
    - The question is asking you to FIND CONTRADICTIONS in the conversation.
    - Do NOT simply answer "yes" or "no" — instead, identify the SPECIFIC conflicting claims.
    - Quote BOTH the original statement AND the contradicting statement.
    - State which came later (higher turn number = more recent).
    - If someone said X in one turn and Y in another turn where X and Y conflict, point out BOTH.
    """
  end

  @doc false
  def ability_specific_instruction("summarization") do
    """

    TASK TYPE: Summarization
    - Provide a comprehensive summary covering: key topics, decisions made, technical details, challenges, and outcomes.
    - Include specific details (names, technologies, dates, numbers) from the evidence.
    - Do NOT say you lack information — summarize what IS in the evidence.
    """
  end

  @doc false
  def ability_specific_instruction("temporal_reasoning") do
    """

    TASK TYPE: Temporal Reasoning
    You MUST follow this step-by-step process:
    Step 1: Extract EVERY date, event, and time reference from the evidence. Write each one out.
    Step 2: Arrange them in chronological order.
    Step 3: For duration questions — subtract the dates and show the arithmetic (e.g., "March 15 to April 14 = 30 days").
    Step 4: For "first/last/most recent" questions — compare the dates and pick the correct one.
    Step 5: State your final answer.
    - Higher turn numbers and later dates = more recent.
    - ALWAYS answer with a specific date, number, or event — never refuse.
    """
  end

  @doc false
  def ability_specific_instruction("multi_session_reasoning") do
    """

    TASK TYPE: Multi-hop Reasoning
    You MUST follow this process:
    Step 1: Scan ALL sessions and turns for relevant items. Write each one out with its source.
    Step 2: Combine and deduplicate items from different sessions.
    Step 3: If counting — enumerate the complete list, then state the total.
    Step 4: If comparing — lay out each piece of evidence side by side.
    Step 5: State your final answer using exact names/terms from the evidence.
    - NEVER refuse. The answer IS in the evidence — look harder across ALL sessions.
    - Information may be spread across 2-5 different sessions. Check the ENTITY CROSS-REFERENCE section to find connections.
    - Partial evidence → partial answer, NEVER "I don't have enough information."
    """
  end

  @doc false
  def ability_specific_instruction("abstention") do
    """

    TASK TYPE: Abstention Check
    - CRITICAL: Only answer if the SPECIFIC detail asked about is EXPLICITLY stated in the evidence.
    - If you cannot find the exact information in the evidence, you MUST say "This information is not available in the provided context."
    - Do NOT infer, guess, or synthesize an answer from loosely related information.
    - Do NOT hallucinate details — if it's not in the evidence word-for-word, it's not there.
    """
  end

  # LongMemEval-specific abilities
  @doc false
  def ability_specific_instruction("information_extraction") do
    """

    TASK TYPE: Information Extraction
    - The USER STATEMENTS section lists extracted facts — check it FIRST for the answer.
    - Extract the SPECIFIC detail the question asks about from the evidence.
    - Look for exact names, preferences, dates, locations, and factual details.
    - If the user stated a preference (e.g., favorite food, preferred tool), quote it precisely.
    - Pay attention to WHO said what — distinguish user statements from assistant statements.
    - The answer is almost always in a USER turn, not an ASSISTANT turn.
    """
  end

  @doc false
  def ability_specific_instruction("knowledge_update") do
    """

    TASK TYPE: Knowledge Update
    The user's facts CHANGE over time. You must find the LATEST version.
    Step 1: Find ALL mentions of the topic across all turns and sessions. Note the turn number and date for each.
    Step 2: If there are multiple values (e.g., "2 cats" in Turn 3, then "3 cats" in Turn 8), the HIGHEST turn number wins.
    Step 3: Look for update markers: "actually", "changed my mind", "not anymore", "now I prefer", "I just got", "I bought". Claims marked [UPDATE] or tagged ⚠ OUTDATED indicate superseded info — IGNORE those values.
    Step 4: State the MOST RECENT value as your answer.
    - The USER CLAIMS section lists extracted facts — check it FIRST.
    - NEVER answer with an outdated value. ALWAYS use the latest turn/date.
    - NEVER refuse — the answer is in the evidence.
    """
  end

  @doc false
  def ability_specific_instruction(_), do: ""

  defp context_char_limit do
    case System.get_env("GRAPHONOMOUS_JUDGE_CONTEXT_CHARS") do
      nil ->
        @default_context_chars

      val ->
        case Integer.parse(val) do
          {n, _} -> n
          :error -> @default_context_chars
        end
    end
  end

  defp score_answer(question, generated_answer, expected_answer) do
    prompt = """
    Judge whether the generated answer correctly answers the question compared to the expected answer.

    Question: #{question}
    Expected Answer: #{expected_answer}
    Generated Answer: #{generated_answer}

    Score as exactly one of:
    - 1.0 if the generated answer is correct and contains the key information
    - 0.5 if partially correct (some key info present but incomplete or slightly wrong)
    - 0.0 if incorrect or missing key information

    You MUST respond with ONLY this JSON format, nothing else:
    {"score": 1.0, "reasoning": "brief explanation"}

    The score MUST be exactly 1.0, 0.5, or 0.0. Do not include any text before or after the JSON.
    """

    case call_judge(prompt, @judge_max_tokens) do
      {:ok, response} ->
        parse_judge_response(response)

      error ->
        error
    end
  end

  defp parse_judge_response(response) do
    # Strip markdown code fences if present
    cleaned =
      response
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    # Try JSON decode first (most reliable)
    with {:ok, parsed} when is_map(parsed) <- try_json_decode(cleaned),
         {score, _} <- parse_score_field(parsed) do
      reasoning = Map.get(parsed, "reasoning", "no reasoning provided") |> to_string()
      {:ok, clamp_score(score), reasoning}
    else
      _ ->
        # Fallback: extract score with regex (handles malformed JSON)
        case Regex.run(~r/"score"\s*:\s*([\d.]+)/, cleaned) do
          [_, score_str] ->
            {score, _} = Float.parse(score_str)

            reasoning =
              case Regex.run(~r/"reasoning"\s*:\s*"((?:[^"\\]|\\.)*)"/, cleaned) do
                [_, r] -> r
                _ -> "parsed score from malformed JSON"
              end

            {:ok, clamp_score(score), reasoning}

          _ ->
            # Last resort: look for bare score values
            case Regex.run(~r/\b(1\.0|0\.5|0\.0)\b/, cleaned) do
              [_, s] ->
                {score, _} = Float.parse(s)
                {:ok, clamp_score(score), "parsed bare score from response"}

              _ ->
                {:ok, 0.0, "could not parse judge response"}
            end
        end
    end
  end

  defp try_json_decode(text) do
    case Regex.run(~r/(\{[\s\S]*\})/U, text) do
      [_, json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} ->
            {:ok, parsed}

          _ ->
            case Regex.run(~r/(\{[\s\S]*\})/, text) do
              [_, json_str2] -> Jason.decode(json_str2)
              _ -> :error
            end
        end

      _ ->
        :error
    end
  end

  defp parse_score_field(%{"score" => score}) when is_number(score), do: {score, ""}

  defp parse_score_field(%{"score" => score}) when is_binary(score) do
    case Float.parse(score) do
      {s, _} -> {s, ""}
      :error -> :error
    end
  end

  defp parse_score_field(_), do: :error

  defp clamp_score(s) when s >= 0.75, do: 1.0
  defp clamp_score(s) when s >= 0.25, do: 0.5
  defp clamp_score(_), do: 0.0

  # --- Generator calls (answer generation) ---

  defp call_generator(prompt, max_tokens) do
    call_with_retry(generator_backend(), generator_model(), prompt, max_tokens)
  end

  # --- Judge calls (answer scoring) ---

  defp call_judge(prompt, max_tokens) do
    call_with_retry(judge_backend(), judge_model(), prompt, max_tokens)
  end

  defp generator_model do
    case generator_backend() do
      :lmstudio -> System.get_env("LMSTUDIO_MODEL", @lmstudio_model_default)
      :openrouter -> System.get_env("OPENROUTER_MODEL", @openrouter_model_default)
      :claude -> @model
    end
  end

  defp judge_model do
    case judge_backend() do
      :lmstudio ->
        System.get_env(
          "LMSTUDIO_JUDGE_MODEL",
          System.get_env("LMSTUDIO_MODEL", @lmstudio_model_default)
        )

      :openrouter ->
        System.get_env(
          "OPENROUTER_JUDGE_MODEL",
          System.get_env("OPENROUTER_MODEL", @openrouter_model_default)
        )

      :claude ->
        @model
    end
  end

  # --- Unified call with retry ---

  defp call_with_retry(backend, model, prompt, max_tokens, retries \\ 3, delay_ms \\ 5_000) do
    result =
      case backend do
        :lmstudio -> call_lmstudio(prompt, max_tokens, model)
        :openrouter -> call_openrouter(prompt, max_tokens, model)
        :claude -> call_claude(prompt, max_tokens)
      end

    case result do
      {:error, {:api_error, 429, _}} when retries > 0 ->
        Logger.debug("Rate limited, retrying in #{delay_ms}ms (#{retries} retries left)")
        Process.sleep(delay_ms)
        call_with_retry(backend, model, prompt, max_tokens, retries - 1, delay_ms * 2)

      {:error, {:api_error, 529, _}} when retries > 0 ->
        Logger.debug("Service overloaded, retrying in #{delay_ms}ms (#{retries} retries left)")
        Process.sleep(delay_ms)
        call_with_retry(backend, model, prompt, max_tokens, retries - 1, delay_ms * 2)

      other ->
        other
    end
  end

  defp call_lmstudio(prompt, max_tokens, model) do
    url =
      System.get_env("LMSTUDIO_URL", @lmstudio_url_default)
      |> String.to_charlist()

    :inets.start()
    :ssl.start()

    # Use /no_think in both system and user message to suppress thinking in Qwen 3.5
    body =
      Jason.encode!(%{
        model: model,
        max_tokens: max_tokens,
        temperature: 0.0,
        messages: [
          %{role: "system", content: "/no_think"},
          %{role: "user", content: prompt <> "\n/no_think"}
        ]
      })

    headers = [{~c"content-type", ~c"application/json"}]
    request = {url, headers, ~c"application/json", body}

    case :httpc.request(:post, request, [{:timeout, 300_000}], []) do
      {:ok, {{_, 200, _}, _headers, resp_body}} ->
        parse_openai_response(resp_body, "LMStudio", model)

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        {:error, {:api_error, status, to_string(resp_body)}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp call_openrouter(prompt, max_tokens, model) do
    api_key = System.get_env("OPENROUTER_API_KEY")

    unless api_key do
      {:error, :missing_openrouter_api_key}
    else
      url =
        System.get_env("OPENROUTER_URL", @openrouter_url_default)
        |> String.to_charlist()

      :inets.start()
      :ssl.start()

      body =
        Jason.encode!(%{
          model: model,
          max_tokens: max_tokens,
          temperature: 0.0,
          messages: [
            %{role: "user", content: prompt}
          ]
        })

      headers = [
        {~c"content-type", ~c"application/json"},
        {~c"authorization", String.to_charlist("Bearer #{api_key}")},
        {~c"http-referer", ~c"https://graphonomous.com"},
        {~c"x-title", ~c"Graphonomous Benchmark"}
      ]

      request = {url, headers, ~c"application/json", body}

      case :httpc.request(
             :post,
             request,
             [{:timeout, 300_000}, {:ssl, [{:verify, :verify_none}]}],
             []
           ) do
        {:ok, {{_, 200, _}, _headers, resp_body}} ->
          parse_openai_response(resp_body, "OpenRouter", model)

        {:ok, {{_, status, _}, _headers, resp_body}} ->
          {:error, {:api_error, status, to_string(resp_body)}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  # Shared OpenAI-format response parser for LMStudio and OpenRouter
  defp parse_openai_response(resp_body, source, model) do
    case Jason.decode(to_string(resp_body)) do
      {:ok, %{"choices" => [%{"message" => msg} | _]}} ->
        content = msg["content"]
        reasoning = msg["reasoning_content"]

        text =
          cond do
            is_binary(content) and String.trim(content) != "" -> String.trim(content)
            is_binary(reasoning) and String.trim(reasoning) != "" -> String.trim(reasoning)
            true -> ""
          end

        Logger.debug(
          "#{source} response: content=#{byte_size(content || "")}B reasoning=#{byte_size(reasoning || "")}B model=#{model}"
        )

        if text == "" do
          {:error, :empty_response}
        else
          {:ok, text}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end

  defp call_claude(prompt, max_tokens) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      :inets.start()
      :ssl.start()

      body =
        Jason.encode!(%{
          model: @model,
          max_tokens: max_tokens,
          messages: [%{role: "user", content: prompt}]
        })

      headers = [
        {~c"content-type", ~c"application/json"},
        {~c"x-api-key", String.to_charlist(api_key)},
        {~c"anthropic-version", ~c"2023-06-01"}
      ]

      request = {@api_url, headers, ~c"application/json", body}

      case :httpc.request(:post, request, [{:timeout, 30_000}], []) do
        {:ok, {{_, 200, _}, _headers, resp_body}} ->
          case Jason.decode(to_string(resp_body)) do
            {:ok, %{"content" => [%{"text" => text} | _]}} ->
              {:ok, text}

            {:ok, other} ->
              {:error, {:unexpected_response, other}}

            {:error, reason} ->
              {:error, {:json_decode, reason}}
          end

        {:ok, {{_, status, _}, _headers, resp_body}} ->
          {:error, {:api_error, status, to_string(resp_body)}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end
end
