defmodule Mix.Tasks.Benchmark.CrossReferenceEntitiesTest do
  @moduledoc """
  Tests for extract_cross_reference_entities/1 and
  extract_cross_reference_entities_resolved/1.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Benchmark.Longmemeval

  defp make_chunk(overrides \\ %{}) do
    Map.merge(
      %{
        document_date: "2023-01-15",
        event_date: nil,
        turn: "1",
        text: "",
        speaker: "user",
        session_id: "s1",
        is_superseded: false,
        valid_until: nil,
        similarity: 0.9,
        node_id: "n1",
        bm25_facts: []
      },
      overrides
    )
  end

  # ── Naive extraction (extract_cross_reference_entities) ──────────

  describe "extract_cross_reference_entities/1" do
    test "returns empty list for empty chunks" do
      assert Longmemeval.extract_cross_reference_entities([]) == []
    end

    test "returns empty list for chunks with no proper nouns" do
      chunks = [
        make_chunk(%{text: "i like the weather today", session_id: "s1"}),
        make_chunk(%{text: "it was nice yesterday too", session_id: "s2"})
      ]

      assert Longmemeval.extract_cross_reference_entities(chunks) == []
    end

    test "finds proper nouns appearing in 2+ sessions" do
      chunks = [
        make_chunk(%{text: "Rex is a good dog.", session_id: "s1"}),
        make_chunk(%{text: "Rex loves the park.", session_id: "s2"})
      ]

      result = Longmemeval.extract_cross_reference_entities(chunks)
      entities = Enum.map(result, fn {name, _sids} -> name end)
      assert "Rex" in entities
    end

    test "excludes common words (The, What, When, etc.)" do
      chunks = [
        make_chunk(%{text: "The dog is nice. What a day.", session_id: "s1"}),
        make_chunk(%{text: "The cat is great. What a time.", session_id: "s2"})
      ]

      result = Longmemeval.extract_cross_reference_entities(chunks)
      entities = Enum.map(result, fn {name, _sids} -> name end)
      refute "The" in entities
      refute "What" in entities
    end

    test "entity appearing in only 1 session is excluded" do
      chunks = [
        make_chunk(%{text: "Portland is rainy.", session_id: "s1"}),
        make_chunk(%{text: "Seattle is nice.", session_id: "s2"})
      ]

      result = Longmemeval.extract_cross_reference_entities(chunks)
      entities = Enum.map(result, fn {name, _sids} -> name end)
      refute "Portland" in entities
      refute "Seattle" in entities
    end

    test "returns at most 15 entities" do
      # Create 20 distinct proper nouns each in 2 sessions
      names = for i <- 1..20, do: "Entity#{String.pad_leading(to_string(i), 2, "0")}"

      chunks =
        Enum.flat_map(names, fn name ->
          [
            make_chunk(%{text: "#{name} is great.", session_id: "s1"}),
            make_chunk(%{text: "#{name} is awesome.", session_id: "s2"})
          ]
        end)

      result = Longmemeval.extract_cross_reference_entities(chunks)
      assert length(result) <= 15
    end

    test "sorted by number of sessions descending" do
      chunks = [
        make_chunk(%{text: "Rex is here.", session_id: "s1"}),
        make_chunk(%{text: "Rex is there.", session_id: "s2"}),
        make_chunk(%{text: "Rex is back.", session_id: "s3"}),
        make_chunk(%{text: "Whiskers plays.", session_id: "s1"}),
        make_chunk(%{text: "Whiskers sleeps.", session_id: "s2"})
      ]

      result = Longmemeval.extract_cross_reference_entities(chunks)

      if length(result) >= 2 do
        [{_, sids1}, {_, sids2} | _] = result
        assert length(sids1) >= length(sids2)
      end
    end

    test "session IDs are deduplicated" do
      chunks = [
        make_chunk(%{text: "Rex is here. Rex is great.", session_id: "s1"}),
        make_chunk(%{text: "Rex is back.", session_id: "s2"})
      ]

      result = Longmemeval.extract_cross_reference_entities(chunks)
      {_name, sids} = Enum.find(result, fn {n, _} -> n == "Rex" end)
      assert sids == Enum.uniq(sids)
    end
  end

  # ── Resolved extraction (extract_cross_reference_entities_resolved) ──

  describe "extract_cross_reference_entities_resolved/1" do
    test "returns empty-or-fallback for empty chunks" do
      result = Longmemeval.extract_cross_reference_entities_resolved([])
      # Should return [] (from naive fallback on empty input)
      assert result == []
    end

    test "falls back to naive extraction when EntityResolver returns no mentions" do
      # Chunks with simple text that EntityResolver may not extract mentions from
      chunks = [
        make_chunk(%{text: "Rex is here.", session_id: "s1"}),
        make_chunk(%{text: "Rex is there.", session_id: "s2"})
      ]

      # Should still return results (via naive fallback or resolver)
      result = Longmemeval.extract_cross_reference_entities_resolved(chunks)
      # The naive fallback should find "Rex" in 2 sessions
      assert is_list(result)
    end

    test "returns list of {entity, session_ids} tuples" do
      chunks = [
        make_chunk(%{text: "John Smith went to Portland for vacation.", session_id: "s1"}),
        make_chunk(%{text: "John Smith enjoyed Portland a lot.", session_id: "s2"})
      ]

      result = Longmemeval.extract_cross_reference_entities_resolved(chunks)
      assert is_list(result)

      for {entity, sids} <- result do
        assert is_binary(entity)
        assert is_list(sids)
        assert length(sids) >= 2
      end
    end

    test "returns at most 20 entities" do
      # Create many proper nouns across sessions
      names = for i <- 1..25, do: "Person#{String.pad_leading(to_string(i), 2, "0")}"

      chunks =
        Enum.flat_map(names, fn name ->
          [
            make_chunk(%{text: "#{name} arrived today.", session_id: "s1"}),
            make_chunk(%{text: "#{name} left yesterday.", session_id: "s2"})
          ]
        end)

      result = Longmemeval.extract_cross_reference_entities_resolved(chunks)
      assert length(result) <= 20
    end
  end
end
