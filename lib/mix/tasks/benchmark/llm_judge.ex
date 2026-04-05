defmodule Mix.Tasks.Benchmark.LlmJudge do
  @moduledoc """
  LLM-based answer generation and judging for LongMemEval benchmark.

  Uses the Claude API via :httpc to:
  1. Generate an answer from retrieved context
  2. Judge the generated answer against the expected answer

  Requires ANTHROPIC_API_KEY environment variable.
  """

  require Logger

  @api_url ~c"https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @max_tokens 256
  @judge_max_tokens 64

  @doc "Check if judge mode is available (API key set)"
  def available? do
    System.get_env("ANTHROPIC_API_KEY") != nil
  end

  @doc """
  Generate an answer from retrieved context and judge it.

  Returns {:ok, %{answer: String.t(), score: 0.0 | 0.5 | 1.0, reasoning: String.t()}}
  or {:error, reason}.
  """
  def judge_answer(question, retrieved_context, expected_answer) do
    with {:ok, generated} <- generate_answer(question, retrieved_context),
         {:ok, score, reasoning} <- score_answer(question, generated, expected_answer) do
      {:ok, %{answer: generated, score: score, reasoning: reasoning}}
    else
      {:error, reason} ->
        Logger.warning("LLM judge failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_answer(question, context) do
    prompt = """
    Based on the following conversation history/context, answer the question concisely.
    If the context doesn't contain enough information, say "I don't have enough information to answer."

    Context:
    #{String.slice(context, 0, 6000)}

    Question: #{question}

    Answer concisely in 1-3 sentences:
    """

    call_claude(prompt, @max_tokens)
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

    Respond with ONLY a JSON object: {"score": <number>, "reasoning": "<brief explanation>"}
    """

    case call_claude(prompt, @judge_max_tokens) do
      {:ok, response} ->
        parse_judge_response(response)

      error ->
        error
    end
  end

  defp parse_judge_response(response) do
    # Try to extract JSON from response
    case Regex.run(
           ~r/\{[^}]*"score"\s*:\s*([\d.]+)[^}]*"reasoning"\s*:\s*"([^"]*)"[^}]*\}/,
           response
         ) do
      [_, score_str, reasoning] ->
        score =
          case Float.parse(score_str) do
            {s, _} -> clamp_score(s)
            :error -> 0.0
          end

        {:ok, score, reasoning}

      _ ->
        # Fallback: look for just a number
        case Regex.run(~r/(1\.0|0\.5|0\.0|1|0)/, response) do
          [_, s] ->
            {score, _} = Float.parse(s)
            {:ok, clamp_score(score), "parsed from response"}

          _ ->
            {:ok, 0.0, "could not parse judge response"}
        end
    end
  end

  defp clamp_score(s) when s >= 0.75, do: 1.0
  defp clamp_score(s) when s >= 0.25, do: 0.5
  defp clamp_score(_), do: 0.0

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
