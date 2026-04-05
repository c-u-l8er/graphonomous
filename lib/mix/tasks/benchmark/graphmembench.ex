defmodule Mix.Tasks.Benchmark.Graphmembench do
  @moduledoc """
  GraphMemBench v2 — κ-sensitive synthetic benchmark for Graphonomous.

  Currently implements **Tier 3** (simple-cycle, κ=1): disjoint 3-5 node SCCs
  with known ground truth. Each cycle is a directed loop A→B→...→A stored as
  semantic nodes with causal edges. Questions probe whether the retriever
  returns topology annotations (SCCs, max_kappa, routing=deliberate) and
  whether membership/root-paradox behavior matches the cyclic ground truth.

  Runs topology ON and OFF side-by-side is expected — use `--topology on|off`
  to toggle. The validation gate for T3 is ≥3pp delta on any of the κ metrics.

  Usage:
      mix benchmark.graphmembench --tier 3 [--sanity] [--distractors N]
                                  [--seed N] [--topology on|off]
                                  [--purge true|false] [--limit N]

  Metrics (reported in JSON):
    * `kappa_recall`            — fraction of gold SCCs detected in retrieval topology
    * `kappa_precision`         — fraction of detected SCCs that match a gold SCC
    * `scc_membership_f1`       — F1 over binary cyclic-membership answers
    * `routing_precision`       — fraction of κ>0 queries that got routing=deliberate
    * `cycle_root_accuracy`     — fraction of root-paradox queries answered "cyclic"
    * `latency_ms_p50/p95`      — retrieval latency distribution
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers
  alias Graphonomous.Benchmarks.GraphMemBenchGen

  @shortdoc "Run GraphMemBench v2 (T3 simple-cycle κ=1 by default)"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          tier: :integer,
          sanity: :boolean,
          distractors: :integer,
          seed: :integer,
          topology: :string,
          purge: :boolean,
          limit: :integer,
          dump_fixtures: :boolean
        ]
      )

    tier = Keyword.get(opts, :tier, 3)
    sanity = Keyword.get(opts, :sanity, false)
    distractors = Keyword.get(opts, :distractors, 0)
    seed = Keyword.get(opts, :seed, 42)
    topology_mode = Keyword.get(opts, :topology, "on")
    purge = Keyword.get(opts, :purge, true)
    limit = Keyword.get(opts, :limit)
    dump_fixtures = Keyword.get(opts, :dump_fixtures, true)

    skip_topology =
      case topology_mode do
        "on" -> false
        "off" -> true
        other -> Mix.raise("--topology must be 'on' or 'off', got: #{inspect(other)}")
      end

    if tier not in [3, 4, 5] do
      Mix.raise("Only tiers 3, 4, and 5 are implemented. Got --tier #{tier}.")
    end

    Helpers.ensure_started()

    tier_label =
      case tier do
        3 -> "κ=1 simple-cycle"
        4 -> "κ≥2 multi-SCC fault-line"
        5 -> "κ=0-1 adversarial contradiction"
      end

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════════╗
    ║  GraphMemBench v2 — Tier #{tier} (#{String.pad_trailing(tier_label, 33)})║
    ║                                                          ║
    ║  Topology:     #{String.pad_trailing(topology_mode, 42)}║
    ║  Sanity:       #{String.pad_trailing(to_string(sanity), 42)}║
    ║  Distractors:  #{String.pad_trailing(to_string(distractors), 42)}║
    ║  Seed:         #{String.pad_trailing(to_string(seed), 42)}║
    ╚══════════════════════════════════════════════════════════╝
    """)

    if purge do
      Mix.shell().info("Purging graph for clean benchmark...")
      Helpers.purge_graph()
    end

    # Generate deterministic plan
    plan = GraphMemBenchGen.generate(tier, seed: seed, sanity: sanity, distractors: distractors)

    if dump_fixtures do
      root = Path.expand("../../../../", __DIR__)
      path = GraphMemBenchGen.dump_fixtures(plan, root)
      Mix.shell().info("Fixtures written to #{path}")
    end

    Mix.shell().info(
      "Plan: #{group_count(plan)} groups, " <>
        "#{length(plan.distractor_chains)} distractor chains, " <>
        "#{length(plan.questions)} questions"
    )

    # Phase 1: Ingest nodes
    Mix.shell().info("\n━━━ Phase 1: Ingesting synthetic graph ━━━")

    {ingest_us, %{key_to_id: key_to_id, gold_groups: gold_groups}} =
      Helpers.timed(fn -> ingest_plan(plan) end)

    fault_line_map = fault_line_map_for_plan(plan, key_to_id)

    Mix.shell().info(
      "  Ingested #{map_size(key_to_id)} nodes, " <>
        "#{edge_count(plan)} edges in #{div(ingest_us, 1000)} ms"
    )

    # Phase 2: Evaluate questions
    Mix.shell().info("\n━━━ Phase 2: Evaluating #{length(plan.questions)} questions ━━━")

    questions = if limit, do: Enum.take(plan.questions, limit), else: plan.questions

    {eval_us, per_question} =
      Helpers.timed(fn ->
        questions
        |> Enum.with_index(1)
        |> Enum.map(fn {q, idx} ->
          if rem(idx, 10) == 0, do: Mix.shell().info("  #{idx}/#{length(questions)}")
          evaluate_question(q, skip_topology, gold_groups, key_to_id, fault_line_map)
        end)
      end)

    Mix.shell().info("  Eval done in #{div(eval_us, 1000)} ms")

    # Phase 3: Aggregate metrics
    metrics = aggregate_metrics(per_question, tier)

    result = %{
      benchmark: "graphmembench:T#{tier}",
      topology_mode: topology_mode,
      skip_topology: skip_topology,
      seed: seed,
      sanity: sanity,
      distractors: distractors,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      plan: %{
        group_count: group_count(plan),
        distractor_chain_count: length(plan.distractor_chains),
        question_count: length(questions)
      },
      metrics: metrics,
      ingest_ms: div(ingest_us, 1000),
      eval_ms: div(eval_us, 1000)
    }

    filename = "graphmembench_T#{tier}_topology_#{topology_mode}"
    path = Helpers.write_results(filename, result)

    Mix.shell().info(summary_text(tier, topology_mode, metrics, path))
  end

  defp summary_text(3, mode, m, path) do
    """

    === GraphMemBench T3 Complete (topology=#{mode}) ===
    kappa_recall:         #{fmt(m.kappa_recall)}
    kappa_precision:      #{fmt(m.kappa_precision)}
    scc_membership_f1:    #{fmt(m.scc_membership_f1)}
    routing_precision:    #{fmt(m.routing_precision)}
    cycle_root_accuracy:  #{fmt(m.cycle_root_accuracy)}
    latency p50/p95:      #{m.latency_ms_p50}ms / #{m.latency_ms_p95}ms
    Output:               #{path}
    """
  end

  defp summary_text(4, mode, m, path) do
    """

    === GraphMemBench T4 Complete (topology=#{mode}) ===
    kappa_recall:              #{fmt(m.kappa_recall)}
    kappa_precision:           #{fmt(m.kappa_precision)}
    scc_membership_f1:         #{fmt(m.scc_membership_f1)}
    routing_precision:         #{fmt(m.routing_precision)}
    faultline_mrr:             #{fmt(m.faultline_mrr)}
    faultline_node_recall@10:  #{fmt(m.faultline_node_recall_at_10)}
    max_observed_kappa:        #{m.max_observed_kappa}
    latency p50/p95:           #{m.latency_ms_p50}ms / #{m.latency_ms_p95}ms
    Output:                    #{path}
    """
  end

  defp summary_text(5, mode, m, path) do
    """

    === GraphMemBench T5 Complete (topology=#{mode}) ===
    kappa_recall:              #{fmt(m.kappa_recall)}         (κ=1 subset only)
    kappa_precision:           #{fmt(m.kappa_precision)}
    scc_membership_f1:         #{fmt(m.scc_membership_f1)}
    routing_precision:         #{fmt(m.routing_precision)}    (over κ>0 questions)
    fresh_belief_top1_rate:    #{fmt(m.fresh_belief_top1_rate)}
    fresh_belief_mrr:          #{fmt(m.fresh_belief_mrr)}
    belief_revision_rank_mean: #{fmt(m.belief_revision_rank_mean)}
    latency p50/p95:           #{m.latency_ms_p50}ms / #{m.latency_ms_p95}ms
    Output:                    #{path}
    """
  end

  defp group_count(%{sccs: sccs}) when is_list(sccs), do: length(sccs)
  defp group_count(%{contradiction_pairs: pairs}) when is_list(pairs), do: length(pairs)

  defp fault_line_map_for_plan(%{tier: 4} = plan, key_to_id) do
    Enum.reduce(plan.sccs, %{}, fn scc, acc ->
      ids =
        scc.fault_line_keys
        |> Enum.map(&Map.get(key_to_id, &1))
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      Map.put(acc, scc.scc_id, ids)
    end)
  end

  defp fault_line_map_for_plan(_plan, _key_to_id), do: %{}

  # ---------- Ingestion ----------

  defp ingest_plan(%{tier: 3} = plan) do
    # T3: SCCs of 3-5 nodes forming cycles. All nodes stored with conf 0.9.
    all_nodes =
      Enum.flat_map(plan.sccs, & &1.nodes) ++
        Enum.flat_map(plan.distractor_chains, & &1.nodes)

    key_to_id = store_nodes(all_nodes, 3, 0.9)
    create_edges(plan.sccs ++ plan.distractor_chains, key_to_id)

    gold_groups =
      Enum.reduce(plan.sccs, %{}, fn scc, acc ->
        ids = scc.nodes |> Enum.map(&key_to_id[&1.key]) |> MapSet.new()
        Map.put(acc, scc.scc_id, %{node_ids: ids, kappa: 1})
      end)

    %{key_to_id: key_to_id, gold_groups: gold_groups}
  end

  defp ingest_plan(%{tier: 4} = plan) do
    # T4: dense multi-SCC with chord edges producing κ≥2
    all_nodes =
      Enum.flat_map(plan.sccs, & &1.nodes) ++
        Enum.flat_map(plan.distractor_chains, & &1.nodes)

    key_to_id = store_nodes(all_nodes, 4, 0.9)
    create_edges(plan.sccs ++ plan.distractor_chains, key_to_id)

    gold_groups =
      Enum.reduce(plan.sccs, %{}, fn scc, acc ->
        ids = scc.nodes |> Enum.map(&key_to_id[&1.key]) |> MapSet.new()
        Map.put(acc, scc.scc_id, %{node_ids: ids, kappa: max(scc.observed_kappa, 1)})
      end)

    %{key_to_id: key_to_id, gold_groups: gold_groups}
  end

  defp ingest_plan(%{tier: 5} = plan) do
    # T5: contradiction pairs. Each node carries its own confidence (old=0.5, new=0.9).
    all_pair_nodes = Enum.flat_map(plan.contradiction_pairs, & &1.nodes)
    distractor_nodes = Enum.flat_map(plan.distractor_chains, & &1.nodes)

    key_to_id_pairs =
      Enum.reduce(all_pair_nodes, %{}, fn n, acc ->
        stored =
          Graphonomous.store_node(%{
            content: n.content,
            node_type: "episodic",
            confidence: n.confidence,
            source: "graphmembench:T5:gen",
            metadata: %{
              "benchmark" => "graphmembench",
              "tier" => 5,
              "pair_id" => n.pair_id,
              "role" => to_string(n.role),
              "key" => n.key,
              "subject" => n.subject
            }
          })

        Map.put(acc, n.key, stored.id)
      end)

    key_to_id_dist = store_nodes(distractor_nodes, 5, 0.7)
    key_to_id = Map.merge(key_to_id_pairs, key_to_id_dist)

    create_edges(plan.contradiction_pairs ++ plan.distractor_chains, key_to_id)

    gold_groups =
      Enum.reduce(plan.contradiction_pairs, %{}, fn pair, acc ->
        ids = pair.nodes |> Enum.map(&key_to_id[&1.key]) |> MapSet.new()
        kappa = if pair.cyclic?, do: 1, else: 0
        Map.put(acc, pair.pair_id, %{node_ids: ids, kappa: kappa})
      end)

    %{key_to_id: key_to_id, gold_groups: gold_groups}
  end

  defp store_nodes(nodes, tier, confidence) do
    Enum.reduce(nodes, %{}, fn n, acc ->
      stored =
        Graphonomous.store_node(%{
          content: n.content,
          node_type: "semantic",
          confidence: confidence,
          source: "graphmembench:T#{tier}:gen",
          metadata: %{
            "benchmark" => "graphmembench",
            "tier" => tier,
            "scc_id" => Map.get(n, :scc_id),
            "role" => to_string(Map.get(n, :role)),
            "key" => n.key,
            "domain" => Map.get(n, :domain)
          }
        })

      Map.put(acc, n.key, stored.id)
    end)
  end

  defp create_edges(groups, key_to_id) do
    Enum.each(groups, fn group ->
      edges = Map.get(group, :edges, [])

      Enum.each(edges, fn e ->
        Graphonomous.link_nodes(key_to_id[e.source_key], key_to_id[e.target_key], %{
          edge_type: e.edge_type,
          weight: 0.9
        })
      end)
    end)
  end

  defp edge_count(%{tier: 3} = plan) do
    Enum.sum(Enum.map(plan.sccs, &length(&1.edges))) +
      Enum.sum(Enum.map(plan.distractor_chains, &length(&1.edges)))
  end

  defp edge_count(%{tier: 4} = plan) do
    Enum.sum(Enum.map(plan.sccs, &length(&1.edges))) +
      Enum.sum(Enum.map(plan.distractor_chains, &length(&1.edges)))
  end

  defp edge_count(%{tier: 5} = plan) do
    Enum.sum(Enum.map(plan.contradiction_pairs, &length(&1.edges))) +
      Enum.sum(Enum.map(plan.distractor_chains, &length(&1.edges)))
  end

  # ---------- Evaluation ----------

  defp evaluate_question(q, skip_topology, gold_groups, key_to_id, fault_line_map) do
    {retrieval_us, retrieval} =
      Helpers.timed(fn ->
        Graphonomous.retrieve_context(q.query,
          similarity_limit: 20,
          final_limit: 30,
          expansion_hops: 1,
          neighbors_per_node: 8,
          skip_topology: skip_topology
        )
      end)

    {retrieval, timed_out?} =
      case retrieval do
        {:error, _} -> {%{results: [], topology: %{}}, true}
        map when is_map(map) -> {map, false}
      end

    results = Map.get(retrieval, :results, [])
    topology = Map.get(retrieval, :topology, %{}) || %{}
    detected_sccs = Map.get(topology, :sccs, []) || []
    max_kappa = Map.get(topology, :max_kappa, 0) || 0
    routing_str = topology |> Map.get(:routing, :fast) |> to_string()

    detected_id_sets =
      Enum.map(detected_sccs, fn scc -> scc |> Map.get(:nodes, []) |> MapSet.new() end)

    # Gold group this question is about (T3: scc_id; T5: pair_id)
    group_id = q.gold[:scc_id] || q.gold[:pair_id]
    gold_group = Map.get(gold_groups, group_id, %{node_ids: MapSet.new(), kappa: 0})
    gold_ids = gold_group.node_ids
    expected_kappa = q.gold[:expected_kappa_min] || 0

    gold_detected? =
      MapSet.size(gold_ids) > 0 and
        Enum.any?(detected_id_sets, fn d -> MapSet.subset?(gold_ids, d) end)

    # A detected SCC is "correct" if it covers any gold κ≥1 group
    gold_id_sets =
      gold_groups
      |> Enum.filter(fn {_, g} -> g.kappa >= 1 end)
      |> Enum.map(fn {_, g} -> g.node_ids end)

    detected_correct_count =
      Enum.count(detected_id_sets, fn d ->
        Enum.any?(gold_id_sets, fn g -> MapSet.subset?(g, d) end)
      end)

    routing_correct? =
      expected_kappa >= 1 and routing_str == "deliberate" and max_kappa >= 1

    membership_predicted =
      if max_kappa >= 1 and gold_detected?, do: true, else: false

    membership_gold = Map.get(q.gold, :membership_answer)

    # T5-specific: rank of expected_top1 node in results
    expected_top1_key = q.gold[:expected_top1_key]
    expected_top1_id = if expected_top1_key, do: key_to_id[expected_top1_key], else: nil

    result_ids = Enum.map(results, & &1.node_id)

    expected_top1_rank =
      if expected_top1_id do
        case Enum.find_index(result_ids, &(&1 == expected_top1_id)) do
          nil -> nil
          idx -> idx + 1
        end
      else
        nil
      end

    fresh_belief_top1? = expected_top1_rank == 1

    # T4-specific: rank of fault-line nodes in results
    fault_line_ids = Map.get(fault_line_map, group_id, MapSet.new())

    {faultline_first_rank, faultline_top10_count} =
      if MapSet.size(fault_line_ids) == 0 do
        {nil, 0}
      else
        ranked_hits =
          result_ids
          |> Enum.with_index(1)
          |> Enum.filter(fn {id, _idx} -> MapSet.member?(fault_line_ids, id) end)

        first_rank =
          ranked_hits
          |> List.first()
          |> case do
            nil -> nil
            {_id, idx} -> idx
          end

        top10 =
          Enum.count(ranked_hits, fn {_id, idx} -> idx <= 10 end)

        {first_rank, top10}
      end

    fault_line_size = MapSet.size(fault_line_ids)

    %{
      q_id: q.q_id,
      pattern: q.pattern,
      group_id: group_id,
      latency_ms: div(retrieval_us, 1000),
      timed_out: timed_out?,
      detected_scc_count: length(detected_sccs),
      detected_correct_count: detected_correct_count,
      max_kappa: max_kappa,
      routing: routing_str,
      expected_kappa_min: expected_kappa,
      gold_detected: gold_detected?,
      routing_correct: routing_correct?,
      membership_predicted: membership_predicted,
      membership_gold: membership_gold,
      expected_top1_rank: expected_top1_rank,
      fresh_belief_top1: fresh_belief_top1?,
      faultline_first_rank: faultline_first_rank,
      faultline_top10_count: faultline_top10_count,
      fault_line_size: fault_line_size
    }
  end

  # ---------- Metrics aggregation ----------

  defp aggregate_metrics(per_question, tier) do
    n = length(per_question)

    # Common κ metrics: only count over κ-expected (κ≥1) questions
    kappa_expected = Enum.filter(per_question, fn r -> r.expected_kappa_min >= 1 end)

    kappa_recall =
      mean(kappa_expected, fn r -> if r.gold_detected, do: 1.0, else: 0.0 end)

    total_detected = Enum.sum(Enum.map(per_question, & &1.detected_scc_count))
    total_correct = Enum.sum(Enum.map(per_question, & &1.detected_correct_count))

    kappa_precision =
      if total_detected == 0, do: 0.0, else: total_correct / total_detected

    routing_precision =
      mean(kappa_expected, fn r -> if r.routing_correct, do: 1.0, else: 0.0 end)

    memb = Enum.filter(per_question, fn r -> r.pattern == "scc_membership" end)
    scc_membership_f1 = binary_f1(memb)

    roots = Enum.filter(per_question, fn r -> r.pattern == "cycle_root_paradox" end)

    cycle_root_accuracy =
      mean(roots, fn r -> if r.routing_correct, do: 1.0, else: 0.0 end)

    latencies = per_question |> Enum.map(& &1.latency_ms) |> Enum.sort()
    p50 = percentile(latencies, 0.50)
    p95 = percentile(latencies, 0.95)

    base = %{
      kappa_recall: kappa_recall,
      kappa_precision: kappa_precision,
      scc_membership_f1: scc_membership_f1,
      routing_precision: routing_precision,
      cycle_root_accuracy: cycle_root_accuracy,
      latency_ms_p50: p50,
      latency_ms_p95: p95,
      question_count: n,
      timed_out_count: Enum.count(per_question, & &1.timed_out),
      per_question: per_question
    }

    cond do
      tier == 4 -> Map.merge(base, t4_extra_metrics(per_question))
      tier == 5 -> Map.merge(base, t5_extra_metrics(per_question))
      true -> base
    end
  end

  defp t4_extra_metrics(per_question) do
    faultline_qs =
      Enum.filter(per_question, fn r -> r.pattern == "faultline_spanning" end)

    faultline_mrr =
      mean(faultline_qs, fn r ->
        case r.faultline_first_rank do
          nil -> 0.0
          rank -> 1.0 / rank
        end
      end)

    faultline_node_recall_at_10 =
      mean(faultline_qs, fn r ->
        if r.fault_line_size == 0 do
          0.0
        else
          r.faultline_top10_count / r.fault_line_size
        end
      end)

    max_observed_kappa =
      per_question
      |> Enum.map(& &1.max_kappa)
      |> case do
        [] -> 0
        list -> Enum.max(list)
      end

    %{
      faultline_mrr: faultline_mrr,
      faultline_node_recall_at_10: faultline_node_recall_at_10,
      max_observed_kappa: max_observed_kappa
    }
  end

  defp t5_extra_metrics(per_question) do
    # Belief revision: over contradiction_resolution questions
    resolution_qs =
      Enum.filter(per_question, fn r -> r.pattern == "contradiction_resolution" end)

    ranked = Enum.filter(resolution_qs, fn r -> not is_nil(r.expected_top1_rank) end)

    fresh_belief_top1_rate =
      mean(resolution_qs, fn r -> if r.fresh_belief_top1, do: 1.0, else: 0.0 end)

    fresh_belief_mrr =
      mean(resolution_qs, fn r ->
        case r.expected_top1_rank do
          nil -> 0.0
          rank -> 1.0 / rank
        end
      end)

    belief_revision_rank_mean =
      if ranked == [] do
        nil
      else
        ranks = Enum.map(ranked, & &1.expected_top1_rank)
        Enum.sum(ranks) / length(ranks)
      end

    %{
      fresh_belief_top1_rate: fresh_belief_top1_rate,
      fresh_belief_mrr: fresh_belief_mrr,
      belief_revision_rank_mean: belief_revision_rank_mean
    }
  end

  defp mean([], _fun), do: 0.0

  defp mean(list, fun) do
    vals = Enum.map(list, fun)
    Enum.sum(vals) / length(vals)
  end

  defp binary_f1([]), do: 0.0

  defp binary_f1(list) do
    {tp, fp, fn_} =
      Enum.reduce(list, {0, 0, 0}, fn r, {tp, fp, fn_} ->
        cond do
          r.membership_gold == true and r.membership_predicted == true -> {tp + 1, fp, fn_}
          r.membership_gold == false and r.membership_predicted == true -> {tp, fp + 1, fn_}
          r.membership_gold == true and r.membership_predicted == false -> {tp, fp, fn_ + 1}
          true -> {tp, fp, fn_}
        end
      end)

    precision = if tp + fp == 0, do: 0.0, else: tp / (tp + fp)
    recall = if tp + fn_ == 0, do: 0.0, else: tp / (tp + fn_)
    if precision + recall == 0, do: 0.0, else: 2 * precision * recall / (precision + recall)
  end

  defp percentile([], _p), do: 0

  defp percentile(sorted, p) when is_list(sorted) do
    n = length(sorted)
    idx = min(n - 1, trunc(Float.floor(p * n)))
    Enum.at(sorted, idx)
  end

  defp fmt(f) when is_float(f), do: :io_lib.format("~.4f", [f]) |> IO.iodata_to_binary()
  defp fmt(x), do: inspect(x)
end
