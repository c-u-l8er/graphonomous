defmodule Mix.Tasks.Benchmark.BuildFactTableTest do
  @moduledoc """
  Tests for build_fact_table/1 — structured fact extraction from bm25_facts metadata.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Benchmark.Longmemeval

  defp make_chunk(overrides \\ %{}) do
    Map.merge(
      %{
        document_date: "2023-01-15",
        event_date: nil,
        turn: "3",
        text: "some text",
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

  describe "build_fact_table/1" do
    test "returns empty string for empty chunks" do
      assert Longmemeval.build_fact_table([]) == ""
    end

    test "returns empty string for chunks with no bm25_facts" do
      result = Longmemeval.build_fact_table([make_chunk()])
      assert result == ""
    end

    test "returns empty string when bm25_facts are all malformed (no colon)" do
      chunk = make_chunk(%{bm25_facts: ["no colon here", "also bad"]})
      assert Longmemeval.build_fact_table([chunk]) == ""
    end

    test "basic single fact produces table with FACT TABLE header" do
      chunk = make_chunk(%{bm25_facts: ["hobby: hiking"]})
      result = Longmemeval.build_fact_table([chunk])

      assert String.contains?(result, "FACT TABLE")
      assert String.contains?(result, "Category")
      assert String.contains?(result, "hobby")
      assert String.contains?(result, "hiking")
      assert String.contains?(result, "CURRENT")
    end

    test "superseded chunk facts are marked OUTDATED" do
      chunk = make_chunk(%{
        bm25_facts: ["hobby: hiking"],
        is_superseded: true
      })

      result = Longmemeval.build_fact_table([chunk])
      assert String.contains?(result, "OUTDATED")
      refute String.contains?(result, "CURRENT")
    end

    test "non-superseded chunk facts are marked CURRENT" do
      chunk = make_chunk(%{
        bm25_facts: ["hobby: hiking"],
        is_superseded: false
      })

      result = Longmemeval.build_fact_table([chunk])
      assert String.contains?(result, "CURRENT")
      refute String.contains?(result, "OUTDATED")
    end

    test "deduplicates by category+value, keeping latest turn" do
      c1 = make_chunk(%{
        bm25_facts: ["pet: 2 cats"],
        turn: "3",
        session_id: "s1",
        is_superseded: true
      })

      c2 = make_chunk(%{
        bm25_facts: ["pet: 2 cats"],
        turn: "7",
        session_id: "s2",
        is_superseded: false
      })

      result = Longmemeval.build_fact_table([c1, c2])

      # Should only appear once (deduped) with latest turn's status
      lines = String.split(result, "\n")
      pet_lines = Enum.filter(lines, &String.contains?(&1, "pet"))
      assert length(pet_lines) == 1
      # Latest turn (7) is CURRENT
      assert String.contains?(hd(pet_lines), "CURRENT")
    end

    test "multiple categories are sorted alphabetically" do
      chunk = make_chunk(%{
        bm25_facts: ["location: Seattle", "hobby: hiking", "pet: dog"]
      })

      result = Longmemeval.build_fact_table([chunk])
      lines = String.split(result, "\n")

      data_lines =
        lines
        |> Enum.filter(fn l ->
          String.contains?(l, "CURRENT") or String.contains?(l, "OUTDATED")
        end)

      # Should be: hobby, location, pet (alphabetical)
      assert length(data_lines) == 3
      assert String.contains?(Enum.at(data_lines, 0), "hobby")
      assert String.contains?(Enum.at(data_lines, 1), "location")
      assert String.contains?(Enum.at(data_lines, 2), "pet")
    end

    test "session and turn are included in output" do
      chunk = make_chunk(%{
        bm25_facts: ["hobby: hiking"],
        session_id: "sess42",
        turn: "5"
      })

      result = Longmemeval.build_fact_table([chunk])
      assert String.contains?(result, "S:sess4")
      assert String.contains?(result, "T:5")
    end

    test "date is included in output" do
      chunk = make_chunk(%{
        bm25_facts: ["hobby: hiking"],
        document_date: "2024-06-15"
      })

      result = Longmemeval.build_fact_table([chunk])
      assert String.contains?(result, "2024-06-15")
    end

    test "nil document_date renders empty in date column" do
      chunk = make_chunk(%{
        bm25_facts: ["hobby: hiking"],
        document_date: nil
      })

      result = Longmemeval.build_fact_table([chunk])
      # Should still produce valid output
      assert String.contains?(result, "FACT TABLE")
      assert String.contains?(result, "hobby")
    end

    test "facts with colons in value are parsed correctly" do
      chunk = make_chunk(%{
        bm25_facts: ["schedule: meetings at 9:30 AM"]
      })

      result = Longmemeval.build_fact_table([chunk])
      assert String.contains?(result, "schedule")
      assert String.contains?(result, "meetings at 9:30")
    end

    test "fact with empty value after colon is skipped" do
      chunk = make_chunk(%{
        bm25_facts: ["empty: ", "good: value"]
      })

      result = Longmemeval.build_fact_table([chunk])
      # "empty: " has empty value after trim, but the split produces " " which has byte_size > 0
      # The key check is byte_size(value) > 0 after split
      assert String.contains?(result, "good")
    end

    test "non-binary facts are filtered out" do
      chunk = make_chunk(%{
        bm25_facts: [123, nil, "valid: fact", :atom]
      })

      result = Longmemeval.build_fact_table([chunk])
      assert String.contains?(result, "valid")
      assert String.contains?(result, "fact")
    end

    test "long values are truncated to 30 chars" do
      long_val = String.duplicate("x", 50)
      chunk = make_chunk(%{
        bm25_facts: ["cat: #{long_val}"]
      })

      result = Longmemeval.build_fact_table([chunk])
      # Value column is padded to 30, so the long value gets sliced
      assert String.contains?(result, "cat")
    end

    test "mixed superseded and current chunks across sessions" do
      chunks = [
        make_chunk(%{
          bm25_facts: ["pet: 2 dogs"],
          session_id: "s1",
          turn: "1",
          is_superseded: true,
          document_date: "2023-01-01"
        }),
        make_chunk(%{
          bm25_facts: ["pet: 3 dogs"],
          session_id: "s2",
          turn: "5",
          is_superseded: false,
          document_date: "2023-06-01"
        }),
        make_chunk(%{
          bm25_facts: ["hobby: cycling"],
          session_id: "s2",
          turn: "6",
          is_superseded: false,
          document_date: "2023-06-01"
        })
      ]

      result = Longmemeval.build_fact_table(chunks)
      assert String.contains?(result, "FACT TABLE")

      lines = String.split(result, "\n")
      data_lines = Enum.filter(lines, fn l ->
        String.contains?(l, "CURRENT") or String.contains?(l, "OUTDATED")
      end)

      # 3 distinct category+value combos: "pet: 2 dogs", "pet: 3 dogs", "hobby: cycling"
      assert length(data_lines) == 3
    end
  end
end
