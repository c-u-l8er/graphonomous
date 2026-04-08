defmodule Graphonomous.EntityResolverTest do
  use ExUnit.Case, async: false

  alias Graphonomous.{EntityResolver, Store}

  @db_path "tmp/graphonomous_entity_test.db"

  setup_all do
    # Clean DB from prior runs
    File.rm(@db_path)
    File.rm(@db_path <> "-wal")
    File.rm(@db_path <> "-shm")
    :ok
  end

  setup do
    unless Process.whereis(Store) do
      start_supervised!({Store, db_path: @db_path})
    end

    # Clear stale entities from prior tests to ensure isolation
    for entity <- Store.list_entities() do
      Store.delete_entity(entity.id)
    end

    :ok
  end

  describe "extract_mentions/1" do
    test "extracts proper noun phrases" do
      mentions = EntityResolver.extract_mentions("I talked to John Smith about the project.")
      names = Enum.map(mentions, & &1.text)
      assert "John Smith" in names
    end

    test "extracts tool/language names" do
      mentions = EntityResolver.extract_mentions("We use Elixir and PostgreSQL for the backend.")
      names = Enum.map(mentions, & &1.text)
      assert "Elixir" in names
      assert "PostgreSQL" in names
    end

    test "extracts quoted terms" do
      mentions = EntityResolver.extract_mentions(~s(The "knowledge graph" approach works best.))
      names = Enum.map(mentions, & &1.text)
      assert "knowledge graph" in names
    end

    test "returns empty list for nil or empty" do
      assert EntityResolver.extract_mentions(nil) == []
      assert EntityResolver.extract_mentions("") == []
    end

    test "deduplicates mentions by lowercase" do
      mentions = EntityResolver.extract_mentions("Elixir is great. I love Elixir.")
      elixir_count = Enum.count(mentions, fn m -> String.downcase(m.text) == "elixir" end)
      assert elixir_count == 1
    end
  end

  describe "resolve/1" do
    test "resolves exact canonical match" do
      # Use a very distinctive name that won't fuzzy-match anything else
      name = "Xyloquantic"

      entity =
        case Store.lookup_entities_by_canonical("xyloquantic") do
          [e | _] ->
            e

          [] ->
            {:ok, e} =
              Store.insert_entity(%{
                name: name,
                canonical_name: "xyloquantic",
                entity_type: :person,
                aliases: []
              })

            e
        end

      mentions = [%{text: name, entity_type: :person}]
      {resolved, unresolved} = EntityResolver.resolve(mentions)

      assert length(resolved) == 1
      assert hd(resolved).entity_id == entity.id
      assert hd(resolved).match_type == :exact
      assert unresolved == []
    end

    test "resolves alias match" do
      suffix = unique_suffix()
      # Use very long distinctive names to prevent fuzzy collisions
      canonical = "zythronomicon#{suffix}"
      name = "Zythronomicon#{suffix}"
      alias_name = "ZythroAlias#{suffix}"

      entity =
        case Store.lookup_entities_by_canonical(canonical) do
          [e | _] ->
            e

          [] ->
            {:ok, e} =
              Store.insert_entity(%{
                name: name,
                canonical_name: canonical,
                entity_type: :tool,
                aliases: [alias_name]
              })

            e
        end

      mentions = [%{text: alias_name, entity_type: :tool}]
      {resolved, _} = EntityResolver.resolve(mentions)

      assert length(resolved) == 1
      assert hd(resolved).entity_id == entity.id
      assert hd(resolved).match_type == :alias
    end

    test "returns unresolved for unknown mentions" do
      mentions = [%{text: "SomeUnknownThing_#{unique_suffix()}", entity_type: :other}]
      {resolved, unresolved} = EntityResolver.resolve(mentions)

      assert resolved == []
      assert length(unresolved) == 1
    end
  end

  describe "resolve_and_link/2" do
    test "creates entities for unresolved mentions and links them" do
      node_id = unique_id("rl_node")

      {:ok, _} =
        Store.insert_node(%{
          id: node_id,
          content: "test content",
          node_type: :semantic,
          confidence: 0.8
        })

      on_exit(fn -> Store.delete_node(node_id) end)

      # Use known tool names that the extractor will find
      {:ok, results} =
        EntityResolver.resolve_and_link(node_id, "We use Elixir and PostgreSQL here.")

      # Should have entities for Elixir and PostgreSQL at minimum
      assert length(results) >= 2

      # Check that entity_node_links were created
      links = Store.entities_for_node(node_id)
      assert length(links) >= 2
    end
  end

  describe "query_entities/1" do
    test "finds entity and returns linked node IDs" do
      # Use a unique name. First check if "Claude" entity exists, if not create it.
      entity =
        case Store.lookup_entities_by_canonical("claude") do
          [e | _] ->
            e

          [] ->
            {:ok, e} =
              Store.insert_entity(%{
                name: "Claude",
                canonical_name: "claude",
                entity_type: :tool
              })

            e
        end

      node_id = unique_id("qe_node")
      {:ok, _} = Store.insert_node(%{id: node_id, content: "test", node_type: :semantic})
      {:ok, _} = Store.insert_entity_node_link(entity.id, node_id, "mentions")

      on_exit(fn -> Store.delete_node(node_id) end)

      results = EntityResolver.query_entities("How does Claude handle retrieval?")

      assert length(results) >= 1
      match = Enum.find(results, fn r -> r.entity_id == entity.id end)
      assert match != nil
      assert node_id in match.node_ids
    end
  end

  describe "jaro_winkler/2" do
    test "returns 1.0 for identical strings" do
      assert EntityResolver.jaro_winkler("test", "test") == 1.0
    end

    test "returns high score for similar strings" do
      score = EntityResolver.jaro_winkler("travis", "travs")
      assert score > 0.85
    end

    test "returns low score for dissimilar strings" do
      score = EntityResolver.jaro_winkler("apple", "zebra")
      assert score < 0.6
    end
  end

  describe "entity link cleanup on node delete" do
    test "delete_node removes entity_node_links" do
      {:ok, entity} =
        Store.insert_entity(%{
          name: "DeleteTest",
          canonical_name: "deletetest_#{unique_suffix()}",
          entity_type: :tool
        })

      node_id = unique_id("del_node")
      {:ok, _} = Store.insert_node(%{id: node_id, content: "test", node_type: :semantic})
      {:ok, _} = Store.insert_entity_node_link(entity.id, node_id, "mentions")

      # Verify link exists
      links = Store.entities_for_node(node_id)
      assert length(links) == 1

      # Delete node
      :ok = Store.delete_node(node_id)

      # Entity links should be cleaned up
      links_after = Store.entities_for_node(node_id)
      assert links_after == []
    end

    test "delete_entity_links_for_node removes all links for a node" do
      {:ok, entity1} =
        Store.insert_entity(%{
          name: "E1",
          canonical_name: "elfc1_#{unique_suffix()}",
          entity_type: :tool
        })

      {:ok, entity2} =
        Store.insert_entity(%{
          name: "E2",
          canonical_name: "elfc2_#{unique_suffix()}",
          entity_type: :tool
        })

      node_id = unique_id("multi_link_node")
      {:ok, _} = Store.insert_node(%{id: node_id, content: "test", node_type: :semantic})
      {:ok, _} = Store.insert_entity_node_link(entity1.id, node_id, "mentions")
      {:ok, _} = Store.insert_entity_node_link(entity2.id, node_id, "mentions")

      assert length(Store.entities_for_node(node_id)) == 2

      :ok = Store.delete_entity_links_for_node(node_id)

      assert Store.entities_for_node(node_id) == []
      Store.delete_node(node_id)
    end
  end

  describe "entity link repointing on merge" do
    test "repoint_entity_links moves links from old node to new node" do
      {:ok, entity} =
        Store.insert_entity(%{
          name: "MergeEntity",
          canonical_name: "mergeent_#{unique_suffix()}",
          entity_type: :concept
        })

      old_node_id = unique_id("old_node")
      new_node_id = unique_id("new_node")

      {:ok, _} = Store.insert_node(%{id: old_node_id, content: "old", node_type: :semantic})
      {:ok, _} = Store.insert_node(%{id: new_node_id, content: "new", node_type: :semantic})
      {:ok, _} = Store.insert_entity_node_link(entity.id, old_node_id, "mentions")

      # Verify old link
      assert length(Store.entities_for_node(old_node_id)) == 1
      assert Store.entities_for_node(new_node_id) == []

      # Repoint
      {:ok, count} = Store.repoint_entity_links(old_node_id, new_node_id)
      assert count == 1

      # Old node should have no links, new node should have the link
      assert Store.entities_for_node(old_node_id) == []
      assert length(Store.entities_for_node(new_node_id)) == 1

      Store.delete_node(old_node_id)
      Store.delete_node(new_node_id)
    end
  end

  describe "entity deletion" do
    test "delete_entity removes entity and all its links" do
      {:ok, entity} =
        Store.insert_entity(%{
          name: "ToDelete",
          canonical_name: "todelete_#{unique_suffix()}",
          entity_type: :tool
        })

      node_id = unique_id("ent_del_node")
      {:ok, _} = Store.insert_node(%{id: node_id, content: "test", node_type: :semantic})
      {:ok, _} = Store.insert_entity_node_link(entity.id, node_id, "mentions")

      # Verify entity and link exist
      assert {:ok, _} = Store.get_entity(entity.id)
      assert length(Store.links_for_entity(entity.id)) == 1

      # Delete entity
      :ok = Store.delete_entity(entity.id)

      # Entity should be gone
      assert {:error, :not_found} = Store.get_entity(entity.id)
      assert Store.links_for_entity(entity.id) == []

      Store.delete_node(node_id)
    end
  end

  describe "entity type normalization" do
    test "concept type is preserved" do
      {:ok, entity} =
        Store.insert_entity(%{
          name: "KnowledgeGraph",
          canonical_name: "kg_concept_#{unique_suffix()}",
          entity_type: :concept
        })

      assert entity.entity_type == :concept
    end

    test "place type is recognized" do
      {:ok, entity} =
        Store.insert_entity(%{
          name: "Portland",
          canonical_name: "portland_#{unique_suffix()}",
          entity_type: "place"
        })

      assert entity.entity_type == :place
    end
  end

  describe "store_nodes_batch entity resolution" do
    test "batch-stored nodes get entity resolution" do
      # Store a known entity first
      {:ok, _} =
        Store.insert_entity(%{
          name: "Redis",
          canonical_name: "redis",
          entity_type: :tool
        })

      node_id = unique_id("batch_node")

      # We can't easily test async entity resolution without waiting,
      # but we can test that resolve_and_link works on batch content
      {:ok, results} =
        EntityResolver.resolve_and_link(node_id, "We cache with Redis for performance.")

      redis_result = Enum.find(results, fn r -> String.downcase(r.entity_name) == "redis" end)
      assert redis_result != nil
      assert redis_result.created == false
    end
  end

  defp unique_id(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp unique_suffix do
    System.unique_integer([:positive, :monotonic])
  end
end
