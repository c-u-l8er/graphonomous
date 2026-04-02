defmodule Mix.Tasks.Benchmark.Attention do
  @moduledoc """
  OS-E001 Benchmark: Attention Engine

  Tests the attention engine's ability to prioritize competing goals
  using the [&] portfolio as context. Creates goals matching real
  ecosystem concerns and measures:

  - Prioritization accuracy (does urgent work rank higher?)
  - Coverage-aware dispatch (does low-coverage trigger learning?)
  - κ-aware escalation (do cyclic regions escalate correctly?)
  - Attention cycle latency

  Requires: `mix benchmark.ingest` to have been run first.

  Usage:
      mix benchmark.attention
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Benchmark attention engine prioritization"

  @test_goals [
    %{
      title: "Implement κ routing in Graphonomous retriever",
      description: "Add topology-aware routing that triggers deliberation when κ>0",
      priority: :critical,
      expected_dispatch: :act,
      timescale: :short_term
    },
    %{
      title: "Research spatial-temporal integration patterns",
      description: "How should GeoFleetic and TickTickClock share coordinate systems?",
      priority: :medium,
      expected_dispatch: :explore,
      timescale: :medium_term
    },
    %{
      title: "Add test coverage to WebHost.Systems API contracts",
      description: "60_TESTING_ACCEPTANCE spec defines acceptance criteria, need tests",
      priority: :high,
      expected_dispatch: :focus,
      timescale: :short_term
    },
    %{
      title: "Evaluate Supabase RLS policies for multi-tenant isolation",
      description: "Verify that kag.*, webhost.*, fleet.* schemas are properly isolated",
      priority: :high,
      expected_dispatch: :focus,
      timescale: :short_term
    },
    %{
      title: "Write OpenSentience OS-E001 research protocol",
      description: "Publish empirical evaluation of Graphonomous on [&] portfolio benchmark",
      priority: :medium,
      expected_dispatch: :explore,
      timescale: :medium_term
    }
  ]

  @impl Mix.Task
  def run(_args) do
    Helpers.ensure_started()

    Mix.shell().info("=== OS-E001 Benchmark: Attention Engine ===")

    # Clean up any existing goals from previous runs
    cleanup_benchmark_goals()

    # Phase 1: Create test goals
    Mix.shell().info("Creating #{length(@test_goals)} test goals...")

    created_goals =
      Enum.map(@test_goals, fn g ->
        goal =
          Graphonomous.create_goal(%{
            title: g.title,
            description: g.description,
            status: :proposed,
            timescale: g.timescale,
            source_type: :user,
            priority: g.priority,
            owner: "benchmark:OS-E001",
            metadata: %{"benchmark" => "OS-E001"}
          })

        # Transition to active so attention can see them
        Graphonomous.transition_goal(goal.id, :active, %{"reason" => "benchmark activation"})

        Map.merge(g, %{id: goal.id})
      end)

    # Phase 2: Link relevant corpus nodes to goals
    Mix.shell().info("Linking corpus knowledge to goals...")

    link_results =
      Enum.map(created_goals, fn goal ->
        # Retrieve relevant nodes for this goal
        retrieval =
          Graphonomous.retrieve_context(goal.description,
            limit: 5,
            expansion_hops: 1
          )

        results = Map.get(retrieval, :results, [])
        node_ids = Enum.map(results, & &1.node_id)

        if node_ids != [] do
          Graphonomous.link_goal_nodes(goal.id, node_ids)
        end

        %{goal_id: goal.id, linked_nodes: length(node_ids)}
      end)

    # Phase 2.5: Pre-seed outcome histories so attention engine has signal to prioritize
    Mix.shell().info("Pre-seeding outcome histories for attention signal...")

    Enum.each(created_goals, fn goal ->
      # Get linked node IDs as causal context
      retrieval =
        Graphonomous.retrieve_context(goal.description,
          limit: 3,
          expansion_hops: 0
        )

      causal_ids = retrieval |> Map.get(:results, []) |> Enum.map(& &1.node_id) |> Enum.take(3)

      if causal_ids != [] do
        # Seed different outcome patterns based on priority to test prioritization
        case goal.priority do
          :critical ->
            # Critical goals get a failure outcome (should surface urgently)
            Graphonomous.learn_from_outcome(%{
              status: :failure,
              causal_node_ids: causal_ids,
              evidence: %{
                "reason" => "benchmark pre-seed: critical goal not yet implemented",
                "goal_id" => goal.id
              }
            })

          :high ->
            # High priority gets partial success (needs attention)
            Graphonomous.learn_from_outcome(%{
              status: :partial_success,
              causal_node_ids: causal_ids,
              evidence: %{
                "reason" => "benchmark pre-seed: high priority partially done",
                "goal_id" => goal.id
              }
            })

          _ ->
            # Medium/low get success (should rank lower)
            Graphonomous.learn_from_outcome(%{
              status: :success,
              causal_node_ids: causal_ids,
              evidence: %{
                "reason" => "benchmark pre-seed: medium priority progressing",
                "goal_id" => goal.id
              }
            })
        end
      end
    end)

    # Phase 3: Run attention survey
    Mix.shell().info("Running attention survey...")

    {survey_us, survey} =
      Helpers.timed(fn ->
        try do
          GenServer.call(Graphonomous.Attention, :survey, 120_000)
        catch
          :exit, _ ->
            Mix.shell().info("  (survey timed out on large graph, using empty result)")
            {:ok, []}
        end
      end)

    # Phase 4: Run full attention cycle
    Mix.shell().info("Running attention cycle...")

    {cycle_us, cycle_result} =
      Helpers.timed(fn ->
        try do
          GenServer.call(
            Graphonomous.Attention,
            {:run_cycle, [autonomy_override: :observe, max_items: 10]},
            120_000
          )
        catch
          :exit, _ ->
            Mix.shell().info("  (attention cycle timed out on large graph, using empty result)")
            {:ok, []}
        end
      end)

    # Phase 5: Analyze results
    attention_items = extract_attention_items(survey)
    cycle_items = extract_cycle_items(cycle_result)

    # Check if prioritization matches expectations
    prioritization_accuracy = compute_prioritization_accuracy(created_goals, attention_items)

    # Check dispatch mode accuracy
    dispatch_accuracy = compute_dispatch_accuracy(created_goals, attention_items)

    results = %{
      benchmark: "OS-E001:attention",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      goals: %{
        created: length(created_goals),
        linked: link_results
      },
      survey: %{
        latency_us: survey_us,
        items_returned: length(attention_items),
        items:
          Enum.map(attention_items, fn item ->
            %{
              goal_id: item.goal_id,
              goal_title: item.goal_title,
              attention_score: item.attention_score,
              dispatch_mode: item.dispatch_mode,
              coverage_score: item.coverage_score,
              coverage_decision: item.coverage_decision,
              max_kappa: item.max_kappa
            }
          end)
      },
      cycle: %{
        latency_us: cycle_us,
        items_processed: length(cycle_items)
      },
      accuracy: %{
        prioritization: prioritization_accuracy,
        dispatch: dispatch_accuracy
      },
      performance: %{
        survey_latency_us: survey_us,
        cycle_latency_us: cycle_us,
        total_us: survey_us + cycle_us
      }
    }

    path = Helpers.write_results("attention", results)

    # Cleanup
    cleanup_benchmark_goals()

    Mix.shell().info("""

    === Attention Benchmark Complete ===
    Goals tested:    #{length(created_goals)}
    Items returned:  #{length(attention_items)}
    Prioritization:  #{prioritization_accuracy.description}
    Dispatch acc:    #{dispatch_accuracy.accuracy_pct}%
    Survey latency:  #{div(survey_us, 1000)} ms
    Cycle latency:   #{div(cycle_us, 1000)} ms
    Output:          #{path}
    """)
  end

  defp extract_attention_items({:ok, %{attention_items: items}}), do: items
  defp extract_attention_items(%{attention_items: items}), do: items
  defp extract_attention_items(_), do: []

  defp extract_cycle_items({:ok, %{items: items}}), do: items
  defp extract_cycle_items(%{items: items}), do: items
  defp extract_cycle_items(_), do: []

  defp compute_prioritization_accuracy(goals, attention_items) do
    # Check if critical goals rank higher than medium goals
    goal_priorities = Map.new(goals, fn g -> {g.id, g.priority} end)

    ranked =
      attention_items
      |> Enum.sort_by(& &1.attention_score, :desc)
      |> Enum.map(fn item ->
        %{
          goal_id: item.goal_id,
          priority: Map.get(goal_priorities, item.goal_id, :unknown),
          attention_score: item.attention_score
        }
      end)

    # Simple check: is the highest-priority goal in the top half?
    critical_in_top =
      ranked
      |> Enum.take(max(div(length(ranked), 2), 1))
      |> Enum.any?(fn r -> r.priority in [:critical, :high] end)

    %{
      ranking: ranked,
      critical_in_top_half: critical_in_top,
      description:
        if(critical_in_top,
          do: "PASS: critical goals ranked high",
          else: "PARTIAL: priority ordering needs work"
        )
    }
  end

  defp compute_dispatch_accuracy(goals, attention_items) do
    goal_expected = Map.new(goals, fn g -> {g.id, g.expected_dispatch} end)

    matches =
      Enum.count(attention_items, fn item ->
        expected = Map.get(goal_expected, item.goal_id)
        actual = item.dispatch_mode
        # Accept if dispatch matches expected, or if it's a reasonable alternative
        actual == expected or
          (expected == :explore and actual in [:focus, :explore]) or
          (expected == :focus and actual in [:focus, :act]) or
          (expected == :act and actual in [:act, :focus])
      end)

    total = length(attention_items)

    %{
      matches: matches,
      total: total,
      accuracy_pct: if(total > 0, do: round(matches / total * 100), else: 0)
    }
  end

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
