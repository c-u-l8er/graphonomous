defmodule Mix.Tasks.Benchmark.Consolidation do
  @moduledoc """
  OS-E001 Benchmark: Consolidation Behavior

  Measures how the consolidator handles the ingested corpus:
  - Confidence decay rates across multiple cycles
  - Pruning behavior (what gets removed and when)
  - Memory stability (do high-confidence nodes survive?)
  - Cycle timing and throughput

  Requires: `mix benchmark.ingest` to have been run first.

  Usage:
      mix benchmark.consolidation [--cycles 5]

  Options:
      --cycles   Number of consolidation cycles to run (default: 5)
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Benchmark consolidation behavior on [&] corpus"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [cycles: :integer])
    num_cycles = Keyword.get(opts, :cycles, 5)

    Helpers.ensure_started()

    Mix.shell().info("=== OS-E001 Benchmark: Consolidation ===")

    # Snapshot before
    before_snapshot = take_snapshot()

    Mix.shell().info(
      "Before: #{before_snapshot.node_count} nodes, avg confidence #{Float.round(before_snapshot.avg_confidence, 4)}"
    )

    # Run multiple consolidation cycles, measuring each
    cycle_results =
      Enum.map(1..num_cycles, fn i ->
        Mix.shell().info("  Cycle #{i}/#{num_cycles}...")

        {cycle_us, _} = Helpers.timed(fn -> Graphonomous.run_consolidation_now() end)

        # Wait for async consolidation to settle on large graphs
        Process.sleep(500)

        snapshot = take_snapshot()

        info =
          try do
            GenServer.call(Graphonomous.Consolidator, :info, 30_000)
          catch
            :exit, _ -> %{}
          end

        %{
          cycle: i,
          latency_us: cycle_us,
          node_count: snapshot.node_count,
          avg_confidence: Float.round(snapshot.avg_confidence, 6),
          min_confidence: Float.round(snapshot.min_confidence, 6),
          max_confidence: Float.round(snapshot.max_confidence, 6),
          confidence_stddev: Float.round(snapshot.confidence_stddev, 6),
          consolidator_cycle_count: Map.get(info, :cycle_count, 0)
        }
      end)

    # Snapshot after all cycles
    after_snapshot = take_snapshot()

    # Compute decay analysis
    confidence_trajectory =
      [before_snapshot.avg_confidence | Enum.map(cycle_results, & &1.avg_confidence)]

    decay_per_cycle =
      confidence_trajectory
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> Float.round(a - b, 6) end)

    # Test: inject nodes at varying confidence levels and see what survives
    Mix.shell().info("Running survival analysis...")
    {survival_us, survival_results} = run_survival_analysis()

    results = %{
      benchmark: "OS-E001:consolidation",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      config: %{
        cycles_run: num_cycles,
        decay_rate: Application.get_env(:graphonomous, :consolidator_decay_rate, 0.02),
        prune_threshold: Application.get_env(:graphonomous, :consolidator_prune_threshold, 0.1),
        merge_similarity: Application.get_env(:graphonomous, :consolidator_merge_similarity, 0.95)
      },
      before: before_snapshot,
      after: after_snapshot,
      cycles: cycle_results,
      decay_analysis: %{
        confidence_trajectory: confidence_trajectory,
        decay_per_cycle: decay_per_cycle,
        mean_decay_per_cycle: safe_mean(decay_per_cycle),
        total_confidence_loss:
          Float.round(before_snapshot.avg_confidence - after_snapshot.avg_confidence, 6),
        nodes_pruned: before_snapshot.node_count - after_snapshot.node_count,
        survival_rate:
          if(before_snapshot.node_count > 0,
            do: Float.round(after_snapshot.node_count / before_snapshot.node_count, 4),
            else: 1.0
          )
      },
      survival_analysis: Map.merge(survival_results, %{latency_us: survival_us}),
      performance: %{
        total_us: Enum.sum(Enum.map(cycle_results, & &1.latency_us)),
        mean_cycle_us: safe_mean(Enum.map(cycle_results, & &1.latency_us)) |> round(),
        throughput_nodes_per_cycle_per_sec:
          if(cycle_results != [],
            do:
              Float.round(
                before_snapshot.node_count /
                  max(safe_mean(Enum.map(cycle_results, & &1.latency_us)) / 1_000_000, 0.001),
                1
              ),
            else: 0
          )
      }
    }

    path = Helpers.write_results("consolidation", results)

    Mix.shell().info("""

    === Consolidation Benchmark Complete ===
    Cycles:       #{num_cycles}
    Nodes before: #{before_snapshot.node_count}
    Nodes after:  #{after_snapshot.node_count}
    Pruned:       #{results.decay_analysis.nodes_pruned}
    Survival:     #{results.decay_analysis.survival_rate * 100}%
    Avg decay/cy: #{results.decay_analysis.mean_decay_per_cycle}
    Mean cycle:   #{div(results.performance.mean_cycle_us, 1000)} ms
    Output:       #{path}
    """)
  end

  defp take_snapshot do
    nodes = Graphonomous.list_nodes(%{limit: 100_000}) || []
    confidences = Enum.map(nodes, & &1.confidence)

    %{
      node_count: length(nodes),
      avg_confidence: safe_mean(confidences),
      min_confidence: Enum.min(confidences, fn -> 0.0 end),
      max_confidence: Enum.max(confidences, fn -> 0.0 end),
      confidence_stddev: stddev(confidences),
      by_type:
        nodes
        |> Enum.group_by(& &1.node_type)
        |> Enum.map(fn {type, items} -> {type, length(items)} end)
        |> Map.new()
    }
  end

  defp run_survival_analysis do
    # Create test nodes at specific confidence levels
    test_confidences = [0.05, 0.1, 0.15, 0.3, 0.5, 0.7, 0.9]

    test_nodes =
      Enum.map(test_confidences, fn conf ->
        node =
          Graphonomous.store_node(%{
            content: "Survival test node at confidence #{conf}",
            node_type: "semantic",
            confidence: conf,
            source: "benchmark:survival_test",
            metadata: %{
              "benchmark" => "OS-E001",
              "test" => "survival",
              "initial_confidence" => conf
            }
          })

        %{id: node.id, initial_confidence: conf}
      end)

    Helpers.timed(fn ->
      # Run 10 consolidation cycles
      for _ <- 1..10, do: Graphonomous.run_consolidation_now()

      Process.sleep(200)

      # Check which survived
      survival =
        Enum.map(test_nodes, fn tn ->
          case Graphonomous.get_node(tn.id) do
            %{confidence: conf} = _node ->
              %{
                initial_confidence: tn.initial_confidence,
                survived: true,
                final_confidence: Float.round(conf, 6),
                decay_total: Float.round(tn.initial_confidence - conf, 6)
              }

            _ ->
              %{
                initial_confidence: tn.initial_confidence,
                survived: false,
                final_confidence: nil,
                cycles_survived: :pruned
              }
          end
        end)

      # Cleanup survivors
      Enum.each(test_nodes, fn tn ->
        Graphonomous.delete_node(tn.id)
      end)

      %{
        test_confidences: test_confidences,
        results: survival,
        survival_threshold:
          Enum.find(survival, & &1.survived)
          |> then(fn
            nil -> nil
            s -> s.initial_confidence
          end)
      }
    end)
  end

  defp safe_mean([]), do: 0.0
  defp safe_mean(list), do: Enum.sum(list) / length(list)

  defp stddev([]), do: 0.0

  defp stddev(list) do
    mean = safe_mean(list)
    variance = Enum.map(list, fn x -> (x - mean) * (x - mean) end) |> safe_mean()
    :math.sqrt(variance)
  end
end
