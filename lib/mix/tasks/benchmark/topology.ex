defmodule Mix.Tasks.Benchmark.Topology do
  @moduledoc """
  OS-E001 Benchmark: Topology & κ Detection

  Tests whether Graphonomous correctly identifies cyclic knowledge
  structures in the [&] portfolio. The portfolio has known cycles:

  1. **κ self-reference cycle**: The κ spec (in AmpersandBoxDesign) defines
     how κ routing works → Graphonomous implements it → the spec references
     Graphonomous as the implementor. This is a genuine κ>0 cycle.

  2. **OS protocol cycle**: OpenSentience defines OS-001 → Graphonomous
     implements OS-001 → OpenSentience references Graphonomous.

  3. **Governance cycle**: Delegatic implements OS-006 → OS-006 governs
     agents → agents include Delegatic itself.

  The benchmark measures:
  - SCC detection accuracy (are known cycles found?)
  - κ value correctness (are cycles scored appropriately?)
  - Routing decision accuracy (does κ>0 trigger deliberate routing?)
  - Edge impact prediction accuracy
  - Computation latency

  Requires: `mix benchmark.ingest` to have been run first.

  Usage:
      mix benchmark.topology
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Benchmark κ topology detection on [&] portfolio"

  @impl Mix.Task
  def run(_args) do
    Helpers.ensure_started()

    Mix.shell().info("=== OS-E001 Benchmark: Topology & κ Detection ===")

    # Phase 1: Analyze the full graph topology
    Mix.shell().info("Phase 1: Full graph topology analysis...")

    {full_analysis_us, full_analysis} = run_full_topology_analysis()

    # Phase 2: Test κ detection on synthetic cycles injected alongside corpus
    Mix.shell().info("Phase 2: Synthetic cycle injection tests...")

    {synthetic_us, synthetic_results} = run_synthetic_cycle_tests()

    # Phase 3: Test edge impact prediction
    Mix.shell().info("Phase 3: Edge impact prediction tests...")

    {impact_us, impact_results} = run_edge_impact_tests()

    # Phase 4: Retrieval-integrated topology (does retrieval surface topology?)
    Mix.shell().info("Phase 4: Retrieval-integrated topology checks...")

    {retrieval_topo_us, retrieval_topo_results} = run_retrieval_topology_tests()

    results = %{
      benchmark: "OS-E001:topology",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      full_graph_analysis: Map.merge(full_analysis, %{latency_us: full_analysis_us}),
      synthetic_cycles: Map.merge(synthetic_results, %{latency_us: synthetic_us}),
      edge_impact: Map.merge(impact_results, %{latency_us: impact_us}),
      retrieval_topology: Map.merge(retrieval_topo_results, %{latency_us: retrieval_topo_us})
    }

    path = Helpers.write_results("topology", results)

    Mix.shell().info("""

    === Topology Benchmark Complete ===
    Full graph SCCs:     #{full_analysis.scc_count}
    Full graph max κ:    #{full_analysis.max_kappa}
    Full graph routing:  #{full_analysis.routing}
    Synthetic tests:     #{synthetic_results.tests_run}
    Synthetic passed:    #{synthetic_results.tests_passed}
    Impact tests:        #{impact_results.tests_run}
    Impact passed:       #{impact_results.tests_passed}
    Output:              #{path}
    """)
  end

  defp run_full_topology_analysis do
    # Get all nodes and edges
    nodes = Graphonomous.list_nodes(%{limit: 100_000}) || []
    node_ids = Enum.map(nodes, & &1.id)

    edges =
      node_ids
      |> Enum.flat_map(fn id ->
        case Graphonomous.query_graph(%{operation: "get_edges", node_id: id}) do
          edges when is_list(edges) -> edges
          _ -> []
        end
      end)
      |> Enum.uniq_by(fn e -> {e.source_id, e.target_id} end)

    {us, analysis} =
      Helpers.timed(fn ->
        adjacency = Graphonomous.Topology.build_adjacency(node_ids, edges)
        Graphonomous.Topology.analyze(adjacency)
      end)

    result = %{
      node_count: length(node_ids),
      edge_count: length(edges),
      scc_count: Map.get(analysis, :scc_count, 0),
      max_kappa: Map.get(analysis, :max_kappa, 0),
      routing: Map.get(analysis, :routing, :fast),
      dag_node_count: length(Map.get(analysis, :dag_nodes, [])),
      sccs:
        Map.get(analysis, :sccs, [])
        |> Enum.map(fn scc ->
          nodes = Map.get(scc, :nodes, [])

          size =
            if is_struct(nodes, MapSet), do: MapSet.size(nodes), else: length(List.wrap(nodes))

          %{
            size: size,
            kappa: Map.get(scc, :kappa, 0),
            routing: Map.get(scc, :routing, :fast)
          }
        end)
    }

    {us, result}
  end

  defp run_synthetic_cycle_tests do
    tests = [
      # Test 1: Create a 3-node cycle, verify κ >= 1
      %{
        name: "3-node cycle",
        setup: fn ->
          n1 = store_temp("Cycle test: A defines B", "semantic")
          n2 = store_temp("Cycle test: B implements A", "semantic")
          n3 = store_temp("Cycle test: C depends on B, referenced by A", "semantic")
          Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "causal", weight: 0.9})
          Graphonomous.link_nodes(n2.id, n3.id, %{edge_type: "causal", weight: 0.9})
          Graphonomous.link_nodes(n3.id, n1.id, %{edge_type: "causal", weight: 0.9})
          [n1.id, n2.id, n3.id]
        end,
        assert: fn analysis ->
          analysis.scc_count >= 1 and analysis.max_kappa >= 1 and analysis.routing == :deliberate
        end
      },

      # Test 2: DAG only (no cycles), verify κ = 0
      %{
        name: "DAG only (no cycles)",
        setup: fn ->
          n1 = store_temp("DAG test: root concept", "semantic")
          n2 = store_temp("DAG test: derived concept", "semantic")
          n3 = store_temp("DAG test: leaf concept", "semantic")
          Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "derived_from", weight: 0.8})
          Graphonomous.link_nodes(n2.id, n3.id, %{edge_type: "derived_from", weight: 0.8})
          [n1.id, n2.id, n3.id]
        end,
        assert: fn analysis ->
          analysis.scc_count == 0 and analysis.max_kappa == 0 and analysis.routing == :fast
        end
      },

      # Test 3: Mixed graph (some cycles, some DAG), verify correct partition
      %{
        name: "mixed cycle + DAG",
        setup: fn ->
          # Cycle
          c1 = store_temp("Mixed: cycle node A", "semantic")
          c2 = store_temp("Mixed: cycle node B", "semantic")
          Graphonomous.link_nodes(c1.id, c2.id, %{edge_type: "supports", weight: 0.9})
          Graphonomous.link_nodes(c2.id, c1.id, %{edge_type: "supports", weight: 0.9})
          # DAG
          d1 = store_temp("Mixed: dag leaf", "semantic")
          Graphonomous.link_nodes(c1.id, d1.id, %{edge_type: "derived_from", weight: 0.7})
          [c1.id, c2.id, d1.id]
        end,
        assert: fn analysis ->
          analysis.scc_count >= 1 and length(analysis.dag_nodes) >= 1
        end
      },

      # Test 4: Self-referential κ (like the spec-about-the-spec pattern)
      %{
        name: "self-referential spec pattern",
        setup: fn ->
          spec = store_temp("κ routing spec: defines how cycles trigger deliberation", "semantic")

          impl =
            store_temp("κ routing impl: implements the spec's algorithm in Elixir", "procedural")

          test = store_temp("κ routing test: validates impl matches spec", "episodic")
          Graphonomous.link_nodes(spec.id, impl.id, %{edge_type: "derived_from", weight: 0.95})
          Graphonomous.link_nodes(impl.id, test.id, %{edge_type: "causal", weight: 0.9})
          Graphonomous.link_nodes(test.id, spec.id, %{edge_type: "supports", weight: 0.85})
          [spec.id, impl.id, test.id]
        end,
        assert: fn analysis ->
          analysis.scc_count >= 1 and analysis.max_kappa >= 1
        end
      }
    ]

    {us, test_results} =
      Helpers.timed(fn ->
        Enum.map(tests, fn test ->
          node_ids = test.setup.()

          edges =
            node_ids
            |> Enum.flat_map(fn id ->
              case Graphonomous.query_graph(%{operation: "get_edges", node_id: id}) do
                edges when is_list(edges) -> edges
                _ -> []
              end
            end)
            |> Enum.uniq_by(fn e -> {e.source_id, e.target_id} end)

          adjacency = Graphonomous.Topology.build_adjacency(node_ids, edges)
          analysis = Graphonomous.Topology.analyze(adjacency)

          passed = test.assert.(analysis)

          # Cleanup
          Enum.each(node_ids, &Graphonomous.delete_node/1)

          %{
            name: test.name,
            passed: passed,
            scc_count: analysis.scc_count,
            max_kappa: analysis.max_kappa,
            routing: analysis.routing,
            dag_nodes: length(Map.get(analysis, :dag_nodes, []))
          }
        end)
      end)

    {us,
     %{
       tests_run: length(test_results),
       tests_passed: Enum.count(test_results, & &1.passed),
       details: test_results
     }}
  end

  defp run_edge_impact_tests do
    {us, results} =
      Helpers.timed(fn ->
        # Create two disconnected nodes, predict impact of connecting them
        n1 = store_temp("Impact test: node A", "semantic")
        n2 = store_temp("Impact test: node B", "semantic")

        adjacency = Graphonomous.Topology.build_adjacency([n1.id, n2.id], [])

        # Predict: adding A→B should not create a cycle
        impact_ab = Graphonomous.Topology.preview_edge_impact(adjacency, n1.id, n2.id)
        test1 = not impact_ab.creates_new_scc

        # Now actually add A→B
        Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: "related", weight: 0.8})

        edges =
          [n1.id, n2.id]
          |> Enum.flat_map(fn id ->
            case Graphonomous.query_graph(%{operation: "get_edges", node_id: id}) do
              e when is_list(e) -> e
              _ -> []
            end
          end)
          |> Enum.uniq_by(fn e -> {e.source_id, e.target_id} end)

        adjacency2 = Graphonomous.Topology.build_adjacency([n1.id, n2.id], edges)

        # Predict: adding B→A should create a cycle
        impact_ba = Graphonomous.Topology.preview_edge_impact(adjacency2, n2.id, n1.id)
        test2 = impact_ba.creates_new_scc

        # Cleanup
        Graphonomous.delete_node(n1.id)
        Graphonomous.delete_node(n2.id)

        [
          %{name: "no-cycle edge prediction", passed: test1, details: impact_ab},
          %{name: "cycle-creating edge prediction", passed: test2, details: impact_ba}
        ]
      end)

    {us,
     %{
       tests_run: length(results),
       tests_passed: Enum.count(results, & &1.passed),
       details: results
     }}
  end

  defp run_retrieval_topology_tests do
    # Query the ingested corpus and check if topology annotations are present
    queries = [
      "How does κ routing work and what triggers deliberation?",
      "What is the relationship between the protocol spec and Graphonomous implementation?",
      "How does governance interact with agent memory?"
    ]

    {us, results} =
      Helpers.timed(fn ->
        Enum.map(queries, fn query ->
          retrieval =
            Graphonomous.retrieve_context(query,
              limit: 10,
              expansion_hops: 1
            )

          topology = Map.get(retrieval, :topology, %{})

          %{
            query: query,
            has_topology: topology != %{},
            routing: Map.get(topology, :routing),
            max_kappa: Map.get(topology, :max_kappa, 0),
            scc_count: Map.get(topology, :scc_count, 0),
            result_count: length(Map.get(retrieval, :results, []))
          }
        end)
      end)

    all_have_topology = Enum.all?(results, & &1.has_topology)

    {us,
     %{
       queries_tested: length(results),
       all_have_topology: all_have_topology,
       details: results
     }}
  end

  defp store_temp(content, type) do
    Graphonomous.store_node(%{
      content: content,
      node_type: type,
      confidence: 0.7,
      source: "benchmark:topology_test",
      metadata: %{"benchmark" => "OS-E001", "temporary" => true}
    })
  end
end
