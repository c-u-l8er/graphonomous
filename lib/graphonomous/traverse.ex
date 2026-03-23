defmodule Graphonomous.Traverse do
  @moduledoc """
  LM Studio-driven traversal loop with Graphonomous-grounded completion.

  This runner is intentionally **external-authority first**:

  - The LLM proposes actions/claims.
  - Graphonomous stores outcomes and reviews coverage.
  - Completion is determined only by Graph/Goal state, never by LLM self-assertion.

  ## Core behavior

  1. Retrieve context from Graphonomous for the current objective.
  2. Query LM Studio chat/completions for the next iteration plan/report.
  3. Store episodic evidence and post outcome learning updates.
  4. Review goal coverage and apply decision->status transition policy.
  5. Terminate only when graph-grounded criteria are satisfied.

  ## Public API

      Graphonomous.Traverse.run(
        prompt: "...",
        model: "local-model",
        goal_id: "codebase-comprehension-parent",
        lm_studio_base_url: "http://127.0.0.1:1234/v1"
      )

  This function blocks until completion/stop/failure policy triggers.
  """

  require Logger

  @type run_result ::
          {:ok,
           %{
             reason: atom(),
             iterations: non_neg_integer(),
             stable_acts: non_neg_integer(),
             final_goal_progress: float() | nil,
             final_goal_status: atom() | String.t() | nil
           }}
          | {:error, term()}

  @default_lm_base_url "http://127.0.0.1:1234/v1"
  @default_model "local-model"
  @default_prompt """
  You are an autonomous engineering agent. Return STRICT JSON only.
  """

  @default_iteration_query "codebase comprehension traversal progress"
  @default_temperature 0.2
  @default_sleep_ms 8_000
  @default_backoff_ms 20_000
  @default_request_timeout_ms 60_000
  @default_connect_timeout_ms 15_000
  @default_target_progress 0.90
  @default_required_stable_acts 3
  @default_max_consecutive_failures 6
  @default_retrieve_limit 10
  @default_consolidation_cadence 5
  @default_review_opts [top_k: 8, min_context_nodes: 3, graph_support_target: 6]

  @doc """
  Run traversal loop.

  ## Options

    * `:prompt` - base user prompt for the traversal agent
    * `:system_prompt` - system instruction used for LM Studio
    * `:lm_studio_base_url` - defaults to `http://127.0.0.1:1234/v1`
    * `:lm_studio_endpoint` - optional full endpoint override
    * `:model` - LM Studio model identifier
    * `:temperature` - generation temperature (default: 0.2)
    * `:goal_id` - required durable goal id used for grounded completion checks
    * `:traversal_root` - required filesystem root path to scan each iteration
    * `:objective_query` - retrieval query template
    * `:retrieve_limit` - retrieve_context result cap
    * `:max_iterations` - nil for open-ended loop
    * `:sleep_ms` - successful iteration delay
    * `:backoff_ms` - delay after failures
    * `:request_timeout_ms` - HTTP request timeout
    * `:connect_timeout_ms` - HTTP connect timeout
    * `:target_progress` - graph-grounded progress threshold
    * `:required_stable_acts` - required consecutive `:act` decisions
    * `:max_consecutive_failures` - hard stop policy
    * `:consolidation_cadence` - run consolidation every N iterations
    * `:stop_file` - optional filesystem kill switch path
    * `:goal_bootstrap` - optional map for creating goal if absent

  Returns `{:ok, result}` on controlled halt, or `{:error, reason}`.
  """
  @spec run(keyword()) :: run_result()
  def run(opts \\ []) when is_list(opts) do
    with :ok <- ensure_http_client_started(),
         {:ok, cfg} <- build_config(opts),
         :ok <- maybe_bootstrap_goal(cfg) do
      Logger.info("traverse loop started goal_id=#{cfg.goal_id}")

      initial_state = %{
        iter: 0,
        stable_acts: 0,
        consecutive_failures: 0,
        started_at: DateTime.utc_now()
      }

      loop(cfg, initial_state)
    end
  end

  defp loop(cfg, state) do
    cond do
      should_stop_file?(cfg.stop_file) ->
        {:ok, finalize_result(:stop_file, state, cfg)}

      max_iterations_reached?(state.iter, cfg.max_iterations) ->
        {:ok, finalize_result(:max_iterations, state, cfg)}

      state.consecutive_failures >= cfg.max_consecutive_failures ->
        {:ok, finalize_result(:max_consecutive_failures, state, cfg)}

      true ->
        iter = state.iter + 1

        case run_iteration(iter, cfg, state) do
          {:ok, iter_outcome, next_state} ->
            maybe_consolidate(iter, cfg)
            sleep_ms = if iter_outcome == :failure, do: cfg.backoff_ms, else: cfg.sleep_ms
            Process.sleep(sleep_ms)

            case grounded_completion?(cfg, next_state.stable_acts) do
              {:ok, true} ->
                {:ok, finalize_result(:grounded_completion, next_state, cfg)}

              {:ok, false} ->
                loop(cfg, next_state)

              {:error, reason} ->
                Logger.warning("grounded completion check failed: #{inspect(reason)}")
                loop(cfg, next_state)
            end

          {:error, reason, next_state} ->
            Logger.warning("iteration #{iter} failed: #{inspect(reason)}")
            Process.sleep(cfg.backoff_ms)
            loop(cfg, next_state)
        end
    end
  end

  defp run_iteration(iter, cfg, state) do
    Logger.info("iteration=#{iter} starting")

    with :ok <- run_filesystem_scan(iter, cfg) do
      retrieval = retrieve_context(cfg, iter)
      {retrieved_nodes, causal_context_ids} = normalize_retrieval(retrieval)

      user_prompt = build_iteration_prompt(cfg, iter, retrieved_nodes)

      with {:ok, llm_payload, raw_content} <- lmstudio_infer(cfg, user_prompt),
           :ok <- store_iteration_episode(iter, llm_payload, raw_content, retrieved_nodes),
           :ok <- post_learning_update(iter, llm_payload, causal_context_ids),
           {:ok, decision} <-
             review_and_transition_goal(cfg, llm_payload, retrieved_nodes, causal_context_ids),
           {:ok, next_state} <- update_state_from_decision(state, decision) do
        Logger.info("iteration=#{iter} decision=#{inspect(decision)}")
        {:ok, :success, %{next_state | iter: iter, consecutive_failures: 0}}
      else
        {:error, reason} ->
          next_state = %{state | iter: iter, consecutive_failures: state.consecutive_failures + 1}
          {:error, reason, next_state}
      end
    else
      {:error, reason} ->
        next_state = %{state | iter: iter, consecutive_failures: state.consecutive_failures + 1}
        {:error, reason, next_state}
    end
  end

  defp run_filesystem_scan(iter, cfg) do
    case Graphonomous.FilesystemTraversal.scan_directory(cfg.traversal_root, recursive: true) do
      {:ok, result} ->
        Logger.info(
          "iteration=#{iter} scan root=#{cfg.traversal_root} discovered=#{result.files_discovered} ingested=#{result.files_ingested} failed=#{result.files_failed}"
        )

        :ok

      {:error, reason} ->
        {:error, {:filesystem_scan_failed, reason}}

      other ->
        {:error, {:filesystem_scan_unexpected, other}}
    end
  end

  defp retrieve_context(cfg, iter) do
    query = "#{cfg.objective_query} iteration=#{iter}"

    case Graphonomous.retrieve_context(query,
           limit: cfg.retrieve_limit,
           expansion_hops: 1,
           neighbors_per_node: 5
         ) do
      %{} = retrieval ->
        {:ok, retrieval}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_retrieval_response, other}}
    end
  end

  defp normalize_retrieval({:ok, %{} = retrieval}) do
    results =
      retrieval
      |> Map.get(:results, Map.get(retrieval, "results", []))
      |> normalize_list()

    causal_context =
      retrieval
      |> Map.get(:causal_context, Map.get(retrieval, "causal_context", []))
      |> normalize_string_list()

    {results, causal_context}
  end

  defp normalize_retrieval({:error, _reason}), do: {[], []}
  defp normalize_retrieval(_), do: {[], []}

  defp build_iteration_prompt(cfg, iter, retrieved_nodes) do
    retrieval_summary =
      retrieved_nodes
      |> Enum.take(8)
      |> Enum.map(fn node ->
        id = map_get(node, :node_id, map_get(node, "node_id", "unknown"))
        score = map_get(node, :score, map_get(node, "score", 0.0))
        content = map_get(node, :content, map_get(node, "content", ""))
        short = content |> to_string() |> String.slice(0, 180) |> String.replace("\n", " ")
        "- id=#{id} score=#{score} content=#{short}"
      end)
      |> Enum.join("\n")

    """
    #{cfg.prompt}

    Iteration: #{iter}
    Goal ID: #{cfg.goal_id}
    Retrieval context (top):
    #{if retrieval_summary == "", do: "- none", else: retrieval_summary}

    Return STRICT JSON object with keys:
    - objective (string)
    - actions (array of strings)
    - claims (array of objects with `text` and optional `evidence`)
    - action_id (string)
    - causal_node_ids (array of strings)
    - confidence (number 0..1)
    - status (success|partial_success|failure|timeout; optional)
    - notes (string; optional)
    """
  end

  defp lmstudio_infer(cfg, user_prompt) do
    body = %{
      model: cfg.model,
      temperature: cfg.temperature,
      messages: [
        %{role: "system", content: cfg.system_prompt},
        %{role: "user", content: user_prompt}
      ]
    }

    with {:ok, response_json} <- lmstudio_chat_request(cfg, body),
         {:ok, content} <- extract_chat_content(response_json),
         {:ok, payload} <- decode_agent_payload(content) do
      {:ok, payload, content}
    end
  end

  defp lmstudio_chat_request(cfg, body) do
    endpoint = lm_endpoint(cfg)

    headers = [{~c"content-type", ~c"application/json"}]
    request_body = Jason.encode!(body)

    http_opts = [
      timeout: cfg.request_timeout_ms,
      connect_timeout: cfg.connect_timeout_ms
    ]

    request = {to_charlist(endpoint), headers, ~c"application/json", request_body}

    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_http, 200, _reason}, _resp_headers, resp_body}} ->
        Jason.decode(resp_body)

      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} ->
        {:error, {:lmstudio_http_status, status, safe_body_preview(resp_body)}}

      {:error, reason} ->
        {:error, {:lmstudio_http_error, reason}}
    end
  end

  defp extract_chat_content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    {:ok, content}
  end

  defp extract_chat_content(%{choices: [%{message: %{content: content}} | _]})
       when is_binary(content) do
    {:ok, content}
  end

  defp extract_chat_content(other), do: {:error, {:invalid_lmstudio_response, other}}

  defp decode_agent_payload(content) when is_binary(content) do
    cleaned =
      content
      |> String.trim()
      |> strip_code_fences()

    case Jason.decode(cleaned) do
      {:ok, %{} = payload} ->
        {:ok, payload}

      {:ok, other} ->
        {:error, {:agent_payload_not_object, other}}

      {:error, _} ->
        {:error, {:agent_payload_not_json, cleaned}}
    end
  end

  defp strip_code_fences(text) do
    if String.starts_with?(text, "```") do
      text
      |> String.trim_leading("```json")
      |> String.trim_leading("```")
      |> String.trim_trailing("```")
      |> String.trim()
    else
      text
    end
  end

  defp store_iteration_episode(iter, payload, raw_content, retrieved_nodes) do
    metadata = %{
      iteration: iter,
      retrieved_node_count: length(retrieved_nodes),
      action_id: map_get(payload, "action_id", map_get(payload, :action_id, "iter-#{iter}"))
    }

    content =
      Jason.encode!(%{
        iteration: iter,
        payload: payload,
        raw_content: raw_content
      })

    case Graphonomous.store_node(%{
           node_type: :episodic,
           source: "traverse.loop",
           confidence: normalize_confidence(map_get(payload, "confidence", 0.7)),
           metadata: metadata,
           content: content
         }) do
      %{} -> :ok
      {:error, reason} -> {:error, {:store_episode_failed, reason}}
      other -> {:error, {:store_episode_unexpected, other}}
    end
  end

  defp post_learning_update(iter, payload, fallback_causal_ids) do
    action_id = to_string(map_get(payload, "action_id", "iter-#{iter}"))
    status = map_get(payload, "status", "partial_success")

    causal_node_ids =
      payload
      |> map_get("causal_node_ids", fallback_causal_ids)
      |> normalize_string_list()

    attrs = %{
      action_id: action_id,
      status: status,
      confidence: normalize_confidence(map_get(payload, "confidence", 0.7)),
      causal_node_ids: causal_node_ids,
      evidence: %{
        claims: map_get(payload, "claims", []),
        actions: map_get(payload, "actions", []),
        objective: map_get(payload, "objective", nil),
        notes: map_get(payload, "notes", nil)
      }
    }

    case Graphonomous.learn_from_outcome(attrs) do
      %{} -> :ok
      {:error, reason} -> {:error, {:learn_from_outcome_failed, reason}}
      other -> {:error, {:learn_from_outcome_unexpected, other}}
    end
  end

  defp review_and_transition_goal(cfg, payload, retrieved_nodes, causal_node_ids) do
    signal = %{
      retrieved_nodes: normalize_list(retrieved_nodes),
      outcomes: [
        %{
          status: map_get(payload, "status", "partial_success"),
          confidence: normalize_confidence(map_get(payload, "confidence", 0.7))
        }
      ],
      contradictions: 0,
      graph_support: length(normalize_string_list(causal_node_ids))
    }

    case Graphonomous.review_goal(cfg.goal_id, signal, cfg.review_opts) do
      {:ok, goal, evaluation} ->
        decision = map_get(evaluation, :decision, map_get(evaluation, "decision", :learn))

        coverage_score =
          normalize_confidence(
            map_get(evaluation, :coverage_score, map_get(evaluation, "coverage_score", 0.0))
          )

        maybe_apply_decision_transition(goal, decision)

        case Graphonomous.set_goal_progress(cfg.goal_id, coverage_score) do
          %{} ->
            {:ok, decision}

          {:error, reason} ->
            {:error, {:set_goal_progress_failed, reason}}

          other ->
            {:error, {:set_goal_progress_unexpected, other}}
        end

      {:error, reason} ->
        {:error, {:review_goal_failed, reason}}

      other ->
        {:error, {:review_goal_unexpected, other}}
    end
  end

  defp maybe_apply_decision_transition(goal, decision) do
    goal_id = map_get(goal, :id, map_get(goal, "id", nil))
    target_status = status_for_decision(decision)

    cond do
      not is_binary(goal_id) ->
        :ok

      is_nil(target_status) ->
        :ok

      true ->
        _ =
          Graphonomous.transition_goal(goal_id, target_status, %{
            source: "traverse.loop",
            policy: "coverage_decision",
            decision: decision_to_string(decision)
          })

        :ok
    end
  end

  defp status_for_decision(:act), do: :active
  defp status_for_decision("act"), do: :active
  defp status_for_decision(:learn), do: :proposed
  defp status_for_decision("learn"), do: :proposed
  defp status_for_decision(:escalate), do: :blocked
  defp status_for_decision("escalate"), do: :blocked
  defp status_for_decision(_), do: nil

  defp decision_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp decision_to_string(value) when is_binary(value), do: value
  defp decision_to_string(value), do: inspect(value)

  defp update_state_from_decision(state, decision) do
    stable_acts =
      if decision in [:act, "act"] do
        state.stable_acts + 1
      else
        0
      end

    {:ok, %{state | stable_acts: stable_acts}}
  end

  defp maybe_consolidate(iter, cfg) do
    if cfg.consolidation_cadence > 0 and rem(iter, cfg.consolidation_cadence) == 0 do
      _ = Graphonomous.run_consolidation_now()
      :ok
    else
      :ok
    end
  end

  defp grounded_completion?(cfg, stable_acts) do
    case Graphonomous.get_goal(cfg.goal_id) do
      %{} = goal ->
        progress = normalize_confidence(map_get(goal, :progress, map_get(goal, "progress", 0.0)))
        status = map_get(goal, :status, map_get(goal, "status", nil))

        completed? =
          progress >= cfg.target_progress and
            stable_acts >= cfg.required_stable_acts and
            status not in [:blocked, "blocked"]

        {:ok, completed?}

      {:error, reason} ->
        {:error, {:get_goal_failed, reason}}

      other ->
        {:error, {:unexpected_get_goal_response, other}}
    end
  end

  defp finalize_result(reason, state, cfg) do
    {progress, status} =
      case Graphonomous.get_goal(cfg.goal_id) do
        %{} = goal ->
          {
            map_get(goal, :progress, map_get(goal, "progress", nil)),
            map_get(goal, :status, map_get(goal, "status", nil))
          }

        _ ->
          {nil, nil}
      end

    %{
      reason: reason,
      iterations: state.iter,
      stable_acts: state.stable_acts,
      final_goal_progress: progress,
      final_goal_status: status
    }
  end

  defp maybe_bootstrap_goal(cfg) do
    case Graphonomous.get_goal(cfg.goal_id) do
      %{} ->
        :ok

      {:error, :not_found} ->
        attrs =
          cfg.goal_bootstrap
          |> Map.put_new(:id, cfg.goal_id)
          |> Map.put_new(:title, "Codebase comprehension and traversal")
          |> Map.put_new(:description, "Durable traversal loop goal")
          |> Map.put_new(:status, :active)
          |> Map.put_new(:timescale, :short_term)
          |> Map.put_new(:priority, :high)
          |> Map.put_new(:progress, 0.0)
          |> Map.put_new(:confidence, 0.7)

        case Graphonomous.create_goal(attrs) do
          %{} -> :ok
          {:error, reason} -> {:error, {:create_goal_failed, reason}}
          other -> {:error, {:create_goal_unexpected, other}}
        end

      {:error, reason} ->
        {:error, {:goal_lookup_failed, reason}}

      _other ->
        :ok
    end
  end

  defp build_config(opts) do
    goal_id = opts[:goal_id]
    traversal_root = opts[:traversal_root]

    cond do
      not is_binary(goal_id) or String.trim(goal_id) == "" ->
        {:error, :missing_goal_id}

      not is_binary(traversal_root) or String.trim(traversal_root) == "" ->
        {:error, :missing_traversal_root}

      true ->
        with {:ok, normalized_root} <- normalize_root_path(traversal_root) do
          cfg = %{
            prompt: Keyword.get(opts, :prompt, @default_prompt),
            system_prompt: Keyword.get(opts, :system_prompt, @default_prompt),
            model:
              Keyword.get(
                opts,
                :model,
                System.get_env("LM_STUDIO_MODEL") || @default_model
              ),
            lm_studio_base_url:
              Keyword.get(
                opts,
                :lm_studio_base_url,
                System.get_env("LM_STUDIO_BASE_URL") || @default_lm_base_url
              ),
            lm_studio_endpoint: Keyword.get(opts, :lm_studio_endpoint, nil),
            temperature:
              normalize_number(Keyword.get(opts, :temperature, @default_temperature), 0.2),
            objective_query: Keyword.get(opts, :objective_query, @default_iteration_query),
            retrieve_limit:
              normalize_positive_int(
                Keyword.get(opts, :retrieve_limit, @default_retrieve_limit),
                @default_retrieve_limit
              ),
            goal_id: goal_id,
            traversal_root: normalized_root,
            target_progress:
              normalize_confidence(Keyword.get(opts, :target_progress, @default_target_progress)),
            required_stable_acts:
              normalize_positive_int(
                Keyword.get(opts, :required_stable_acts, @default_required_stable_acts),
                @default_required_stable_acts
              ),
            max_consecutive_failures:
              normalize_positive_int(
                Keyword.get(opts, :max_consecutive_failures, @default_max_consecutive_failures),
                @default_max_consecutive_failures
              ),
            max_iterations: Keyword.get(opts, :max_iterations, nil),
            sleep_ms:
              normalize_positive_int(
                Keyword.get(opts, :sleep_ms, @default_sleep_ms),
                @default_sleep_ms
              ),
            backoff_ms:
              normalize_positive_int(
                Keyword.get(opts, :backoff_ms, @default_backoff_ms),
                @default_backoff_ms
              ),
            request_timeout_ms:
              normalize_positive_int(
                Keyword.get(opts, :request_timeout_ms, @default_request_timeout_ms),
                @default_request_timeout_ms
              ),
            connect_timeout_ms:
              normalize_positive_int(
                Keyword.get(opts, :connect_timeout_ms, @default_connect_timeout_ms),
                @default_connect_timeout_ms
              ),
            consolidation_cadence:
              normalize_non_neg_int(
                Keyword.get(opts, :consolidation_cadence, @default_consolidation_cadence),
                @default_consolidation_cadence
              ),
            stop_file: Keyword.get(opts, :stop_file, nil),
            review_opts: Keyword.get(opts, :review_opts, @default_review_opts),
            goal_bootstrap: normalize_map(Keyword.get(opts, :goal_bootstrap, %{}))
          }

          {:ok, cfg}
        end
    end
  end

  defp ensure_http_client_started do
    _ = :inets.start()
    _ = :ssl.start()
    :ok
  end

  defp lm_endpoint(cfg) do
    case cfg.lm_studio_endpoint do
      endpoint when is_binary(endpoint) and endpoint != "" ->
        endpoint

      _ ->
        base = String.trim_trailing(cfg.lm_studio_base_url, "/")

        if String.ends_with?(base, "/chat/completions") do
          base
        else
          base <> "/chat/completions"
        end
    end
  end

  defp should_stop_file?(nil), do: false
  defp should_stop_file?(path) when is_binary(path), do: File.exists?(path)
  defp should_stop_file?(_), do: false

  defp max_iterations_reached?(_iter, nil), do: false

  defp max_iterations_reached?(iter, max_iterations)
       when is_integer(max_iterations) and max_iterations > 0 do
    iter >= max_iterations
  end

  defp max_iterations_reached?(_, _), do: false

  defp safe_body_preview(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp safe_body_preview(body), do: inspect(body)

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(_), do: []

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_), do: []

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp normalize_root_path(path) when is_binary(path) do
    expanded =
      path
      |> String.trim()
      |> Path.expand()

    with true <- expanded != "",
         {:ok, stat} <- File.stat(expanded),
         true <- stat.type == :directory do
      {:ok, expanded}
    else
      false -> {:error, :missing_traversal_root}
      {:error, reason} -> {:error, {:invalid_traversal_root, reason}}
      _ -> {:error, :invalid_traversal_root}
    end
  end

  defp normalize_root_path(_), do: {:error, :missing_traversal_root}

  defp normalize_positive_int(value, _fallback) when is_integer(value) and value > 0, do: value
  defp normalize_positive_int(_value, fallback), do: fallback

  defp normalize_non_neg_int(value, _fallback) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_int(_value, fallback), do: fallback

  defp normalize_number(value, _fallback) when is_number(value), do: value * 1.0

  defp normalize_number(value, fallback) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> fallback
    end
  end

  defp normalize_number(_value, fallback), do: fallback

  defp normalize_confidence(value) when is_integer(value), do: normalize_confidence(value * 1.0)

  defp normalize_confidence(value) when is_float(value) do
    value
    |> max(0.0)
    |> min(1.0)
  end

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> normalize_confidence(num)
      :error -> 0.5
    end
  end

  defp normalize_confidence(_), do: 0.5

  defp map_get(map, key, default) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        if is_atom(key) do
          Map.get(map, Atom.to_string(key), default)
        else
          key_string = to_string(key)

          case safe_to_existing_atom(key_string) do
            {:ok, atom_key} ->
              Map.get(map, atom_key, Map.get(map, key_string, default))

            :error ->
              Map.get(map, key_string, Map.get(map, key, default))
          end
        end
    end
  rescue
    _ -> default
  end

  defp safe_to_existing_atom(key) when is_binary(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end
end
