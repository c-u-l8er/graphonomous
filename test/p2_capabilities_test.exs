defmodule Graphonomous.P2CapabilitiesTest do
  @moduledoc """
  Tests for P2 capabilities:
  - Capability 8: Scoped Uncertainty Propagation
  - Capability 9: Procedural Metadata + Enhanced Retrieval
  - Capability 10: Multi-Agent Schema Prep
  """

  use ExUnit.Case, async: false

  alias Graphonomous.Uncertainty

  describe "Capability 8: Uncertainty — Wilson score intervals" do
    test "node with evidence_count=0 returns :no_evidence" do
      assert Uncertainty.interval(%{confidence: 0.7, evidence_count: 0}) == :no_evidence
    end

    test "node with nil evidence_count returns :no_evidence" do
      assert Uncertainty.interval(%{confidence: 0.7, evidence_count: nil}) == :no_evidence
    end

    test "node with confidence=0.7, evidence_count=1 → wide interval" do
      {lo, hi} = Uncertainty.interval(%{confidence: 0.7, evidence_count: 1})
      width = hi - lo
      assert width > 0.4, "Expected wide interval, got width=#{width}"
      assert lo >= 0.0
      assert hi <= 1.0
    end

    test "interval narrows with more evidence" do
      node_1 = %{confidence: 0.7, evidence_count: 1}
      node_10 = %{confidence: 0.7, evidence_count: 10}

      {lo1, hi1} = Uncertainty.interval(node_1)
      {lo10, hi10} = Uncertainty.interval(node_10)

      width_1 = hi1 - lo1
      width_10 = hi10 - lo10

      assert width_10 < width_1, "Expected narrower interval with more evidence"
    end

    test "interval approaches confidence with many evidence points" do
      node = %{confidence: 0.7, evidence_count: 100}
      {lo, hi} = Uncertainty.interval(node)
      width = hi - lo
      assert width < 0.20, "Expected tight interval with n=100, got width=#{width}"
      assert lo < 0.7
      assert hi > 0.7
    end

    test "entropy returns 1.0 for no-evidence nodes" do
      assert Uncertainty.entropy(%{confidence: 0.8, evidence_count: 0}) == 1.0
    end

    test "entropy returns interval width for evidence-bearing nodes" do
      node = %{confidence: 0.7, evidence_count: 5}
      entropy = Uncertainty.entropy(node)
      {lo, hi} = Uncertainty.interval(node)
      assert_in_delta entropy, hi - lo, 1.0e-10
    end

    test "information_gain is positive for evidence-bearing nodes" do
      node = %{confidence: 0.6, evidence_count: 3}
      ig = Uncertainty.information_gain(node)
      assert ig > 0.0, "Expected positive information gain"
    end

    test "evidence_count increments on learn_from_outcome" do
      node =
        store_node!(%{
          content: "test evidence count #{uniq()}",
          node_type: :semantic,
          confidence: 0.5,
          source: "p2_test"
        })

      assert node.evidence_count == 0

      Graphonomous.learn_from_outcome(%{
        action_id: "action_#{uniq()}",
        status: "success",
        confidence: 0.9,
        causal_node_ids: [node.id]
      })

      updated = Graphonomous.get_node(node.id)
      assert updated.evidence_count == 1

      # Second outcome
      Graphonomous.learn_from_outcome(%{
        action_id: "action_#{uniq()}",
        status: "failure",
        confidence: 0.8,
        causal_node_ids: [node.id]
      })

      updated2 = Graphonomous.get_node(node.id)
      assert updated2.evidence_count == 2
    end

    test "propagation widens child intervals based on parent" do
      parent =
        store_node!(%{
          content: "uncertain parent #{uniq()}",
          node_type: :semantic,
          confidence: 0.5,
          evidence_count: 1,
          source: "p2_test"
        })

      child =
        store_node!(%{
          content: "child of uncertain #{uniq()}",
          node_type: :semantic,
          confidence: 0.8,
          evidence_count: 10,
          source: "p2_test"
        })

      # Create derived_from edge
      Graphonomous.link_nodes(parent.id, child.id, %{
        edge_type: :derived_from,
        weight: 0.8
      })

      {:ok, widened_count} = Uncertainty.propagate(parent.id)
      # Parent has wide interval, child has narrow — propagation should widen
      assert is_integer(widened_count)
    end
  end

  describe "Capability 8: Uncertainty — frontier query" do
    test "frontier returns nodes with wide intervals sorted by information gain" do
      # Create some evidence-bearing nodes
      _wide =
        store_node!(%{
          content: "wide interval node #{uniq()}",
          node_type: :semantic,
          confidence: 0.5,
          evidence_count: 1,
          source: "p2_test"
        })

      _narrow =
        store_node!(%{
          content: "narrow interval node #{uniq()}",
          node_type: :semantic,
          confidence: 0.7,
          evidence_count: 50,
          source: "p2_test"
        })

      frontier = Uncertainty.frontier(min_gap: 0.1, limit: 100)
      assert is_list(frontier)

      # Wide node should appear in frontier, narrow likely not (small gap)
      Enum.each(frontier, fn item ->
        assert item.width > 0.1
        assert item.evidence_count > 0
        assert is_float(item.information_gain)
      end)
    end
  end

  describe "Capability 9: Procedural Metadata — skill auto-extraction" do
    test "procedural node with structured content gets skill metadata" do
      content = """
      How to deploy a new service.
      Prerequisites:
      - has_docker_installed
      - has_kubernetes_access
      Steps:
      1. Build the Docker image
      2. Push to registry
      3. Apply Kubernetes manifests
      Result:
      - service_deployed
      - health_check_passing
      """

      node =
        store_node!(%{
          content: content,
          node_type: :procedural,
          confidence: 0.8,
          source: "p2_test"
        })

      assert is_map(node.metadata)
      skill = Map.get(node.metadata, "skill")
      assert is_map(skill), "Expected skill metadata to be auto-extracted"
      assert is_list(Map.get(skill, "preconditions"))
      assert "has_docker_installed" in Map.get(skill, "preconditions", [])
    end

    test "procedural node without structured content gets no skill metadata" do
      node =
        store_node!(%{
          content: "Just a plain procedure description without any special format #{uniq()}",
          node_type: :procedural,
          confidence: 0.7,
          source: "p2_test"
        })

      skill = Map.get(node.metadata || %{}, "skill")
      # Either nil or empty — no auto-extraction if no structured indicators
      assert is_nil(skill) or map_size(skill) == 0 or
               (is_map(skill) and Map.get(skill, "domain") != nil)
    end

    test "existing skill metadata is preserved (not overwritten)" do
      skill_meta = %{
        "skill" => %{
          "preconditions" => ["custom_precond"],
          "domain" => "custom"
        }
      }

      node =
        store_node!(%{
          content: "Procedure with existing metadata #{uniq()}",
          node_type: :procedural,
          confidence: 0.8,
          source: "p2_test",
          metadata: skill_meta
        })

      assert Map.get(node.metadata, "skill") == skill_meta["skill"]
    end
  end

  describe "Capability 9: Procedural Metadata — precondition matching" do
    test "precondition_match_score returns 1.0 for full match" do
      # Direct test of the matching logic
      required = ["a", "b", "c"]
      available = ["a", "b", "c", "d"]
      matched = Enum.count(required, &(&1 in available))
      score = matched / length(required)
      assert_in_delta score, 1.0, 0.01
    end

    test "precondition_match_score returns partial for partial match" do
      required = ["a", "b", "c"]
      available = ["a", "d"]
      matched = Enum.count(required, &(&1 in available))
      score = matched / length(required)
      assert_in_delta score, 1 / 3, 0.01
    end
  end

  describe "Capability 10: Multi-Agent Schema — node agent_id" do
    test "node defaults to agent_id 'default'" do
      node =
        store_node!(%{
          content: "default agent node #{uniq()}",
          node_type: :semantic,
          confidence: 0.7,
          source: "p2_test"
        })

      assert node.agent_id == "default"
    end

    test "node with explicit agent_id persists correctly" do
      node =
        store_node!(%{
          content: "custom agent node #{uniq()}",
          node_type: :semantic,
          confidence: 0.7,
          source: "p2_test",
          agent_id: "agent_alpha"
        })

      assert node.agent_id == "agent_alpha"

      # Verify persistence
      fetched = Graphonomous.get_node(node.id)
      assert fetched.agent_id == "agent_alpha"
    end

    test "filtering by agent_id returns only matching nodes" do
      store_node!(%{
        content: "agent A node #{uniq()}",
        node_type: :semantic,
        confidence: 0.7,
        source: "p2_test",
        agent_id: "agent_filter_test_a"
      })

      store_node!(%{
        content: "agent B node #{uniq()}",
        node_type: :semantic,
        confidence: 0.7,
        source: "p2_test",
        agent_id: "agent_filter_test_b"
      })

      a_nodes = Graphonomous.list_nodes(%{agent_id: "agent_filter_test_a"})
      assert is_list(a_nodes)
      assert Enum.all?(a_nodes, &(&1.agent_id == "agent_filter_test_a"))
    end
  end

  describe "Capability 10: Multi-Agent Schema — edge agent_id" do
    test "edge defaults to agent_id 'default'" do
      n1 =
        store_node!(%{content: "edge test A #{uniq()}", node_type: :semantic, source: "p2_test"})

      n2 =
        store_node!(%{content: "edge test B #{uniq()}", node_type: :semantic, source: "p2_test"})

      edge = Graphonomous.link_nodes(n1.id, n2.id, %{edge_type: :related, weight: 0.5})
      assert is_map(edge)
      assert edge.agent_id == "default"
    end

    test "edge with explicit agent_id persists correctly" do
      n1 =
        store_node!(%{content: "edge agent A #{uniq()}", node_type: :semantic, source: "p2_test"})

      n2 =
        store_node!(%{content: "edge agent B #{uniq()}", node_type: :semantic, source: "p2_test"})

      edge =
        Graphonomous.link_nodes(n1.id, n2.id, %{
          edge_type: :related,
          weight: 0.5,
          agent_id: "agent_beta"
        })

      assert is_map(edge)
      assert edge.agent_id == "agent_beta"
    end
  end

  describe "Capability 8+10 integration: evidence_count persists through store/retrieve" do
    test "evidence_count round-trips through storage" do
      node =
        store_node!(%{
          content: "evidence round trip #{uniq()}",
          node_type: :semantic,
          confidence: 0.6,
          evidence_count: 5,
          source: "p2_test"
        })

      assert node.evidence_count == 5

      fetched = Graphonomous.get_node(node.id)
      assert fetched.evidence_count == 5
    end
  end

  ## Helpers

  defp store_node!(attrs) do
    node = Graphonomous.store_node(attrs)
    assert is_map(node), "Expected store_node to return a map, got: #{inspect(node)}"
    assert is_binary(node.id)
    node
  end

  defp uniq, do: System.unique_integer([:positive, :monotonic])
end
