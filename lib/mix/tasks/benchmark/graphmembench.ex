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

    if tier != 3 do
      Mix.raise("Only tier 3 is implemented. Got --tier #{tier}.")
    end

    Helpers.ensure_started()

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════════╗
    ║  GraphMemBench v2 — Tier #{tier} (κ=1 simple-cycle)              ║
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
      "Plan: #{length(plan.sccs)} SCCs, " <>
        "#{length(plan.distractor_chains)} distractor chains, " <>
        "#{length(plan.questions)} questions"
    )

    # Phase 1: Ingest nodes
    Mix.shell().info("\n━━━ Phase 1: Ingesting synthetic graph ━━━")

    {ingest_us, %{key_to_id: key_to_id, gold_scc_ids: gold_scc_ids}} =
      Helpers.timed(fn -> ingest_plan(plan) end)

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
          evaluate_question(q, skip_topology, gold_scc_ids)
        end)
      end)

    Mix.shell().info("  Eval done in #{div(eval_us, 1000)} ms")

    # Phase 3: Aggregate metrics
    metrics = aggregate_metrics(per_question, gold_scc_ids)

    result = %{
      benchmark: "graphmembench:T#{tier}",
      topology_mode: topology_mode,
      skip_topology: skip_topology,
      seed: seed,
      sanity: sanity,
      distractors: distractors,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      plan: %{
        scc_count: length(plan.sccs),
        distractor_chain_count: length(plan.distractor_chains),
        question_count: length(questions)
      },
      metrics: metrics,
      ingest_ms: div(ingest_us, 1000),
      eval_ms: div(eval_us, 1000)
    }

    filename = "graphmembench_T#{tier}_topology_#{topology_mode}"
    path = Helpers.write_results(filename, result)

    Mix.shell().info("""

    === GraphMemBench T#{tier} Complete (topology=#{topology_mode}) ===
    kappa_recall:         #{fmt(metrics.kappa_recall)}
    kappa_precision:      #{fmt(metrics.kappa_precision)}
    scc_membership_f1:    #{fmt(metrics.scc_membership_f1)}
    routing_precision:    #{fmt(metrics.routing_precision)}
    cycle_root_accuracy:  #{fmt(metrics.cycle_root_accuracy)}
    latency p50/p95:      #{metrics.latency_ms_p50}ms / #{metrics.latency_ms_p95}ms
    Output:               #{path}
    """)
  end

  # ---------- Ingestion ----------

  defp ingest_plan(plan) do
    # Flatten all nodes from SCCs + distractors
    all_nodes =
      Enum.flat_map(plan.sccs, & &1.nodes) ++
        Enum.flat_map(plan.distractor_chains, & &1.nodes)

    # Store nodes; capture key → node_id mapping
    key_to_id =
      Enum.reduce(all_nodes, %{}, fn n, acc ->
        stored =
          Graphonomous.store_node(%{
            content: n.content,
            node_type: "semantic",
            confidence: 0.9,
            source: "graphmembench:T3:gen",
            metadata: %{
              "benchmark" => "graphmembench",
              "tier" => 3,
              "scc_id" => n.scc_id,
              "role" => n.role,
              "key" => n.key,
              "domain" => n.domain
            }
          })

        Map.put(acc, n.key, stored.id)
      end)

    # Create edges for SCC cycles
    Enum.each(plan.sccs, fn scc ->
      Enum.each(scc.edges, fn e ->
        Graphonomous.link_nodes(key_to_id[e.source_key], key_to_id[e.target_key], %{
          edge_type: e.edge_type,
          weight: 0.9
        })
      end)
    end)

    # Create edges for distractor chains
    Enum.each(plan.distractor_chains, fn chain ->
      Enum.each(chain.edges, fn e ->
        Graphonomous.link_nodes(key_to_id[e.source_key], key_to_id[e.target_key], %{
          edge_type: e.edge_type,
          weight: 0.8
        })
      end)
    end)

    # Build gold_scc_ids: scc_id → MapSet of node_ids (used for detection matching)
    gold_scc_ids =
      Enum.reduce(plan.sccs, %{}, fn scc, acc ->
        ids = scc.nodes |> Enum.map(&key_to_id[&1.key]) |> MapSet.new()
        Map.put(acc, scc.scc_id, ids)
      end)

    %{key_to_id: key_to_id, gold_scc_ids: gold_scc_ids}
  end

  defp edge_count(plan) do
    Enum.sum(Enum.map(plan.sccs, &length(&1.edges))) +
      Enum.sum(Enum.map(plan.distractor_chains, &length(&1.edges)))
  end

  # ---------- Evaluation ----------

  defp evaluate_question(q, skip_topology, gold_scc_ids) do
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

    topology = Map.get(retrieval, :topology, %{}) || %{}
    detected_sccs = Map.get(topology, :sccs, []) || []
    max_kappa = Map.get(topology, :max_kappa, 0) || 0
    routing = Map.get(topology, :routing, :fast)
    routing_str = to_string(routing)

    # Match detected SCCs against gold SCCs (a detected SCC matches a gold SCC
    # iff the gold SCC's node-id set is a subset of the detected node set).
    detected_id_sets =
      Enum.map(detected_sccs, fn scc ->
        scc |> Map.get(:nodes, []) |> MapSet.new()
      end)

    gold_scc = q.gold[:scc_id]
    gold_ids = Map.get(gold_scc_ids, gold_scc, MapSet.new())

    gold_detected? =
      Enum.any?(detected_id_sets, fn d -> MapSet.subset?(gold_ids, d) end)

    # A detected SCC is "correct" if it covers any gold SCC's node set
    gold_id_sets = Map.values(gold_scc_ids)

    detected_correct_count =
      Enum.count(detected_id_sets, fn d ->
        Enum.any?(gold_id_sets, fn g -> MapSet.subset?(g, d) end)
      end)

    routing_correct? =
      q.gold[:expected_kappa_min] >= 1 and routing_str == "deliberate" and max_kappa >= 1

    membership_predicted =
      if max_kappa >= 1 and gold_detected?, do: true, else: false

    membership_gold = Map.get(q.gold, :membership_answer)

    %{
      q_id: q.q_id,
      pattern: q.pattern,
      gold_scc_id: gold_scc,
      latency_ms: div(retrieval_us, 1000),
      timed_out: timed_out?,
      detected_scc_count: length(detected_sccs),
      detected_correct_count: detected_correct_count,
      max_kappa: max_kappa,
      routing: routing_str,
      gold_detected: gold_detected?,
      routing_correct: routing_correct?,
      membership_predicted: membership_predicted,
      membership_gold: membership_gold
    }
  end

  # ---------- Metrics aggregation ----------

  defp aggregate_metrics(per_question, _gold_scc_ids) do
    n = length(per_question)

    # kappa_recall: mean over questions of "was gold SCC detected?"
    kappa_recall = mean(per_question, fn r -> if r.gold_detected, do: 1.0, else: 0.0 end)

    # kappa_precision: micro-average — correct_detections / total_detections
    total_detected = Enum.sum(Enum.map(per_question, & &1.detected_scc_count))
    total_correct = Enum.sum(Enum.map(per_question, & &1.detected_correct_count))

    kappa_precision =
      if total_detected == 0, do: 0.0, else: total_correct / total_detected

    # routing_precision: among questions with expected_kappa_min≥1, fraction
    # that got routing=deliberate AND max_kappa≥1 (all questions here are κ-expected)
    routing_precision = mean(per_question, fn r -> if r.routing_correct, do: 1.0, else: 0.0 end)

    # scc_membership_f1: binary F1 over membership pattern questions
    memb = Enum.filter(per_question, fn r -> r.pattern == "scc_membership" end)
    scc_membership_f1 = binary_f1(memb)

    # cycle_root_accuracy: root-paradox questions where routing was deliberate
    roots = Enum.filter(per_question, fn r -> r.pattern == "cycle_root_paradox" end)

    cycle_root_accuracy =
      mean(roots, fn r -> if r.routing_correct, do: 1.0, else: 0.0 end)

    # latency percentiles
    latencies = per_question |> Enum.map(& &1.latency_ms) |> Enum.sort()
    p50 = percentile(latencies, 0.50)
    p95 = percentile(latencies, 0.95)

    %{
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
