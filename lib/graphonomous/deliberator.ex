defmodule Graphonomous.Deliberator do
  @moduledoc """
  κ-driven deliberation orchestrator for cyclic knowledge regions.

  This module is intentionally model-agnostic:
  - it decomposes SCCs into focused partitions,
  - runs partition-scoped reasoning via injected `agent_fn`,
  - reconciles intermediate conclusions,
  - optionally crystallizes conclusions back into the graph.

  Public entrypoint: `deliberate/4`.
  """

  alias Graphonomous.{CostTracker, ModelTier}

  @type node_id :: binary()

  @type conclusion :: %{
          content: binary(),
          confidence: float(),
          source_scc_id: binary() | nil,
          source_kappa: non_neg_integer(),
          fault_lines_examined: [%{source: node_id(), target: node_id()}]
        }

  @type deliberation_result :: %{
          converged: boolean(),
          iterations_used: non_neg_integer(),
          conclusions: [conclusion()],
          topology_change: %{
            kappa_before: non_neg_integer(),
            kappa_after: non_neg_integer(),
            new_nodes_created: non_neg_integer(),
            note: binary()
          }
        }

  @type scc :: map()
  @type partition :: %{
          left: [node_id()],
          right: [node_id()],
          fault_line: %{source: node_id(), target: node_id()} | nil
        }

  @default_budget %{
    max_iterations: 2,
    confidence_threshold: 0.75
  }

  @doc """
  Run κ-driven deliberation across SCCs from a topology payload.

  ## Parameters

    * `topology` - topology map (expects `:sccs`, `:max_kappa`; string keys accepted)
    * `query` - natural-language question/problem statement
    * `retrieval_results` - list of retrieval result maps
    * `opts` -
      - `:agent_fn` (required for non-heuristic behavior)
      - `:budget` (%{max_iterations, confidence_threshold})
      - `:write_back` (boolean, default: false)
      - `:source` (string metadata for crystallized nodes)

  ## Returns

  `%{converged, iterations_used, conclusions, topology_change}`
  """
  @spec deliberate(map(), binary(), [map()], keyword()) :: deliberation_result()
  def deliberate(topology, query, retrieval_results, opts \\ [])
      when is_map(topology) and is_binary(query) and is_list(retrieval_results) and is_list(opts) do
    sccs = get_in_any(topology, :sccs, [])
    max_kappa = as_non_neg_int(get_in_any(topology, :max_kappa, 0))

    if sccs == [] do
      %{
        converged: true,
        iterations_used: 0,
        conclusions: [],
        topology_change: %{
          kappa_before: max_kappa,
          kappa_after: max_kappa,
          new_nodes_created: 0,
          note: "No nontrivial SCCs detected; fast path requires no deliberation."
        }
      }
    else
      {tier, budget} = resolve_tier_and_budget(opts)
      strategy = get_in_any(budget, :strategy, :multi_pass)
      floor = as_non_neg_int(get_in_any(budget, :kappa_deliberation_floor, 1))
      agent_fn = Keyword.get(opts, :agent_fn, &heuristic_agent/1)
      write_back? = Keyword.get(opts, :write_back, false) == true

      sccs_to_deliberate =
        sccs
        |> Enum.filter(fn scc ->
          as_non_neg_int(get_in_any(scc, :kappa, 0)) >= floor
        end)

      {conclusions, iterations_used} =
        case strategy do
          :single_pass ->
            deliberate_single_pass(
              sccs_to_deliberate,
              query,
              retrieval_results,
              budget,
              Keyword.put(opts, :agent_fn, agent_fn)
            )

          _ ->
            sccs_to_deliberate
            |> Enum.reduce({[], 0}, fn scc, {acc, iter_acc} ->
              {conclusion, used} =
                deliberate_scc(
                  scc,
                  query,
                  retrieval_results,
                  budget,
                  Keyword.put(opts, :agent_fn, agent_fn)
                )

              {[conclusion | acc], iter_acc + used}
            end)
            |> then(fn {list, used} -> {Enum.reverse(list), used} end)
        end

      {new_nodes_created, _node_ids} =
        if write_back? do
          crystallize_all(conclusions, sccs_to_deliberate, opts)
        else
          {0, []}
        end

      converged? =
        conclusions == [] or
          Enum.all?(conclusions, fn c ->
            c.confidence >= to_float(get_in_any(budget, :confidence_threshold, 0.75))
          end)

      note =
        cond do
          sccs_to_deliberate == [] ->
            "All SCCs are below κ deliberation floor (κ floor=#{floor}) for tier #{tier}; skipped LLM deliberation."

          converged? ->
            "Deliberation converged. Crystallized conclusions can reduce effective future κ."

          true ->
            "Deliberation did not fully converge; keep SCC under deliberate routing."
        end

      %{
        converged: converged?,
        iterations_used: iterations_used,
        conclusions: conclusions,
        topology_change: %{
          kappa_before: max_kappa,
          kappa_after: max(max_kappa - if(converged? and conclusions != [], do: 1, else: 0), 0),
          new_nodes_created: new_nodes_created,
          note: note
        }
      }
    end
  end

  @doc """
  Decompose one SCC into candidate fault-line partitions.

  Strategy:
  1) Use explicit `fault_line_edges` if present.
  2) Fallback to one balanced split over SCC nodes.
  """
  @spec decompose(scc()) :: [partition()]
  def decompose(scc) when is_map(scc) do
    nodes =
      scc
      |> get_in_any(:nodes, [])
      |> normalize_node_ids()

    fault_lines =
      scc
      |> get_in_any(:fault_line_edges, [])
      |> normalize_fault_lines()

    cond do
      nodes == [] ->
        []

      fault_lines != [] ->
        Enum.map(fault_lines, fn fl ->
          left =
            nodes
            |> Enum.filter(fn n -> n != fl.target end)

          right = [fl.target]

          %{
            left: uniq_sorted(left),
            right: uniq_sorted(right),
            fault_line: fl
          }
        end)

      true ->
        {left, right} = split_balanced(nodes)

        [
          %{
            left: left,
            right: right,
            fault_line: nil
          }
        ]
    end
  end

  @doc """
  Build a focused prompt payload for one partition.

  The return value is a structured map so downstream `agent_fn` can format
  however it wants (LLM prompt, rules engine input, etc.).
  """
  @spec build_focused_prompt(binary(), partition(), scc(), [map()]) :: map()
  def build_focused_prompt(query, partition, scc, retrieval_results)
      when is_binary(query) and is_map(partition) and is_map(scc) and is_list(retrieval_results) do
    scc_id = get_in_any(scc, :id, nil)
    source_kappa = as_non_neg_int(get_in_any(scc, :kappa, 0))

    scoped_evidence =
      retrieval_results
      |> Enum.filter(fn row ->
        node_id = get_in_any(row, :node_id, nil)
        node_id in partition.left or node_id in partition.right
      end)
      |> Enum.take(12)

    %{
      mode: :focused_partition_analysis,
      query: query,
      scc_id: scc_id,
      source_kappa: source_kappa,
      partition: partition,
      evidence: scoped_evidence,
      instructions: [
        "Analyze causal tension across the partition boundary.",
        "Propose a concise conclusion that reduces contradiction.",
        "Return content + confidence in [0.0, 1.0]."
      ]
    }
  end

  @doc """
  Reconcile intermediate partition conclusions into one SCC-level conclusion.
  """
  @spec reconcile([map()], scc(), binary(), map()) :: conclusion()
  def reconcile(intermediates, scc, query, budget)
      when is_list(intermediates) and is_map(scc) and is_binary(query) and is_map(budget) do
    scc_id = get_in_any(scc, :id, nil)
    source_kappa = as_non_neg_int(get_in_any(scc, :kappa, 0))
    fault_lines = scc |> get_in_any(:fault_line_edges, []) |> normalize_fault_lines()

    texts =
      intermediates
      |> Enum.map(&normalize_agent_output/1)
      |> Enum.map(&Map.get(&1, :content))
      |> Enum.reject(&(not is_binary(&1) or String.trim(&1) == ""))

    base_conf =
      intermediates
      |> Enum.map(&normalize_agent_output/1)
      |> Enum.map(&Map.get(&1, :confidence, 0.5))
      |> avg_or(0.5)

    # κ-aware reconciliation penalty: higher κ demands stronger certainty.
    # Keeps confidence conservative in high-feedback regions.
    kappa_penalty = min(source_kappa * 0.04, 0.2)
    confidence_threshold = to_float(Map.get(budget, :confidence_threshold, 0.75))
    reconciled_conf = clamp(base_conf - kappa_penalty, 0.0, 1.0)

    content =
      case texts do
        [] ->
          "Deliberation on query '#{query}' produced no strong intermediate claims."

        _ ->
          summary =
            texts
            |> Enum.uniq()
            |> Enum.map(&("- " <> String.trim(&1)))
            |> Enum.join("\n")

          """
          Reconciled conclusion for #{scc_id || "unknown_scc"} (κ=#{source_kappa}) on query: #{query}

          #{summary}
          """
          |> String.trim()
      end

    # slight boost if already above threshold and multiple aligned intermediates
    aligned_bonus =
      if length(texts) >= 2 and reconciled_conf >= confidence_threshold do
        0.03
      else
        0.0
      end

    %{
      content: content,
      confidence: clamp(reconciled_conf + aligned_bonus, 0.0, 1.0),
      source_scc_id: scc_id,
      source_kappa: source_kappa,
      fault_lines_examined: fault_lines
    }
  end

  @doc """
  Optionally write a conclusion back to the graph as semantic knowledge.
  """
  @spec crystallize(conclusion(), scc(), keyword()) ::
          {:ok, binary()} | {:error, term()} | :skipped
  def crystallize(conclusion, scc, opts)
      when is_map(conclusion) and is_map(scc) and is_list(opts) do
    if Keyword.get(opts, :write_back, false) == true do
      source = Keyword.get(opts, :source, "deliberator:crystallization")
      scc_id = get_in_any(scc, :id, nil)

      attrs = %{
        content: Map.get(conclusion, :content, ""),
        node_type: :semantic,
        confidence: clamp(to_float(Map.get(conclusion, :confidence, 0.5)), 0.0, 1.0),
        source: source,
        metadata: %{
          "kind" => "deliberation_conclusion",
          "source_scc_id" => scc_id,
          "source_kappa" => as_non_neg_int(Map.get(conclusion, :source_kappa, 0)),
          "fault_lines_examined" => Map.get(conclusion, :fault_lines_examined, [])
        }
      }

      case Graphonomous.store_node(attrs) do
        %{id: id} when is_binary(id) -> {:ok, id}
        {:ok, %{id: id}} when is_binary(id) -> {:ok, id}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_store_node_response, other}}
      end
    else
      :skipped
    end
  end

  @spec deliberate_single_pass([scc()], binary(), [map()], map(), keyword()) ::
          {[conclusion()], non_neg_integer()}
  defp deliberate_single_pass(sccs, query, retrieval_results, _budget, opts) do
    agent_fn = Keyword.fetch!(opts, :agent_fn)

    tier =
      opts |> Keyword.get(:model_tier, ModelTier.current_tier()) |> ModelTier.normalize_tier()

    max_nodes_per_prompt =
      opts
      |> Keyword.get(:max_nodes_per_prompt, ModelTier.profile(tier).max_nodes_per_prompt)
      |> as_non_neg_int()
      |> max(1)

    conclusions =
      Enum.map(sccs, fn scc ->
        prompt = build_single_pass_prompt(query, scc, retrieval_results, max_nodes_per_prompt)
        output = agent_fn.(prompt) |> normalize_agent_output()
        conclusion = parse_single_pass_conclusion(output, scc, query)

        _ =
          CostTracker.record(%{
            operation: :deliberation,
            tier: tier,
            tokens_in: approx_token_count(inspect(prompt)),
            tokens_out: approx_token_count(Map.get(conclusion, :content, "")),
            inference_ms: 0.0,
            timestamp: DateTime.utc_now()
          })

        if Keyword.get(opts, :write_back, false) == true do
          _ = crystallize(conclusion, scc, opts)
        end

        conclusion
      end)

    {conclusions, length(conclusions)}
  end

  @spec build_single_pass_prompt(binary(), scc(), [map()], pos_integer()) :: map()
  defp build_single_pass_prompt(query, scc, retrieval_results, max_nodes_per_prompt) do
    nodes =
      scc
      |> get_in_any(:nodes, [])
      |> normalize_node_ids()
      |> Enum.take(max_nodes_per_prompt)

    fault_lines = scc |> get_in_any(:fault_line_edges, []) |> normalize_fault_lines()

    weakest_link =
      case fault_lines do
        [%{source: s, target: t} | _] -> "#{s} → #{t}"
        _ -> "unknown"
      end

    evidence =
      retrieval_results
      |> Enum.filter(fn row ->
        node_id = get_in_any(row, :node_id, nil)
        is_binary(node_id) and node_id in nodes
      end)
      |> Enum.take(max_nodes_per_prompt)

    %{
      mode: :single_pass_deliberation,
      query: query,
      scc_id: get_in_any(scc, :id, nil),
      source_kappa: as_non_neg_int(get_in_any(scc, :kappa, 0)),
      context_node_ids: nodes,
      evidence: evidence,
      topology_note:
        "These concepts form a feedback loop (κ=#{as_non_neg_int(get_in_any(scc, :kappa, 0))}). Weakest link: #{weakest_link}.",
      instruction:
        "Given the circular dependency and weakest link, provide one concise conclusion and confidence (0.0-1.0)."
    }
  end

  @spec parse_single_pass_conclusion(map(), scc(), binary()) :: conclusion()
  defp parse_single_pass_conclusion(output, scc, query) do
    content =
      case String.trim(Map.get(output, :content, "")) do
        "" ->
          "Single-pass deliberation produced no explicit claim for query '#{query}'."

        text ->
          text
      end

    %{
      content: content,
      confidence: clamp(to_float(Map.get(output, :confidence, 0.5)), 0.0, 1.0),
      source_scc_id: get_in_any(scc, :id, nil),
      source_kappa: as_non_neg_int(get_in_any(scc, :kappa, 0)),
      fault_lines_examined: scc |> get_in_any(:fault_line_edges, []) |> normalize_fault_lines()
    }
  end

  defp resolve_tier_and_budget(opts) do
    tier =
      opts |> Keyword.get(:model_tier, ModelTier.current_tier()) |> ModelTier.normalize_tier()

    tier_budget = ModelTier.deliberation_config(tier)
    user_budget = opts |> Keyword.get(:budget, %{}) |> normalize_map() |> atomize_keys()
    merged = Map.merge(tier_budget, user_budget)
    {tier, merged_budget(Keyword.put(opts, :budget, merged))}
  end

  # --- Internal loop ---

  @spec deliberate_scc(scc(), binary(), [map()], map(), keyword()) ::
          {conclusion(), non_neg_integer()}
  defp deliberate_scc(scc, query, retrieval_results, budget, opts) do
    partitions = decompose(scc)
    agent_fn = Keyword.fetch!(opts, :agent_fn)

    initial_intermediates =
      Enum.map(partitions, fn partition ->
        prompt = build_focused_prompt(query, partition, scc, retrieval_results)
        agent_fn.(prompt) |> normalize_agent_output()
      end)

    initial = reconcile(initial_intermediates, scc, query, budget)

    max_iterations = as_non_neg_int(Map.get(budget, :max_iterations, 2))
    threshold = to_float(Map.get(budget, :confidence_threshold, 0.75))

    if initial.confidence >= threshold or max_iterations <= 1 do
      {initial, max(max_iterations, 1) |> min(1)}
    else
      iterate_refinement(initial, query, scc, retrieval_results, budget, opts, 2, max_iterations)
    end
  end

  defp iterate_refinement(
         current,
         _query,
         _scc,
         _retrieval_results,
         _budget,
         _opts,
         iter,
         max_iter
       )
       when iter > max_iter do
    {current, max_iter}
  end

  defp iterate_refinement(current, query, scc, retrieval_results, budget, opts, iter, max_iter) do
    threshold = to_float(Map.get(budget, :confidence_threshold, 0.75))
    agent_fn = Keyword.fetch!(opts, :agent_fn)

    if current.confidence >= threshold do
      {current, iter - 1}
    else
      refine_prompt = %{
        mode: :reconcile_refinement,
        query: query,
        prior_conclusion: current,
        source_scc: %{
          id: get_in_any(scc, :id, nil),
          kappa: as_non_neg_int(get_in_any(scc, :kappa, 0)),
          fault_line_edges: get_in_any(scc, :fault_line_edges, [])
        },
        retrieval_sample: Enum.take(retrieval_results, 10),
        instructions: [
          "Tighten the conclusion to resolve contradiction.",
          "Increase precision, not verbosity.",
          "Return content + confidence."
        ]
      }

      refined =
        refine_prompt
        |> agent_fn.()
        |> normalize_agent_output()
        |> then(fn out ->
          %{
            current
            | content:
                if(String.trim(Map.get(out, :content, "")) == "",
                  do: current.content,
                  else: out.content
                ),
              confidence:
                clamp(
                  max(
                    current.confidence,
                    to_float(Map.get(out, :confidence, current.confidence))
                  ),
                  0.0,
                  1.0
                )
          }
        end)

      iterate_refinement(refined, query, scc, retrieval_results, budget, opts, iter + 1, max_iter)
    end
  end

  defp crystallize_all(conclusions, sccs, opts) do
    scc_by_id =
      sccs
      |> Enum.map(fn scc -> {get_in_any(scc, :id, nil), scc} end)
      |> Enum.into(%{})

    Enum.reduce(conclusions, {0, []}, fn conclusion, {count, ids} ->
      scc_id = Map.get(conclusion, :source_scc_id)
      scc = Map.get(scc_by_id, scc_id, %{"id" => scc_id})

      case crystallize(conclusion, scc, opts) do
        {:ok, node_id} -> {count + 1, [node_id | ids]}
        _ -> {count, ids}
      end
    end)
    |> then(fn {count, ids} -> {count, Enum.reverse(ids)} end)
  end

  # --- Default local agent (deterministic fallback) ---

  @spec heuristic_agent(map()) :: map()
  defp heuristic_agent(prompt) when is_map(prompt) do
    evidence = get_in_any(prompt, :evidence, [])
    source_kappa = as_non_neg_int(get_in_any(prompt, :source_kappa, 0))
    partition = get_in_any(prompt, :partition, %{})
    query = get_in_any(prompt, :query, "")

    evidence_lines =
      evidence
      |> Enum.take(3)
      |> Enum.map(fn row ->
        content = row |> get_in_any(:content, "") |> to_string()
        String.slice(content, 0, 180)
      end)
      |> Enum.reject(&(&1 == ""))

    content =
      case evidence_lines do
        [] ->
          "Heuristic deliberation: insufficient direct evidence for '#{query}' across partition #{inspect(partition)}."

        lines ->
          """
          Heuristic deliberation for '#{query}' (κ=#{source_kappa}) suggests:
          #{Enum.map_join(lines, "\n", &("- " <> &1))}
          """
          |> String.trim()
      end

    # conservative fallback confidence
    conf = clamp(0.62 - min(source_kappa * 0.03, 0.15), 0.3, 0.75)

    %{content: content, confidence: conf}
  end

  # --- Helpers ---

  defp merged_budget(opts) do
    user_budget = Keyword.get(opts, :budget, %{}) |> normalize_map() |> atomize_keys()

    %{
      strategy: Map.get(user_budget, :strategy, :multi_pass),
      max_agent_calls_per_scc: Map.get(user_budget, :max_agent_calls_per_scc, 1),
      timeout_multiplier:
        user_budget
        |> Map.get(:timeout_multiplier, 1.0)
        |> to_float()
        |> max(0.1),
      kappa_deliberation_floor:
        user_budget
        |> Map.get(:kappa_deliberation_floor, 1)
        |> as_non_neg_int(),
      max_iterations:
        user_budget
        |> Map.get(:max_iterations, @default_budget.max_iterations)
        |> as_non_neg_int()
        |> max(1),
      confidence_threshold:
        user_budget
        |> Map.get(:confidence_threshold, @default_budget.confidence_threshold)
        |> to_float()
        |> clamp(0.0, 1.0)
    }
  end

  defp normalize_agent_output(output) when is_binary(output) do
    %{content: String.trim(output), confidence: 0.5}
  end

  defp normalize_agent_output(output) when is_map(output) do
    %{
      content: output |> get_in_any(:content, "") |> to_string() |> String.trim(),
      confidence: output |> get_in_any(:confidence, 0.5) |> to_float() |> clamp(0.0, 1.0)
    }
  end

  defp normalize_agent_output(_), do: %{content: "", confidence: 0.5}

  defp normalize_fault_lines(lines) when is_list(lines) do
    lines
    |> Enum.map(fn
      %{source: s, target: t} when is_binary(s) and is_binary(t) ->
        %{source: s, target: t}

      %{"source" => s, "target" => t} when is_binary(s) and is_binary(t) ->
        %{source: s, target: t}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_fault_lines(_), do: []

  defp normalize_node_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&is_binary/1)
    |> uniq_sorted()
  end

  defp normalize_node_ids(_), do: []

  defp split_balanced([]), do: {[], []}
  defp split_balanced([only]), do: {[only], []}

  defp split_balanced(nodes) do
    sorted = uniq_sorted(nodes)
    cut = div(length(sorted), 2)
    {Enum.take(sorted, cut), Enum.drop(sorted, cut)}
  end

  defp uniq_sorted(list), do: list |> Enum.uniq() |> Enum.sort()

  defp get_in_any(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp get_in_any(_map, _key, default), do: default

  defp as_non_neg_int(v) when is_integer(v) and v >= 0, do: v
  defp as_non_neg_int(v) when is_float(v) and v >= 0, do: trunc(v)

  defp as_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> 0
    end
  end

  defp as_non_neg_int(_), do: 0

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp avg_or([], fallback), do: fallback
  defp avg_or(list, _fallback), do: Enum.sum(list) / length(list)

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_), do: %{}

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {safe_to_atom(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  defp safe_to_atom(key) when is_binary(key) do
    case key do
      "strategy" -> :strategy
      "max_agent_calls_per_scc" -> :max_agent_calls_per_scc
      "max_iterations" -> :max_iterations
      "confidence_threshold" -> :confidence_threshold
      "timeout_multiplier" -> :timeout_multiplier
      "kappa_deliberation_floor" -> :kappa_deliberation_floor
      _ -> String.to_atom(key)
    end
  rescue
    _ -> :unknown
  end

  defp approx_token_count(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> length()
    |> max(1)
  end

  defp approx_token_count(_), do: 1
end
