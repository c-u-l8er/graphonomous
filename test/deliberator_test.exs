defmodule Graphonomous.DeliberatorTest do
  use ExUnit.Case, async: false

  alias Graphonomous.Deliberator

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  test "decompose/1 uses fault_line_edges when present" do
    scc = %{
      id: "scc-1",
      nodes: ["a", "b", "c"],
      kappa: 1,
      fault_line_edges: [%{source: "a", target: "b"}]
    }

    partitions = Deliberator.decompose(scc)

    assert is_list(partitions)
    assert length(partitions) == 1

    [partition] = partitions
    assert partition.right == ["b"]
    assert Enum.sort(partition.left) == ["a", "c"]
    assert partition.fault_line == %{source: "a", target: "b"}
  end

  test "deliberate/4 converges with high-confidence agent output" do
    topology = %{
      sccs: [
        %{
          id: "scc-0",
          nodes: ["n1", "n2", "n3"],
          kappa: 1,
          fault_line_edges: [%{source: "n1", target: "n2"}]
        }
      ],
      max_kappa: 1
    }

    retrieval_results = [
      %{node_id: "n1", content: "A influences B", confidence: 0.9, score: 0.8},
      %{node_id: "n2", content: "B influences C", confidence: 0.9, score: 0.8},
      %{node_id: "n3", content: "C influences A", confidence: 0.9, score: 0.8}
    ]

    strong_agent = fn _prompt ->
      %{content: "Resolved causal contradiction across fault line.", confidence: 0.95}
    end

    result =
      Deliberator.deliberate(topology, "How should we break this cycle?", retrieval_results,
        model_tier: :local_large,
        agent_fn: strong_agent,
        budget: %{max_iterations: 3, confidence_threshold: 0.8},
        write_back: false
      )

    assert result.converged == true
    assert result.iterations_used == 1
    assert length(result.conclusions) == 1

    [conclusion] = result.conclusions
    assert conclusion.source_scc_id == "scc-0"
    assert conclusion.source_kappa == 1
    assert conclusion.confidence >= 0.8
    assert is_binary(conclusion.content)

    assert result.topology_change.kappa_before == 1
    assert result.topology_change.kappa_after == 0
    assert result.topology_change.new_nodes_created == 0
  end

  test "deliberate/4 remains unconverged with low-confidence agent output" do
    topology = %{
      sccs: [
        %{
          id: "scc-2",
          nodes: ["x", "y"],
          kappa: 2,
          fault_line_edges: [%{source: "x", target: "y"}]
        }
      ],
      max_kappa: 2
    }

    retrieval_results = [
      %{node_id: "x", content: "x evidence", confidence: 0.5, score: 0.3},
      %{node_id: "y", content: "y evidence", confidence: 0.5, score: 0.3}
    ]

    weak_agent = fn _prompt ->
      %{content: "Still ambiguous.", confidence: 0.2}
    end

    result =
      Deliberator.deliberate(topology, "What is the stable intervention?", retrieval_results,
        model_tier: :local_small,
        agent_fn: weak_agent,
        budget: %{max_iterations: 2, confidence_threshold: 0.9},
        write_back: false
      )

    assert result.converged == false
    assert result.iterations_used == 1
    assert length(result.conclusions) == 1
    assert result.topology_change.kappa_before == 2
    assert result.topology_change.kappa_after == 2
  end

  test "crystallize/3 returns :skipped when write_back is false" do
    conclusion = %{
      content: "A concise conclusion",
      confidence: 0.77,
      source_scc_id: "scc-skip",
      source_kappa: 1,
      fault_lines_examined: [%{source: "a", target: "b"}]
    }

    scc = %{id: "scc-skip", nodes: ["a", "b"], kappa: 1, fault_line_edges: []}

    assert :skipped = Deliberator.crystallize(conclusion, scc, write_back: false)
  end

  test "crystallize/3 writes a semantic node when write_back is true" do
    conclusion = %{
      content: "Crystallized conclusion for a cyclic region.",
      confidence: 0.83,
      source_scc_id: "scc-write",
      source_kappa: 1,
      fault_lines_examined: [%{source: "m", target: "n"}]
    }

    scc = %{id: "scc-write", nodes: ["m", "n"], kappa: 1, fault_line_edges: []}

    assert {:ok, node_id} =
             Deliberator.crystallize(conclusion, scc,
               write_back: true,
               source: "test:deliberator_crystallize"
             )

    stored = Graphonomous.get_node(node_id)
    assert stored.id == node_id
    assert stored.node_type == :semantic
    assert stored.source == "test:deliberator_crystallize"
    assert is_map(stored.metadata)
    assert stored.metadata["kind"] == "deliberation_conclusion"
    assert stored.metadata["source_scc_id"] == "scc-write"

    assert :ok = Graphonomous.delete_node(node_id)
  end
end
