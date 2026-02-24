defmodule Graphonomous.Coverage do
  @moduledoc """
  Epistemic coverage scoring for `act` / `learn` / `escalate` decisions.

  The module evaluates how well current memory and evidence cover a requested
  decision context, then emits:

  - `coverage_score` (0.0..1.0)
  - `uncertainty_score` (0.0..1.0)
  - `risk_score` (0.0..1.0)
  - `decision` (`:act | :learn | :escalate`)
  - `rationale` and per-component diagnostics

  ## Expected input shape

      %{
        retrieved_nodes: [map()],
        outcomes: [map()],
        contradictions: non_neg_integer() | [map()],
        graph_support: non_neg_integer(),
        known_unknowns: float(),         # optional
        goal_criticality: float()        # optional
      }

  Any key can be provided as either atom or string.

  ## Node fields used (when present)

  - `score`
  - `confidence`
  - `similarity`
  - `updated_at` / `created_at`
  - `edge_count`

  ## Outcome fields used (when present)

  - `status` (`:success | :partial_success | :failure | :timeout` or string)
  - `confidence` (`0.0..1.0`)
  """

  @type decision :: :act | :learn | :escalate

  @type evaluation :: %{
          decision: decision(),
          decision_confidence: float(),
          coverage_score: float(),
          uncertainty_score: float(),
          risk_score: float(),
          components: map(),
          thresholds: map(),
          rationale: [String.t()],
          diagnostics: map(),
          computed_at: DateTime.t()
        }

  @default_weights %{
    semantic_coverage: 0.40,
    consistency: 0.20,
    freshness: 0.15,
    graph_support: 0.15,
    outcome_reliability: 0.10
  }

  @default_thresholds %{
    act_coverage: 0.72,
    learn_coverage: 0.45,
    act_max_uncertainty: 0.35,
    act_max_risk: 0.45,
    learn_max_uncertainty: 0.70,
    learn_max_risk: 0.75
  }

  @default_opts [
    top_k: 8,
    min_context_nodes: 3,
    freshness_half_life_hours: 7 * 24,
    graph_support_target: 6
  ]

  @known_signal_keys %{
    "retrieved_nodes" => :retrieved_nodes,
    "outcomes" => :outcomes,
    "contradictions" => :contradictions,
    "graph_support" => :graph_support,
    "known_unknowns" => :known_unknowns,
    "goal_criticality" => :goal_criticality
  }

  @doc """
  Evaluate epistemic coverage and return a structured decision payload.
  """
  @spec evaluate(map(), keyword()) :: evaluation()
  def evaluate(signal, opts \\ []) when is_map(signal) and is_list(opts) do
    opts = Keyword.merge(@default_opts, opts)

    weights =
      opts
      |> Keyword.get(:weights, %{})
      |> merge_numeric_map(@default_weights)

    thresholds =
      opts
      |> Keyword.get(:thresholds, %{})
      |> merge_numeric_map(@default_thresholds)

    signal = normalize_signal(signal)

    components = %{
      semantic_coverage: semantic_coverage(signal, opts),
      consistency: consistency_score(signal),
      freshness: freshness_score(signal, opts),
      graph_support: graph_support_score(signal, opts),
      outcome_reliability: outcome_reliability_score(signal)
    }

    coverage_score = weighted_sum(components, weights)

    uncertainty_score =
      uncertainty_score(signal, components, opts)
      |> clamp01()

    risk_score =
      risk_score(signal, components)
      |> clamp01()

    decision =
      pick_decision(
        coverage_score,
        uncertainty_score,
        risk_score,
        thresholds
      )

    decision_confidence =
      decision_confidence(decision, coverage_score, uncertainty_score, risk_score)

    %{
      decision: decision,
      decision_confidence: decision_confidence,
      coverage_score: clamp01(coverage_score),
      uncertainty_score: uncertainty_score,
      risk_score: risk_score,
      components: components,
      thresholds: thresholds,
      rationale:
        rationale(
          decision,
          coverage_score,
          uncertainty_score,
          risk_score,
          components,
          thresholds
        ),
      diagnostics: diagnostics(signal, components, opts),
      computed_at: DateTime.utc_now()
    }
  end

  @doc """
  Return only the recommended action atom.
  """
  @spec decide(map(), keyword()) :: decision()
  def decide(signal, opts \\ []) do
    signal
    |> evaluate(opts)
    |> Map.fetch!(:decision)
  end

  @doc """
  Return a concise map useful for orchestration pipelines.
  """
  @spec recommend(map(), keyword()) :: map()
  def recommend(signal, opts \\ []) do
    result = evaluate(signal, opts)

    %{
      decision: result.decision,
      decision_confidence: result.decision_confidence,
      coverage_score: result.coverage_score,
      uncertainty_score: result.uncertainty_score,
      risk_score: result.risk_score,
      rationale: result.rationale
    }
  end

  # -- coverage components -----------------------------------------------------

  defp semantic_coverage(signal, opts) do
    nodes = Map.get(signal, :retrieved_nodes, [])
    top_k = Keyword.get(opts, :top_k, 8)

    scores =
      nodes
      |> Enum.map(&node_score/1)
      |> Enum.sort(:desc)
      |> Enum.take(top_k)

    case scores do
      [] ->
        0.0

      _ ->
        scores
        |> mean()
        |> clamp01()
    end
  end

  defp consistency_score(signal) do
    contradictions = contradiction_count(signal)
    outcomes = Map.get(signal, :outcomes, [])

    failure_weight =
      outcomes
      |> Enum.map(&outcome_conflicting_weight/1)
      |> mean_or_zero()

    contradiction_penalty =
      if contradictions <= 0 do
        0.0
      else
        clamp01(contradictions / 5.0)
      end

    (1.0 - (0.60 * contradiction_penalty + 0.40 * failure_weight))
    |> clamp01()
  end

  defp freshness_score(signal, opts) do
    half_life = Keyword.get(opts, :freshness_half_life_hours, 168)
    now = DateTime.utc_now()

    fresh_values =
      signal
      |> Map.get(:retrieved_nodes, [])
      |> Enum.map(fn node ->
        node
        |> node_timestamp()
        |> freshness_from_timestamp(now, half_life)
      end)

    mean_or_zero(fresh_values)
    |> clamp01()
  end

  defp graph_support_score(signal, opts) do
    target = Keyword.get(opts, :graph_support_target, 6)

    explicit_support = get_num(signal, :graph_support, nil)

    score =
      cond do
        is_number(explicit_support) ->
          saturation(explicit_support, target)

        true ->
          edge_count =
            signal
            |> Map.get(:retrieved_nodes, [])
            |> Enum.map(&get_num(&1, :edge_count, 0))
            |> Enum.sum()

          saturation(edge_count, target)
      end

    clamp01(score)
  end

  defp outcome_reliability_score(signal) do
    outcomes = Map.get(signal, :outcomes, [])

    case outcomes do
      [] ->
        # Neutral prior
        0.5

      _ ->
        outcomes
        |> Enum.map(&outcome_reliability/1)
        |> mean_or_zero()
        |> clamp01()
    end
  end

  # -- uncertainty + risk ------------------------------------------------------

  defp uncertainty_score(signal, components, opts) do
    semantic_gap = 1.0 - Map.get(components, :semantic_coverage, 0.0)
    known_unknowns = clamp01(get_num(signal, :known_unknowns, 0.0))

    min_nodes = Keyword.get(opts, :min_context_nodes, 3)
    node_count = length(Map.get(signal, :retrieved_nodes, []))

    low_evidence_penalty =
      if node_count >= min_nodes do
        0.0
      else
        clamp01((min_nodes - node_count) / max(min_nodes * 1.0, 1.0))
      end

    score_dispersion =
      signal
      |> Map.get(:retrieved_nodes, [])
      |> Enum.map(&node_score/1)
      |> stddev()

    (0.45 * semantic_gap + 0.25 * score_dispersion + 0.20 * low_evidence_penalty +
       0.10 * known_unknowns)
    |> clamp01()
  end

  defp risk_score(signal, components) do
    outcomes = Map.get(signal, :outcomes, [])

    failure_rate =
      outcomes
      |> Enum.map(&failure_risk/1)
      |> mean_or_zero()

    consistency_gap = 1.0 - Map.get(components, :consistency, 0.0)
    staleness = 1.0 - Map.get(components, :freshness, 0.0)
    criticality = clamp01(get_num(signal, :goal_criticality, 0.5))

    (0.45 * failure_rate + 0.25 * consistency_gap + 0.15 * staleness + 0.15 * criticality)
    |> clamp01()
  end

  # -- decision policy ---------------------------------------------------------

  defp pick_decision(coverage, uncertainty, risk, thresholds) do
    cond do
      coverage >= t(thresholds, :act_coverage) and
        uncertainty <= t(thresholds, :act_max_uncertainty) and
          risk <= t(thresholds, :act_max_risk) ->
        :act

      coverage >= t(thresholds, :learn_coverage) and
        uncertainty <= t(thresholds, :learn_max_uncertainty) and
          risk <= t(thresholds, :learn_max_risk) ->
        :learn

      true ->
        :escalate
    end
  end

  defp decision_confidence(:act, coverage, uncertainty, risk) do
    mean([coverage, 1.0 - uncertainty, 1.0 - risk]) |> clamp01()
  end

  defp decision_confidence(:learn, coverage, uncertainty, _risk) do
    clamp01(0.6 * coverage + 0.4 * (1.0 - uncertainty))
  end

  defp decision_confidence(:escalate, _coverage, uncertainty, risk) do
    max(uncertainty, risk) |> clamp01()
  end

  # -- rationale + diagnostics -------------------------------------------------

  defp rationale(decision, coverage, uncertainty, risk, components, thresholds) do
    [
      "coverage=#{fmt(coverage)} uncertainty=#{fmt(uncertainty)} risk=#{fmt(risk)} decision=#{decision}",
      "semantic=#{fmt(components.semantic_coverage)} consistency=#{fmt(components.consistency)} freshness=#{fmt(components.freshness)} graph_support=#{fmt(components.graph_support)} outcomes=#{fmt(components.outcome_reliability)}",
      "thresholds: act(cov>=#{fmt(t(thresholds, :act_coverage))}, unc<=#{fmt(t(thresholds, :act_max_uncertainty))}, risk<=#{fmt(t(thresholds, :act_max_risk))}) learn(cov>=#{fmt(t(thresholds, :learn_coverage))}, unc<=#{fmt(t(thresholds, :learn_max_uncertainty))}, risk<=#{fmt(t(thresholds, :learn_max_risk))})"
    ]
  end

  defp diagnostics(signal, components, opts) do
    node_scores =
      signal
      |> Map.get(:retrieved_nodes, [])
      |> Enum.map(&node_score/1)
      |> Enum.sort(:desc)

    %{
      node_count: length(Map.get(signal, :retrieved_nodes, [])),
      outcome_count: length(Map.get(signal, :outcomes, [])),
      contradiction_count: contradiction_count(signal),
      known_unknowns: clamp01(get_num(signal, :known_unknowns, 0.0)),
      goal_criticality: clamp01(get_num(signal, :goal_criticality, 0.5)),
      top_node_scores: Enum.take(node_scores, Keyword.get(opts, :top_k, 8)),
      component_weights: @default_weights,
      component_values: components
    }
  end

  # -- normalization helpers ---------------------------------------------------

  defp normalize_signal(signal) do
    signal =
      Enum.reduce(signal, %{}, fn
        {k, v}, acc when is_atom(k) ->
          Map.put(acc, k, v)

        {k, v}, acc when is_binary(k) ->
          atom_key = Map.get(@known_signal_keys, k, nil)
          if is_atom(atom_key), do: Map.put(acc, atom_key, v), else: acc

        _, acc ->
          acc
      end)

    signal
    |> Map.update(:retrieved_nodes, [], fn nodes -> if is_list(nodes), do: nodes, else: [] end)
    |> Map.update(:outcomes, [], fn outcomes -> if is_list(outcomes), do: outcomes, else: [] end)
  end

  # -- primitives --------------------------------------------------------------

  defp node_score(node) when is_map(node) do
    explicit = get_num(node, :score, nil)

    score =
      cond do
        is_number(explicit) ->
          explicit * 1.0

        true ->
          confidence = clamp01(get_num(node, :confidence, 0.5))
          similarity = clamp01(get_num(node, :similarity, 0.5))
          confidence * similarity
      end

    clamp01(score)
  end

  defp outcome_reliability(outcome) when is_map(outcome) do
    status = normalize_status(get_val(outcome, :status, :failure))
    confidence = clamp01(get_num(outcome, :confidence, 0.5))

    base =
      case status do
        :success -> 1.0
        :partial_success -> 0.75
        :failure -> 0.25
        :timeout -> 0.10
      end

    clamp01(base * confidence + (1.0 - confidence) * 0.5)
  end

  defp outcome_conflicting_weight(outcome) when is_map(outcome) do
    status = normalize_status(get_val(outcome, :status, :failure))
    confidence = clamp01(get_num(outcome, :confidence, 0.5))

    case status do
      :failure -> confidence
      :timeout -> 0.7 * confidence
      _ -> 0.0
    end
  end

  defp failure_risk(outcome) when is_map(outcome) do
    status = normalize_status(get_val(outcome, :status, :failure))
    confidence = clamp01(get_num(outcome, :confidence, 0.5))

    case status do
      :success -> 0.0
      :partial_success -> 0.35 * confidence
      :failure -> 1.0 * confidence
      :timeout -> 0.8 * confidence
    end
  end

  defp contradiction_count(signal) do
    contradictions = Map.get(signal, :contradictions, 0)

    cond do
      is_integer(contradictions) and contradictions >= 0 ->
        contradictions

      is_list(contradictions) ->
        length(contradictions)

      true ->
        0
    end
  end

  defp freshness_from_timestamp(nil, _now, _half_life), do: 0.5

  defp freshness_from_timestamp(timestamp, now, half_life_hours) do
    age_hours = max(DateTime.diff(now, timestamp, :second), 0) / 3600.0

    :math.exp(-age_hours / max(half_life_hours * 1.0, 1.0))
    |> clamp01()
  end

  defp node_timestamp(node) when is_map(node) do
    updated = get_val(node, :updated_at, nil)
    created = get_val(node, :created_at, nil)
    parse_datetime(updated) || parse_datetime(created)
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp normalize_status(status) when status in [:success, :partial_success, :failure, :timeout],
    do: status

  defp normalize_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "success" -> :success
      "partial_success" -> :partial_success
      "failure" -> :failure
      "timeout" -> :timeout
      _ -> :failure
    end
  end

  defp normalize_status(_), do: :failure

  defp weighted_sum(components, weights) do
    components
    |> Enum.reduce(0.0, fn {key, value}, acc ->
      acc + value * Map.get(weights, key, 0.0)
    end)
    |> clamp01()
  end

  defp merge_numeric_map(given, defaults) when is_map(given) and is_map(defaults) do
    Enum.reduce(defaults, %{}, fn {k, default_v}, acc ->
      v = Map.get(given, k, default_v)
      Map.put(acc, k, normalize_num(v, default_v))
    end)
  end

  defp merge_numeric_map(_given, defaults), do: defaults

  defp get_num(map, key, default) when is_map(map) do
    value = get_val(map, key, default)

    cond do
      is_integer(value) ->
        value * 1.0

      is_float(value) ->
        value

      is_binary(value) ->
        case Float.parse(String.trim(value)) do
          {f, _} -> f
          :error -> default
        end

      true ->
        default
    end
  end

  defp get_val(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_num(value, _fallback) when is_integer(value), do: value * 1.0
  defp normalize_num(value, _fallback) when is_float(value), do: value
  defp normalize_num(_value, fallback), do: fallback

  defp saturation(value, target) when is_number(value) and is_number(target) do
    value_f = max(value * 1.0, 0.0)
    target_f = max(target * 1.0, 1.0)
    1.0 - :math.exp(-value_f / target_f)
  end

  defp t(thresholds, key), do: Map.get(thresholds, key, Map.get(@default_thresholds, key, 0.0))

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / max(length(values) * 1.0, 1.0)

  defp mean_or_zero(values) when is_list(values), do: mean(values)
  defp mean_or_zero(_), do: 0.0

  defp stddev([]), do: 0.0

  defp stddev(values) do
    m = mean(values)

    variance =
      values
      |> Enum.map(fn v -> (v - m) * (v - m) end)
      |> mean()

    :math.sqrt(max(variance, 0.0))
    |> clamp01()
  end

  defp fmt(value) do
    :erlang.float_to_binary(clamp01(value), decimals: 3)
  end

  defp clamp01(v) when is_integer(v), do: clamp01(v * 1.0)
  defp clamp01(v) when is_float(v) and v < 0.0, do: 0.0
  defp clamp01(v) when is_float(v) and v > 1.0, do: 1.0
  defp clamp01(v) when is_float(v), do: v
  defp clamp01(_), do: 0.0
end
