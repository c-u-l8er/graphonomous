defmodule Mix.Tasks.Benchmark.Run do
  @moduledoc """
  OS-E001 Benchmark: Full Suite Runner

  Orchestrates all 10 benchmark phases covering all 20 MCP tools:

  1. Ingest (scan_directory) — FilesystemTraversal on full codebase
  2. Retrieval — cross-domain precision/recall/F1
  3. Topology — κ detection, SCC, edge impact
  4. Learning — outcome, feedback, novelty, interaction
  5. Goals — lifecycle, coverage_query, review_goal
  6. Graph Ops — query_graph, graph_traverse, graph_stats,
                 retrieve_episodic, retrieve_procedural, deliberate
  7. Consolidation — decay curves, survival analysis
  8. Attention — survey, dispatch, prioritization
  9. LongMemEval — competitive memory benchmark (ICLR 2025)
  10. BEAM — Beyond a Million Tokens (ICLR 2026)

  Usage:
      mix benchmark.run [--cycles 5]

  Options:
      --cycles   Consolidation cycles (default: 5)
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Run the full OS-E001 benchmark suite (all 20 MCP tools, 10 phases)"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [cycles: :integer, neural: :boolean])
    cycles = Keyword.get(opts, :cycles, 5)
    neural = Keyword.get(opts, :neural, false)

    # Store neural flag for sub-tasks to read
    Application.put_env(:graphonomous, :benchmark_neural, neural)

    embedder_label = if neural, do: "Bumblebee + EXLA (neural)", else: "fallback (trigram)"

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════════╗
    ║  OS-E001: Empirical Evaluation of Topology-Aware        ║
    ║  Continual Learning on a Multi-Domain Portfolio         ║
    ║                                                         ║
    ║  System:   Graphonomous v#{Mix.Project.config()[:version] || "0.1.12"}                          ║
    ║  Embedder: #{String.pad_trailing(embedder_label, 44)}║
    ║  Corpus:   Full ProjectAmp2 codebase (scan_directory)    ║
    ║  Skills:   All 20 MCP tools                              ║
    ║  Date:     #{Date.utc_today()}                               ║
    ╚══════════════════════════════════════════════════════════╝
    """)

    total_start = System.monotonic_time(:microsecond)

    # Phase 1: Ingestion via scan_directory
    Mix.shell().info("\n━━━ Phase 1/9: Corpus Ingestion (scan_directory) ━━━")
    Mix.Tasks.Benchmark.Ingest.run(["--purge"])

    # Phase 2: Retrieval quality
    Mix.shell().info("\n━━━ Phase 2/9: Retrieval Quality ━━━")
    Mix.Tasks.Benchmark.Retrieval.run([])

    # Phase 3: Topology & κ detection
    Mix.shell().info("\n━━━ Phase 3/9: Topology & κ Detection ━━━")
    Mix.Tasks.Benchmark.Topology.run([])

    # Phase 4: Learning loop
    Mix.shell().info("\n━━━ Phase 4/9: Learning Loop ━━━")
    Mix.Tasks.Benchmark.Learning.run([])

    # Phase 5: Goal lifecycle & coverage
    Mix.shell().info("\n━━━ Phase 5/9: Goal Lifecycle & Coverage ━━━")
    Mix.Tasks.Benchmark.Goals.run([])

    # Phase 6: Graph operations & specialized retrieval
    Mix.shell().info("\n━━━ Phase 6/9: Graph Operations & Deliberation ━━━")
    Mix.Tasks.Benchmark.GraphOps.run([])

    # Phase 7: Consolidation
    Mix.shell().info("\n━━━ Phase 7/9: Consolidation ━━━")
    Mix.Tasks.Benchmark.Consolidation.run(["--cycles", "#{cycles}"])

    # Phase 8: Attention engine
    Mix.shell().info("\n━━━ Phase 8/9: Attention Engine ━━━")
    Mix.Tasks.Benchmark.Attention.run([])

    # Phase 9: LongMemEval competitive benchmark
    longmemeval_data =
      Path.join([
        Helpers.portfolio_root(),
        "graphonomous",
        "priv",
        "longmemeval",
        "longmemeval_oracle.json"
      ])

    if File.exists?(longmemeval_data) do
      Mix.shell().info("\n━━━ Phase 9/10: LongMemEval Competitive Benchmark ━━━")
      Mix.Tasks.Benchmark.Longmemeval.run(["--split", "oracle", "--purge"])
    else
      Mix.shell().info("\n━━━ Phase 9/10: LongMemEval — SKIPPED (data not downloaded) ━━━")
      Mix.shell().info("  Run: cd graphonomous/priv/longmemeval && bash download.sh")
    end

    # Phase 10: BEAM competitive benchmark
    beam_data =
      Path.join([
        Helpers.portfolio_root(),
        "graphonomous",
        "priv",
        "beam",
        "100K"
      ])

    if File.dir?(beam_data) do
      Mix.shell().info("\n━━━ Phase 10/10: BEAM Competitive Benchmark (100K) ━━━")
      Mix.Tasks.Benchmark.Beam.run(["--tier", "100k", "--purge"])
    else
      Mix.shell().info("\n━━━ Phase 10/10: BEAM — SKIPPED (data not downloaded) ━━━")
      Mix.shell().info("  Run: cd graphonomous/priv/beam && bash download.sh")
    end

    total_us = System.monotonic_time(:microsecond) - total_start

    # Load individual results and combine
    dir = Path.join([Helpers.portfolio_root(), "graphonomous", "benchmark_results"])

    combined = %{
      benchmark: "OS-E001:combined",
      version: "2.0.0",
      system: %{
        engine: "Graphonomous",
        engine_version: Mix.Project.config()[:version] || "0.1.12",
        elixir_version: System.version(),
        otp_release: :erlang.system_info(:otp_release) |> to_string(),
        embedder: Application.get_env(:graphonomous, :embedder_backend, :auto) |> to_string(),
        embedding_model:
          Application.get_env(:graphonomous, :embedding_model_id, "all-MiniLM-L6-v2")
      },
      corpus: %{
        name: "[&] Protocol Portfolio — Full Codebase",
        description: "Full ProjectAmp2 codebase ingested via scan_directory",
        method: "scan_directory"
      },
      skill_coverage: %{
        total_mcp_tools: 20,
        covered: [
          "store_node",
          "store_edge",
          "retrieve_context",
          "query_graph",
          "topology_analyze",
          "graph_traverse",
          "graph_stats",
          "retrieve_episodic",
          "retrieve_procedural",
          "coverage_query",
          "learn_from_outcome",
          "learn_from_feedback",
          "learn_detect_novelty",
          "learn_from_interaction",
          "deliberate",
          "manage_goal",
          "review_goal",
          "run_consolidation",
          "attention_survey",
          "attention_run_cycle"
        ],
        coverage_pct: 100
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_duration_us: total_us,
      total_duration_human: format_duration(total_us),
      phases: load_phase_results(dir),
      graph_final: get_final_graph_stats()
    }

    path = Helpers.write_results("combined", combined)

    Mix.shell().info("""

    ╔══════════════════════════════════════════════════════════╗
    ║              OS-E001 BENCHMARK COMPLETE                  ║
    ╠══════════════════════════════════════════════════════════╣
    ║  MCP tools covered: 20/20 (100%)                         ║
    ║  Total time: #{String.pad_trailing(combined.total_duration_human, 42)}║
    ║  Results:    #{String.pad_trailing(path, 42)}║
    ╚══════════════════════════════════════════════════════════╝
    """)
  end

  defp load_phase_results(dir) do
    phases = [
      "ingest",
      "retrieval",
      "topology",
      "learning",
      "goals",
      "graph_ops",
      "consolidation",
      "attention",
      "longmemeval",
      "beam_128k"
    ]

    Enum.reduce(phases, %{}, fn phase, acc ->
      path = Path.join(dir, "#{phase}.json")

      case File.read(path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, data} -> Map.put(acc, phase, data)
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp get_final_graph_stats do
    nodes = Graphonomous.list_nodes(%{limit: 100_000}) || []
    confidences = Enum.map(nodes, & &1.confidence)

    %{
      node_count: length(nodes),
      avg_confidence:
        if(confidences != [],
          do: Float.round(Enum.sum(confidences) / length(confidences), 4),
          else: 0
        ),
      by_type:
        nodes
        |> Enum.group_by(& &1.node_type)
        |> Enum.map(fn {type, items} -> {type, length(items)} end)
        |> Map.new()
    }
  end

  defp format_duration(us) when us < 1_000_000, do: "#{div(us, 1000)} ms"
  defp format_duration(us) when us < 60_000_000, do: "#{Float.round(us / 1_000_000, 1)} sec"
  defp format_duration(us), do: "#{Float.round(us / 60_000_000, 1)} min"
end
