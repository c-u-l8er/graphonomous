defmodule Graphonomous.SpecComplianceTest do
  @moduledoc """
  Tests for spec compliance features added in v0.2.0:
  - New node types (temporal, outcome, goal)
  - New node fields (causal_parent_ids, creation_source, timescale, decay_rate)
  - New edge types (causes, resolves, related_to, part_of, follows, supersedes,
    depends_on, similar_to, temporal_before, temporal_after, co_occurs)
  - New edge fields (co_activation_count, decay_rate)
  - New Store APIs (list_all_edges, update_edge, delete_edge)
  - Spec-aligned defaults (timescale: medium, creation_source: inference, weight: 0.3)
  """

  use ExUnit.Case, async: false

  alias Graphonomous.{Graph, Store}

  setup do
    {:ok, nodes} = Graph.list_nodes(%{})
    Enum.each(nodes, fn node -> _ = Graph.delete_node(node.id) end)

    {:ok, edges} = Graph.list_all_edges()
    Enum.each(edges, fn edge -> _ = Graph.delete_edge(edge.id) end)

    :ok
  end

  # ─── Node Types ───────────────────────────────────────────────────

  describe "node types" do
    test "temporal node type round-trips through store" do
      {:ok, node} =
        Graph.store_node(%{
          content: "CPU spike observed at 14:00 UTC",
          node_type: "temporal",
          confidence: 0.8,
          source: "monitoring"
        })

      assert node.node_type == :temporal
      assert {:ok, fetched} = Graph.get_node(node.id)
      assert fetched.node_type == :temporal
    end

    test "outcome node type round-trips through store" do
      {:ok, node} =
        Graph.store_node(%{
          content: "Retrieval F1=0.667 on portfolio corpus",
          node_type: "outcome",
          confidence: 0.95,
          source: "benchmark"
        })

      assert node.node_type == :outcome
      assert {:ok, fetched} = Graph.get_node(node.id)
      assert fetched.node_type == :outcome
    end

    test "goal node type round-trips through store" do
      {:ok, node} =
        Graph.store_node(%{
          content: "Achieve F1 > 0.8 on LongMemEval",
          node_type: "goal",
          confidence: 0.5,
          source: "planning"
        })

      assert node.node_type == :goal
      assert {:ok, fetched} = Graph.get_node(node.id)
      assert fetched.node_type == :goal
    end

    test "list_nodes filters by new node types" do
      {:ok, _} = Graph.store_node(%{content: "temporal event", node_type: "temporal"})
      {:ok, _} = Graph.store_node(%{content: "outcome data", node_type: "outcome"})
      {:ok, _} = Graph.store_node(%{content: "goal intent", node_type: "goal"})
      {:ok, _} = Graph.store_node(%{content: "semantic fact", node_type: "semantic"})

      {:ok, temporal} = Graph.list_nodes(%{node_type: :temporal})
      assert length(temporal) == 1
      assert hd(temporal).node_type == :temporal

      {:ok, outcomes} = Graph.list_nodes(%{node_type: :outcome})
      assert length(outcomes) == 1

      {:ok, goals} = Graph.list_nodes(%{node_type: :goal})
      assert length(goals) == 1
    end

    test "all six node types survive cache rebuild" do
      types = [:episodic, :semantic, :procedural, :temporal, :outcome, :goal]

      ids =
        Enum.map(types, fn type ->
          {:ok, node} =
            Store.insert_node(%{
              content: "#{type} node",
              node_type: type,
              confidence: 0.7
            })

          node.id
        end)

      assert :ok = Store.rebuild_cache()

      Enum.zip(ids, types)
      |> Enum.each(fn {id, expected_type} ->
        assert {:ok, node} = Store.get_node(id)
        assert node.node_type == expected_type
      end)
    end
  end

  # ─── Node Fields ──────────────────────────────────────────────────

  describe "node fields" do
    test "causal_parent_ids persists and round-trips" do
      parent_ids = ["node_abc123", "node_def456"]

      {:ok, node} =
        Store.insert_node(%{
          content: "Derived from two parent nodes",
          node_type: :outcome,
          causal_parent_ids: parent_ids
        })

      assert node.causal_parent_ids == parent_ids

      assert :ok = Store.rebuild_cache()
      assert {:ok, fetched} = Store.get_node(node.id)
      assert fetched.causal_parent_ids == parent_ids
    end

    test "creation_source defaults to :inference per spec" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Node with default creation_source",
          node_type: :semantic
        })

      assert node.creation_source == :inference
    end

    test "creation_source can be set to all valid values" do
      for source <- [:manual, :inference, :consolidation, :federation] do
        {:ok, node} =
          Store.insert_node(%{
            content: "Node with #{source} source",
            node_type: :semantic,
            creation_source: source
          })

        assert node.creation_source == source
      end
    end

    test "creation_source survives cache rebuild" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Consolidation-created node",
          node_type: :semantic,
          creation_source: :consolidation
        })

      assert :ok = Store.rebuild_cache()
      assert {:ok, fetched} = Store.get_node(node.id)
      assert fetched.creation_source == :consolidation
    end

    test "timescale defaults to :medium per spec" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Node with default timescale",
          node_type: :semantic
        })

      assert node.timescale == :medium
    end

    test "timescale can be set to all valid values" do
      for ts <- [:fast, :medium, :slow, :glacial] do
        {:ok, node} =
          Store.insert_node(%{
            content: "#{ts} timescale node",
            node_type: :semantic,
            timescale: ts
          })

        assert node.timescale == ts
      end
    end

    test "timescale survives cache rebuild" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Glacial timescale node",
          node_type: :semantic,
          timescale: :glacial
        })

      assert :ok = Store.rebuild_cache()
      assert {:ok, fetched} = Store.get_node(node.id)
      assert fetched.timescale == :glacial
    end

    test "decay_rate persists as float and round-trips" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Node with custom decay",
          node_type: :episodic,
          decay_rate: 0.05
        })

      assert_in_delta node.decay_rate, 0.05, 1.0e-6

      assert :ok = Store.rebuild_cache()
      assert {:ok, fetched} = Store.get_node(node.id)
      assert_in_delta fetched.decay_rate, 0.05, 1.0e-6
    end

    test "decay_rate defaults to nil when not set" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Node without custom decay",
          node_type: :semantic
        })

      assert node.decay_rate == nil
    end

    test "update_node preserves new fields" do
      {:ok, node} =
        Store.insert_node(%{
          content: "Original",
          node_type: :temporal,
          causal_parent_ids: ["parent1"],
          creation_source: :manual,
          timescale: :fast,
          decay_rate: 0.03
        })

      {:ok, updated} =
        Store.update_node(node.id, %{
          content: "Updated",
          timescale: :slow,
          causal_parent_ids: ["parent1", "parent2"]
        })

      assert updated.content == "Updated"
      assert updated.timescale == :slow
      assert updated.causal_parent_ids == ["parent1", "parent2"]
      assert updated.creation_source == :manual
      assert_in_delta updated.decay_rate, 0.03, 1.0e-6
    end
  end

  # ─── Edge Types ───────────────────────────────────────────────────

  describe "edge types" do
    setup do
      {:ok, src} = Graph.store_node(%{content: "Source", node_type: "semantic"})
      {:ok, tgt} = Graph.store_node(%{content: "Target", node_type: "semantic"})
      %{src: src, tgt: tgt}
    end

    @new_edge_types [
      :causes,
      :resolves,
      :related_to,
      :part_of,
      :follows,
      :supersedes,
      :depends_on,
      :similar_to,
      :temporal_before,
      :temporal_after,
      :co_occurs
    ]

    test "all new edge types round-trip through store", %{src: src, tgt: tgt} do
      for edge_type <- @new_edge_types do
        {:ok, edge} =
          Graph.create_edge(src.id, tgt.id, %{
            edge_type: edge_type,
            weight: 0.7
          })

        assert edge.edge_type == edge_type,
               "Expected edge_type #{inspect(edge_type)}, got #{inspect(edge.edge_type)}"
      end
    end

    test "new edge types normalize from strings", %{src: src, tgt: tgt} do
      for type_str <- [
            "causes",
            "resolves",
            "part_of",
            "follows",
            "supersedes",
            "depends_on",
            "similar_to",
            "temporal_before",
            "temporal_after",
            "co_occurs",
            "related_to"
          ] do
        {:ok, edge} =
          Graph.create_edge(src.id, tgt.id, %{
            edge_type: type_str,
            weight: 0.6
          })

        assert edge.edge_type == String.to_existing_atom(type_str)
      end
    end

    test "backward-compatible edge types still work", %{src: src, tgt: tgt} do
      for {type, expected} <- [
            {:causal, :causal},
            {:related, :related},
            {:contradicts, :contradicts},
            {:supports, :supports},
            {:derived_from, :derived_from}
          ] do
        {:ok, edge} =
          Graph.create_edge(src.id, tgt.id, %{edge_type: type, weight: 0.5})

        assert edge.edge_type == expected
      end
    end
  end

  # ─── Edge Fields ──────────────────────────────────────────────────

  describe "edge fields" do
    setup do
      {:ok, src} = Graph.store_node(%{content: "Source", node_type: "semantic"})
      {:ok, tgt} = Graph.store_node(%{content: "Target", node_type: "semantic"})
      %{src: src, tgt: tgt}
    end

    test "co_activation_count defaults to 0", %{src: src, tgt: tgt} do
      {:ok, edge} =
        Graph.create_edge(src.id, tgt.id, %{edge_type: :related, weight: 0.5})

      assert edge.co_activation_count == 0
    end

    test "co_activation_count can be set and persists", %{src: src, tgt: tgt} do
      {:ok, edge} =
        Store.upsert_edge(%{
          source_id: src.id,
          target_id: tgt.id,
          edge_type: :related,
          weight: 0.5,
          co_activation_count: 7
        })

      assert edge.co_activation_count == 7

      assert :ok = Store.rebuild_cache()
      {:ok, edges} = Store.list_edges_for_node(src.id)
      found = Enum.find(edges, &(&1.id == edge.id))
      assert found.co_activation_count == 7
    end

    test "edge decay_rate persists", %{src: src, tgt: tgt} do
      {:ok, edge} =
        Store.upsert_edge(%{
          source_id: src.id,
          target_id: tgt.id,
          edge_type: :causal,
          weight: 0.8,
          decay_rate: 0.01
        })

      assert_in_delta edge.decay_rate, 0.01, 1.0e-6

      assert :ok = Store.rebuild_cache()
      {:ok, edges} = Store.list_edges_for_node(src.id)
      found = Enum.find(edges, &(&1.id == edge.id))
      assert_in_delta found.decay_rate, 0.01, 1.0e-6
    end

    test "edge weight defaults to 0.3 per spec", %{src: src, tgt: tgt} do
      {:ok, edge} =
        Store.upsert_edge(%{
          source_id: src.id,
          target_id: tgt.id,
          edge_type: :related
        })

      assert_in_delta edge.weight, 0.3, 1.0e-6
    end
  end

  # ─── Store APIs ───────────────────────────────────────────────────

  describe "new Store APIs" do
    setup do
      {:ok, a} = Graph.store_node(%{content: "Node A", node_type: "semantic"})
      {:ok, b} = Graph.store_node(%{content: "Node B", node_type: "semantic"})

      {:ok, edge} =
        Graph.create_edge(a.id, b.id, %{edge_type: :supports, weight: 0.7})

      %{a: a, b: b, edge: edge}
    end

    test "list_all_edges returns all edges", %{edge: edge} do
      {:ok, all_edges} = Graph.list_all_edges()
      assert Enum.any?(all_edges, &(&1.id == edge.id))
    end

    test "update_edge modifies weight and co_activation_count", %{edge: edge} do
      {:ok, updated} =
        Graph.update_edge(edge.id, %{weight: 0.95, co_activation_count: 3})

      assert_in_delta updated.weight, 0.95, 1.0e-6
      assert updated.co_activation_count == 3
    end

    test "update_edge returns error for non-existent edge" do
      assert {:error, :not_found} = Graph.update_edge("nonexistent_edge", %{weight: 0.5})
    end

    test "delete_edge removes edge from store", %{edge: edge, a: a} do
      assert :ok = Graph.delete_edge(edge.id)
      {:ok, edges} = Graph.get_edges_for_node(a.id)
      refute Enum.any?(edges, &(&1.id == edge.id))
    end

    test "delete_edge + rebuild_cache confirms persistence", %{edge: edge, a: a} do
      assert :ok = Graph.delete_edge(edge.id)
      assert :ok = Store.rebuild_cache()
      {:ok, edges} = Graph.get_edges_for_node(a.id)
      refute Enum.any?(edges, &(&1.id == edge.id))
    end
  end

  # ─── Spec Defaults ────────────────────────────────────────────────

  describe "spec-aligned defaults" do
    test "node timescale defaults to :medium" do
      {:ok, node} = Graph.store_node(%{content: "Default timescale", node_type: "semantic"})
      assert node.timescale == :medium
    end

    test "node creation_source defaults to :inference" do
      {:ok, node} = Graph.store_node(%{content: "Default source", node_type: "semantic"})
      assert node.creation_source == :inference
    end

    test "edge weight defaults to 0.3" do
      {:ok, src} = Graph.store_node(%{content: "S", node_type: "semantic"})
      {:ok, tgt} = Graph.store_node(%{content: "T", node_type: "semantic"})
      {:ok, edge} = Graph.create_edge(src.id, tgt.id, %{edge_type: :related})
      assert_in_delta edge.weight, 0.3, 1.0e-6
    end
  end

  # ─── DDL Migrations ──────────────────────────────────────────────

  describe "DDL migrations" do
    test "new migrations are tracked in schema_migrations" do
      db_path = "tmp/graphonomous_test.db"
      {:ok, conn} = Exqlite.Sqlite3.open(db_path)

      on_exit(fn -> _ = Exqlite.Sqlite3.close(conn) end)

      {:ok, stmt} =
        Exqlite.Sqlite3.prepare(conn, "SELECT id FROM schema_migrations ORDER BY id;")

      {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
      _ = Exqlite.Sqlite3.release(conn, stmt)

      ids = Enum.map(rows, fn [id] -> to_string(id) end)

      assert "2026_04_02_node_spec_fields" in ids
      assert "2026_04_02_edge_spec_fields" in ids
    end
  end
end
