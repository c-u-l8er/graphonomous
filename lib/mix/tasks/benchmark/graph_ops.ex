defmodule Mix.Tasks.Benchmark.GraphOps do
  @moduledoc """
  OS-E001 Benchmark: Graph Operations & Specialized Retrieval

  Exercises graph inspection and specialized retrieval MCP tools:
  - query_graph — operation-based graph inspection
  - graph_traverse — BFS walk (MCP tool)
  - graph_stats — aggregate health metrics (MCP tool)
  - retrieve_episodic — time-filtered episodic retrieval (MCP tool)
  - retrieve_procedural — type-scoped retrieval (MCP tool)
  - coverage_query — standalone coverage assessment (MCP tool)
  - deliberate — κ-driven deliberation

  Requires: `mix benchmark.ingest` to have been run first.

  Usage:
      mix benchmark.graph_ops
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Benchmark graph operations, specialized retrieval, and deliberation"

  @impl Mix.Task
  def run(_args) do
    Helpers.ensure_started()

    Mix.shell().info("=== OS-E001 Benchmark: Graph Operations & Specialized Retrieval ===")

    Mix.shell().info("Phase 1: query_graph operations...")
    {query_us, query_results} = run_query_graph_tests()

    Mix.shell().info("Phase 2: graph_traverse (MCP tool)...")
    {traverse_us, traverse_results} = run_traverse_tests()

    Mix.shell().info("Phase 3: graph_stats (MCP tool)...")
    {stats_us, stats_results} = run_stats_tests()

    Mix.shell().info("Phase 4: retrieve_episodic (MCP tool)...")
    {episodic_us, episodic_results} = run_episodic_retrieval()

    Mix.shell().info("Phase 5: retrieve_procedural (MCP tool)...")
    {procedural_us, procedural_results} = run_procedural_retrieval()

    Mix.shell().info("Phase 6: coverage_query (MCP tool)...")
    {coverage_us, coverage_results} = run_coverage_query_tests()

    Mix.shell().info("Phase 7: deliberate (κ-driven)...")
    {deliberate_us, deliberate_results} = run_deliberation_test()

    results = %{
      benchmark: "OS-E001:graph_ops",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      query_graph: Map.merge(query_results, %{latency_us: query_us}),
      graph_traverse: Map.merge(traverse_results, %{latency_us: traverse_us}),
      graph_stats: Map.merge(stats_results, %{latency_us: stats_us}),
      retrieve_episodic: Map.merge(episodic_results, %{latency_us: episodic_us}),
      retrieve_procedural: Map.merge(procedural_results, %{latency_us: procedural_us}),
      coverage_query: Map.merge(coverage_results, %{latency_us: coverage_us}),
      deliberation: Map.merge(deliberate_results, %{latency_us: deliberate_us}),
      performance: %{
        total_us:
          query_us + traverse_us + stats_us + episodic_us + procedural_us + coverage_us +
            deliberate_us
      }
    }

    path = Helpers.write_results("graph_ops", results)

    Mix.shell().info("""

    === Graph Operations Benchmark Complete ===
    query_graph:         #{query_results.tests_run} tests (#{query_results.tests_passed} passed)
    graph_traverse:      #{traverse_results.tests_run} tests (#{traverse_results.tests_passed} passed)
    graph_stats:         #{if stats_results.passed, do: "PASS", else: "FAIL"}
    retrieve_episodic:   #{episodic_results.tests_run} tests (#{episodic_results.tests_passed} passed)
    retrieve_procedural: #{procedural_results.tests_run} tests (#{procedural_results.tests_passed} passed)
    coverage_query:      #{coverage_results.tests_run} tests (#{coverage_results.tests_passed} passed)
    deliberation:        #{deliberate_results.tests_run} tests (#{deliberate_results.tests_passed} passed)
    Output:              #{path}
    """)
  end

  defp run_query_graph_tests do
    Helpers.timed(fn ->
      nodes = Graphonomous.list_nodes(%{limit: 3}) || []
      sample_node = List.first(nodes)

      tests =
        if sample_node do
          [
            %{
              name: "list_nodes via query_graph",
              run: fn ->
                result = Graphonomous.query_graph(%{operation: "list_nodes", limit: 10})
                is_list(result) and length(result) > 0
              end
            },
            %{
              name: "get_node via query_graph",
              run: fn ->
                result =
                  Graphonomous.query_graph(%{operation: "get_node", node_id: sample_node.id})

                is_map(result) and Map.get(result, :id) == sample_node.id
              end
            },
            %{
              name: "get_edges via query_graph",
              run: fn ->
                result =
                  Graphonomous.query_graph(%{operation: "get_edges", node_id: sample_node.id})

                is_list(result)
              end
            },
            %{
              name: "similarity_search via query_graph",
              run: fn ->
                result =
                  Graphonomous.query_graph(%{
                    operation: "similarity_search",
                    query: "knowledge graph topology",
                    limit: 5
                  })

                is_list(result)
              end
            }
          ]
        else
          []
        end

      run_tests(tests)
    end)
  end

  defp run_traverse_tests do
    Helpers.timed(fn ->
      nodes = Graphonomous.list_nodes(%{limit: 50}) || []

      node_with_edges =
        Enum.find(nodes, fn n ->
          edges = Graphonomous.query_graph(%{operation: "get_edges", node_id: n.id})
          is_list(edges) and length(edges) > 0
        end)

      tests =
        if node_with_edges do
          [
            %{
              name: "BFS traverse depth=1 (MCP tool)",
              run: fn ->
                result =
                  Graphonomous.MCP.GraphTraverse.execute(
                    %{"start_node_id" => node_with_edges.id, "max_depth" => "1"},
                    nil
                  )

                match?({:reply, _, _}, result)
              end
            },
            %{
              name: "BFS traverse depth=2 (MCP tool)",
              run: fn ->
                result =
                  Graphonomous.MCP.GraphTraverse.execute(
                    %{"start_node_id" => node_with_edges.id, "max_depth" => "2"},
                    nil
                  )

                match?({:reply, _, _}, result)
              end
            }
          ]
        else
          [%{name: "no edges found for traversal (skip)", run: fn -> true end}]
        end

      run_tests(tests)
    end)
  end

  defp run_stats_tests do
    Helpers.timed(fn ->
      result =
        try do
          Graphonomous.MCP.GraphStats.execute(%{}, nil)
        rescue
          e -> {:error, Exception.message(e)}
        end

      case result do
        {:reply, response, _} ->
          %{passed: true, response: extract_text(response)}

        _ ->
          %{passed: false, response: inspect(result)}
      end
    end)
  end

  defp run_episodic_retrieval do
    Helpers.timed(fn ->
      # Create episodic test nodes
      e1 =
        Graphonomous.store_node(%{
          content: "Benchmark observation: scan_directory successfully ingested ProjectAmp2.",
          node_type: "episodic",
          confidence: 0.8,
          source: "benchmark:graph_ops_test"
        })

      tests = [
        %{
          name: "retrieve_episodic via MCP tool",
          run: fn ->
            result =
              Graphonomous.MCP.RetrieveEpisodic.execute(
                %{"limit" => "5"},
                nil
              )

            match?({:reply, _, _}, result)
          end
        }
      ]

      test_results = run_tests(tests)
      Graphonomous.delete_node(e1.id)
      test_results
    end)
  end

  defp run_procedural_retrieval do
    Helpers.timed(fn ->
      p1 =
        Graphonomous.store_node(%{
          content: "To run the benchmark suite: cd graphonomous && mix benchmark.run",
          node_type: "procedural",
          confidence: 0.9,
          source: "benchmark:graph_ops_test"
        })

      tests = [
        %{
          name: "retrieve_procedural via MCP tool",
          run: fn ->
            result =
              Graphonomous.MCP.RetrieveProcedural.execute(
                %{"task" => "how to run benchmark", "limit" => "5"},
                nil
              )

            match?({:reply, _, _}, result)
          end
        }
      ]

      test_results = run_tests(tests)
      Graphonomous.delete_node(p1.id)
      test_results
    end)
  end

  defp run_coverage_query_tests do
    Helpers.timed(fn ->
      tests = [
        %{
          name: "coverage_query on well-documented task",
          run: fn ->
            result =
              Graphonomous.MCP.CoverageQuery.execute(
                %{
                  "task_description" => "Store and retrieve nodes in the knowledge graph",
                  "critical_topics" => "[\"knowledge graph\", \"node storage\"]"
                },
                nil
              )

            match?({:reply, _, _}, result)
          end
        },
        %{
          name: "coverage_query on undocumented task",
          run: fn ->
            result =
              Graphonomous.MCP.CoverageQuery.execute(
                %{
                  "task_description" => "Implement quantum error correction for graph federation",
                  "critical_topics" => "[\"quantum\", \"error correction\"]"
                },
                nil
              )

            match?({:reply, _, _}, result)
          end
        }
      ]

      run_tests(tests)
    end)
  end

  defp run_deliberation_test do
    Helpers.timed(fn ->
      # Create a cycle to trigger deliberation
      n1 =
        Graphonomous.store_node(%{
          content: "Deliberation test: spec defines κ routing algorithm.",
          node_type: "semantic",
          confidence: 0.8,
          source: "benchmark:deliberation_test"
        })

      n2 =
        Graphonomous.store_node(%{
          content: "Deliberation test: implementation uses Tarjan SCC.",
          node_type: "procedural",
          confidence: 0.75,
          source: "benchmark:deliberation_test"
        })

      n3 =
        Graphonomous.store_node(%{
          content: "Deliberation test: test validates impl matches spec.",
          node_type: "episodic",
          confidence: 0.7,
          source: "benchmark:deliberation_test"
        })

      Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "derived_from", weight: 0.9})
      Graphonomous.link_nodes(n2.id, n3.id, %{edge_type: "causal", weight: 0.85})
      Graphonomous.link_nodes(n3.id, n1.id, %{edge_type: "supports", weight: 0.8})

      edges =
        [n1.id, n2.id, n3.id]
        |> Enum.flat_map(fn id ->
          case Graphonomous.query_graph(%{operation: "get_edges", node_id: id}) do
            e when is_list(e) -> e
            _ -> []
          end
        end)
        |> Enum.uniq_by(fn e -> {e.source_id, e.target_id} end)

      adjacency = Graphonomous.Topology.build_adjacency([n1.id, n2.id, n3.id], edges)
      topology = Graphonomous.Topology.analyze(adjacency)

      retrieval_results = [
        %{
          node_id: n1.id,
          content: n1.content,
          confidence: n1.confidence,
          similarity: 0.9,
          score: 0.72
        },
        %{
          node_id: n2.id,
          content: n2.content,
          confidence: n2.confidence,
          similarity: 0.85,
          score: 0.64
        },
        %{
          node_id: n3.id,
          content: n3.content,
          confidence: n3.confidence,
          similarity: 0.8,
          score: 0.56
        }
      ]

      tests = [
        %{
          name: "deliberate on κ>0 region",
          run: fn ->
            result =
              Graphonomous.deliberate(
                topology,
                "Should the κ routing implementation match the spec exactly?",
                retrieval_results,
                write_back: false
              )

            is_map(result) and Map.has_key?(result, :verdict)
          end
        },
        %{
          name: "topology confirms κ>0 for cycle",
          run: fn ->
            topology.max_kappa >= 1 and topology.routing == :deliberate
          end
        }
      ]

      test_results = run_tests(tests)
      Enum.each([n1.id, n2.id, n3.id], &Graphonomous.delete_node/1)

      Map.merge(test_results, %{
        topology: %{
          max_kappa: topology.max_kappa,
          routing: topology.routing,
          scc_count: topology.scc_count
        }
      })
    end)
  end

  defp run_tests(tests) do
    results =
      Enum.map(tests, fn test ->
        passed =
          try do
            test.run.()
          rescue
            e ->
              Mix.shell().info("  FAIL: #{test.name} — #{Exception.message(e)}")
              false
          end

        %{name: test.name, passed: passed == true}
      end)

    %{
      tests_run: length(results),
      tests_passed: Enum.count(results, & &1.passed),
      details: results
    }
  end

  defp extract_text(%{content: [%{text: text} | _]}), do: text
  defp extract_text(%{content: text}) when is_binary(text), do: text
  defp extract_text(other), do: inspect(other)
end
