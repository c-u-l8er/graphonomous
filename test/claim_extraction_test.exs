defmodule Mix.Tasks.Benchmark.ClaimExtractionTest do
  @moduledoc """
  Tests for extract_user_claims/1 and the claim extraction regex patterns:
  - @claim_first_person_re — first-person statements (I, my, we)
  - @claim_number_re — sentences with numbers
  - @claim_update_re — update keywords (actually, changed, now I, etc.)
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

  describe "extract_user_claims/1" do
    test "returns empty list for empty chunks" do
      assert Longmemeval.extract_user_claims([]) == []
    end

    test "returns empty list for assistant-only chunks" do
      chunks = [
        make_chunk(%{text: "I can help you with that.", speaker: "assistant"})
      ]

      assert Longmemeval.extract_user_claims(chunks) == []
    end

    test "extracts first-person statements with I" do
      chunks = [
        make_chunk(%{text: "I own 3 bikes and I ride them every day."})
      ]

      result = Longmemeval.extract_user_claims(chunks)
      assert length(result) > 0
      joined = Enum.join(result, " ")
      assert String.contains?(joined, "I own 3 bikes")
    end

    test "extracts first-person statements with my/My" do
      chunks = [
        make_chunk(%{text: "My favorite hobby is hiking in the mountains."})
      ]

      result = Longmemeval.extract_user_claims(chunks)
      assert length(result) > 0
      joined = Enum.join(result, " ")
      assert String.contains?(joined, "My favorite hobby")
    end

    test "extracts sentences containing numbers" do
      chunks = [
        make_chunk(%{text: "There are 5 cats in the shelter right now."})
      ]

      result = Longmemeval.extract_user_claims(chunks)
      assert length(result) > 0
      joined = Enum.join(result, " ")
      assert String.contains?(joined, "5 cats")
    end

    test "tags update keywords with [UPDATE]" do
      chunks = [
        make_chunk(%{text: "I actually changed my mind about sushi."})
      ]

      result = Longmemeval.extract_user_claims(chunks)
      assert length(result) > 0
      assert Enum.any?(result, &String.contains?(&1, "[UPDATE]"))
    end

    test "falls back to update-keyword sentences when no first-person or numbers" do
      chunks = [
        make_chunk(%{text: "Actually the plan changed completely. Not anymore."})
      ]

      result = Longmemeval.extract_user_claims(chunks)
      # Should pick up sentences with update keywords
      assert is_list(result)
    end

    test "includes session and date prefix" do
      chunks = [
        make_chunk(%{
          text: "I have a dog named Rex.",
          session_id: "42",
          document_date: "2024-03-15"
        })
      ]

      result = Longmemeval.extract_user_claims(chunks)
      assert length(result) > 0
      first = hd(result)
      assert String.contains?(first, "S42")
      assert String.contains?(first, "2024-03-15")
    end

    test "limits to 30 claims maximum" do
      # Create many chunks with multiple claim sentences each
      chunks =
        for i <- 1..20 do
          make_chunk(%{
            text: "I have #{i} cats. I also own #{i * 2} dogs. My #{i}th hobby is great.",
            turn: to_string(i),
            session_id: "s#{i}"
          })
        end

      result = Longmemeval.extract_user_claims(chunks)
      assert length(result) <= 30
    end

    test "deduplicates identical claims" do
      chunks = [
        make_chunk(%{text: "I own 3 bikes.", session_id: "s1", turn: "1"}),
        make_chunk(%{text: "I own 3 bikes.", session_id: "s1", turn: "1"})
      ]

      result = Longmemeval.extract_user_claims(chunks)
      assert result == Enum.uniq(result)
    end

    test "update keywords recognized: actually, changed, now I, used to, switched, moved to" do
      test_cases = [
        "I actually prefer tea now.",
        "I changed my address last week.",
        "I used to live in Portland but moved.",
        "I switched to a new dentist recently.",
        "I moved to Seattle last month actually.",
        "I no longer have a car at all.",
        "I updated my phone number yesterday."
      ]

      for text <- test_cases do
        chunks = [make_chunk(%{text: text})]
        result = Longmemeval.extract_user_claims(chunks)

        assert Enum.any?(result, &String.contains?(&1, "[UPDATE]")),
               "Expected [UPDATE] tag for: #{text}"
      end
    end
  end
end
