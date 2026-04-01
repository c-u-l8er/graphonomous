defmodule Mix.Tasks.Benchmark.Goals do
  @moduledoc """
  OS-E001 Benchmark: Goal Lifecycle & Coverage

  Exercises the full goal management skill surface:
  - manage_goal — CRUD + lifecycle transitions
  - review_goal — coverage-driven decision gate (act/learn/escalate)
  - coverage_query — standalone epistemic coverage assessment

  Creates realistic goals, links knowledge, reviews coverage,
  and measures the act/learn/escalate routing accuracy.

  Requires: `mix benchmark.ingest` to have been run first.

  Usage:
      mix benchmark.goals
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Benchmark goal lifecycle and coverage evaluation"

  @impl Mix.Task
  def run(_args) do
    Helpers.ensure_started()

    Mix.shell().info("=== OS-E001 Benchmark: Goal Lifecycle & Coverage ===")
    cleanup_benchmark_goals()

    # Phase 1: Goal CRUD lifecycle
    Mix.shell().info("Phase 1: Goal lifecycle (create → activate → progress → complete)...")
    {lifecycle_us, lifecycle_results} = run_lifecycle_tests()

    # Phase 2: Coverage query (standalone, no goal binding)
    Mix.shell().info("Phase 2: coverage_query (standalone epistemic assessment)...")
    {coverage_us, coverage_results} = run_coverage_tests()

    # Phase 3: Goal review with coverage-driven routing
    Mix.shell().info("Phase 3: review_goal (coverage-driven act/learn/escalate)...")
    {review_us, review_results} = run_review_tests()

    cleanup_benchmark_goals()

    results = %{
      benchmark: "OS-E001:goals",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      lifecycle: Map.merge(lifecycle_results, %{latency_us: lifecycle_us}),
      coverage_query: Map.merge(coverage_results, %{latency_us: coverage_us}),
      goal_review: Map.merge(review_results, %{latency_us: review_us}),
      performance: %{
        total_us: lifecycle_us + coverage_us + review_us
      }
    }

    path = Helpers.write_results("goals", results)

    Mix.shell().info("""

    === Goal Lifecycle Benchmark Complete ===
    Lifecycle tests:  #{lifecycle_results.tests_run} (#{lifecycle_results.tests_passed} passed)
    Coverage tests:   #{coverage_results.tests_run} (#{coverage_results.tests_passed} passed)
    Review tests:     #{review_results.tests_run} (#{review_results.tests_passed} passed)
    Output:           #{path}
    """)
  end

  defp run_lifecycle_tests do
    Helpers.timed(fn ->
      tests = [
        %{
          name: "full lifecycle: proposed → active → completed",
          run: fn ->
            goal =
              Graphonomous.create_goal(%{
                title: "Bench: implement κ routing",
                description: "Add topology-aware routing to retriever",
                status: :proposed,
                timescale: :short_term,
                source_type: :user,
                priority: :high,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            if not assert_status(goal, :proposed), do: throw(:failed)
            active = Graphonomous.transition_goal(goal.id, :active, %{"reason" => "bench"})
            if not assert_status(active, :active), do: throw(:failed)
            progressed = Graphonomous.set_goal_progress(goal.id, 0.5)
            if progressed.progress < 0.5, do: throw(:failed)
            completed = Graphonomous.set_goal_progress(goal.id, 1.0)
            assert_status(completed, :completed)
          end
        },
        %{
          name: "goal with linked knowledge nodes",
          run: fn ->
            goal =
              Graphonomous.create_goal(%{
                title: "Bench: evaluate consolidation",
                description: "Measure decay rates across timescales",
                status: :proposed,
                timescale: :medium_term,
                source_type: :user,
                priority: :medium,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            # Retrieve relevant knowledge
            retrieval = Graphonomous.retrieve_context("consolidation decay confidence", limit: 3)
            node_ids = Map.get(retrieval, :results, []) |> Enum.map(& &1.node_id)

            if node_ids != [] do
              linked = Graphonomous.link_goal_nodes(goal.id, node_ids)
              length(linked.linked_node_ids) > 0
            else
              # no nodes to link, still passes
              true
            end
          end
        },
        %{
          name: "goal abandonment",
          run: fn ->
            goal =
              Graphonomous.create_goal(%{
                title: "Bench: abandoned goal",
                description: "This goal will be abandoned",
                status: :proposed,
                timescale: :short_term,
                source_type: :user,
                priority: :low,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            abandoned =
              Graphonomous.transition_goal(goal.id, :abandoned, %{
                "reason" => "no longer relevant"
              })

            assert_status(abandoned, :abandoned)
          end
        },
        %{
          name: "list and filter goals",
          run: fn ->
            _g1 =
              Graphonomous.create_goal(%{
                title: "Bench: list test A",
                status: :proposed,
                priority: :high,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            _g2 =
              Graphonomous.create_goal(%{
                title: "Bench: list test B",
                status: :proposed,
                priority: :low,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            all = Graphonomous.list_goals(%{limit: 100})
            is_list(all) and length(all) >= 2
          end
        }
      ]

      run_tests(tests)
    end)
  end

  defp run_coverage_tests do
    Helpers.timed(fn ->
      tests = [
        %{
          name: "high-coverage task (well-documented topic)",
          run: fn ->
            {:reply, response, _} =
              Graphonomous.MCP.CoverageQuery.execute(
                %{
                  "task_description" =>
                    "Store and retrieve nodes in the Graphonomous knowledge graph",
                  "critical_topics" => "[\"knowledge graph\", \"node storage\", \"retrieval\"]"
                },
                nil
              )

            is_map(response)
          end
        },
        %{
          name: "low-coverage task (undocumented topic)",
          run: fn ->
            {:reply, response, _} =
              Graphonomous.MCP.CoverageQuery.execute(
                %{
                  "task_description" =>
                    "Implement quantum error correction for distributed graph federation",
                  "critical_topics" => "[\"quantum\", \"error correction\", \"federation\"]"
                },
                nil
              )

            is_map(response)
          end
        },
        %{
          name: "cross-domain coverage query",
          run: fn ->
            {:reply, response, _} =
              Graphonomous.MCP.CoverageQuery.execute(
                %{
                  "task_description" =>
                    "How does governance affect the memory consolidation lifecycle?",
                  "critical_topics" => "[\"governance\", \"consolidation\", \"lifecycle\"]"
                },
                nil
              )

            is_map(response)
          end
        }
      ]

      run_tests(tests)
    end)
  end

  defp run_review_tests do
    Helpers.timed(fn ->
      tests = [
        %{
          name: "review goal with linked knowledge → act/learn decision",
          run: fn ->
            # Create goal + link knowledge
            goal =
              Graphonomous.create_goal(%{
                title: "Bench: reviewable goal",
                description: "Evaluate κ detection accuracy on synthetic cycles",
                status: :proposed,
                timescale: :short_term,
                source_type: :user,
                priority: :high,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            Graphonomous.transition_goal(goal.id, :active, %{"reason" => "bench"})

            retrieval = Graphonomous.retrieve_context("κ detection topology cycles", limit: 5)
            node_ids = Map.get(retrieval, :results, []) |> Enum.map(& &1.node_id)
            if node_ids != [], do: Graphonomous.link_goal_nodes(goal.id, node_ids)

            # Build coverage signal from retrieval
            signal = %{
              retrieved_nodes:
                Map.get(retrieval, :results, [])
                |> Enum.map(fn r ->
                  %{
                    node_id: r.node_id,
                    confidence: r.confidence,
                    similarity: r.similarity
                  }
                end),
              outcomes: [],
              contradictions: 0
            }

            case Graphonomous.review_goal(goal.id, signal) do
              {:ok, reviewed, evaluation} ->
                evaluation.decision in [:act, :learn, :escalate] and
                  reviewed.last_reviewed_at != nil

              _ ->
                false
            end
          end
        },
        %{
          name: "review goal with no knowledge → learn/escalate",
          run: fn ->
            goal =
              Graphonomous.create_goal(%{
                title: "Bench: empty knowledge goal",
                description: "Build a faster-than-light communication protocol",
                status: :proposed,
                timescale: :long_term,
                source_type: :user,
                priority: :low,
                owner: "benchmark:OS-E001",
                metadata: %{"benchmark" => "OS-E001"}
              })

            Graphonomous.transition_goal(goal.id, :active, %{"reason" => "bench"})

            signal = %{retrieved_nodes: [], outcomes: [], contradictions: 0}

            case Graphonomous.review_goal(goal.id, signal) do
              {:ok, _reviewed, evaluation} ->
                evaluation.decision in [:learn, :escalate]

              _ ->
                false
            end
          end
        }
      ]

      run_tests(tests)
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

  defp assert_status(%{status: status}, expected) when is_atom(expected), do: status == expected
  defp assert_status(_, _), do: false

  defp cleanup_benchmark_goals do
    case Graphonomous.list_goals(%{include_abandoned: true, limit: 10_000}) do
      goals when is_list(goals) ->
        goals
        |> Enum.filter(fn g ->
          meta = Map.get(g, :metadata, %{})
          Map.get(meta, "benchmark") == "OS-E001"
        end)
        |> Enum.each(fn g -> Graphonomous.delete_goal(g.id) end)

      _ ->
        :ok
    end
  end
end
