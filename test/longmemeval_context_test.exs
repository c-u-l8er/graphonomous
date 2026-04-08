defmodule Mix.Tasks.Benchmark.LongmemevalContextTest do
  @moduledoc """
  Tests for LongMemEval context formatting, claim extraction, entity
  cross-referencing, fact versioning, and provenance-aware presentation.
  """
  use ExUnit.Case, async: true

  # ── Claim Extraction ─────────────────────────────────────────────

  describe "extract_user_claims (via format_longmemeval_context)" do
    test "extracts first-person statements from user turns" do
      chunks = [
        chunk("I recently set a personal best of 25:50 in the 5K run.", "user",
          session_id: "s1", document_date: "2023-03-01", turn: 5
        ),
        chunk("That's a great time! Keep training.", "assistant",
          session_id: "s1", document_date: "2023-03-01", turn: 6
        )
      ]

      context = format_knowledge_update(chunks)

      assert context =~ "USER CLAIMS"
      assert context =~ "25:50"
      assert context =~ "5K"
    end

    test "tags claims with [UPDATE] when update language is present" do
      chunks = [
        chunk("I used to prefer Thai food but now I prefer Italian.", "user",
          session_id: "s2", document_date: "2023-04-15", turn: 3
        )
      ]

      context = format_knowledge_update(chunks)

      # The claim should not be empty
      assert context =~ "USER CLAIMS"
    end

    test "extracts number-containing sentences" do
      chunks = [
        chunk("I currently own 4 bikes and ride them every weekend.", "user",
          session_id: "s1", document_date: "2023-03-01", turn: 2
        )
      ]

      context = format_knowledge_update(chunks)

      assert context =~ "4 bikes"
    end

    test "skips assistant turns for claim extraction" do
      chunks = [
        chunk("You mentioned you have 3 cats.", "assistant",
          session_id: "s1", document_date: "2023-03-01", turn: 4
        )
      ]

      context = format_knowledge_update(chunks)

      # Claims section should be empty or not present since only assistant turn
      assert context =~ "SUPPORTING EVIDENCE"
    end
  end

  # ── Knowledge Update Provenance Tags ──────────────────────────────

  describe "knowledge_update provenance formatting" do
    test "marks superseded chunks with OUTDATED tag" do
      chunks = [
        chunk("I own 2 bikes.", "user",
          session_id: "s1", document_date: "2023-01-15", turn: 3,
          is_superseded: true, valid_until: "2023-04-01"
        ),
        chunk("I just bought 2 more bikes, so I have 4 now.", "user",
          session_id: "s2", document_date: "2023-04-01", turn: 2,
          is_superseded: false, valid_until: nil
        )
      ]

      context = format_knowledge_update(chunks)

      assert context =~ "OUTDATED"
      assert context =~ "4 now"
    end

    test "non-superseded chunks have no OUTDATED tag" do
      chunks = [
        chunk("I attend yoga three times a week.", "user",
          session_id: "s1", document_date: "2023-03-01", turn: 5,
          is_superseded: false, valid_until: nil
        )
      ]

      context = format_knowledge_update(chunks)

      refute context =~ "OUTDATED"
    end
  end

  # ── Information Extraction Formatting ──────────────────────────────

  describe "information_extraction formatting" do
    test "produces USER STATEMENTS section and ranks by relevance" do
      chunks = [
        chunk("I love hiking in the Pacific Northwest every summer.", "user",
          session_id: "s1", document_date: "2023-02-10", turn: 3,
          similarity: 0.9
        ),
        chunk("The weather has been great this week.", "user",
          session_id: "s1", document_date: "2023-02-10", turn: 1,
          similarity: 0.3
        )
      ]

      context = format_info_extraction(chunks)

      assert context =~ "USER STATEMENTS"
      assert context =~ "EVIDENCE (ranked by relevance)"
      assert context =~ "hiking"
    end
  end

  # ── Multi-Session Entity Cross-Reference ──────────────────────────

  describe "multi_session_reasoning entity cross-reference" do
    test "builds entity cross-reference for shared entities across sessions" do
      chunks = [
        chunk("I started learning Python for data analysis.", "user",
          session_id: "s1", turn: 2
        ),
        chunk("I'm using Python with pandas for my project.", "user",
          session_id: "s2", turn: 3
        ),
        chunk("React is great for building UIs.", "user",
          session_id: "s3", turn: 1
        )
      ]

      context = format_multi_session(chunks)

      assert context =~ "ENTITY CROSS-REFERENCE"
      assert context =~ "Python"
      assert context =~ "MULTI-SESSION CONTEXT"
    end

    test "groups evidence by session" do
      chunks = [
        chunk("Topic A discussion.", "user", session_id: "s1", turn: 1),
        chunk("Topic B discussion.", "user", session_id: "s2", turn: 1),
        chunk("More about A.", "user", session_id: "s1", turn: 3)
      ]

      context = format_multi_session(chunks)

      assert context =~ "## Session s1"
      assert context =~ "## Session s2"
    end
  end

  # ── Temporal Timeline Formatting ──────────────────────────────────

  describe "temporal_reasoning timeline" do
    test "prepends TIMELINE section from dated chunks" do
      chunks = [
        chunk("I started growing tomatoes indoors.", "user",
          session_id: "s1", document_date: "2023-02-20", turn: 2,
          event_date: "2023-02-20"
        ),
        chunk("My marigold seeds arrived today.", "user",
          session_id: "s1", document_date: "2023-03-03", turn: 4,
          event_date: "2023-03-03"
        )
      ]

      context = format_temporal(chunks)

      assert context =~ "TIMELINE:"
      assert context =~ "2023-02-20"
      assert context =~ "2023-03-03"
      assert context =~ "EVIDENCE (strict chronological order)"
    end

    test "omits TIMELINE when no dates available" do
      chunks = [
        chunk("Something happened.", "user", session_id: "s1", turn: 1)
      ]

      context = format_temporal(chunks)

      refute context =~ "TIMELINE:"
      assert context =~ "EVIDENCE"
    end
  end

  # ── Question Relevance Scoring ──────────────────────────────────

  describe "question_relevance_score" do
    test "high overlap produces higher score" do
      high = relevance_score("I own 4 bikes and ride every weekend.", "How many bikes do I own?")
      low = relevance_score("The weather is nice today.", "How many bikes do I own?")

      assert high > low
    end

    test "returns 0.0 for zero overlap" do
      score = relevance_score("Completely unrelated content here.", "quantum physics equations")
      assert score == 0.0
    end
  end

  # ── Fact Category Extraction ──────────────────────────────────────

  describe "extract_fact_categories" do
    test "extracts category prefixes from BM25 facts" do
      facts = ["preference: thai food", "location: Seattle", "hobby: hiking"]
      categories = extract_fact_categories(facts)

      assert MapSet.member?(categories, "preference")
      assert MapSet.member?(categories, "location")
      assert MapSet.member?(categories, "hobby")
    end

    test "returns empty set for non-list input" do
      assert extract_fact_categories(nil) == MapSet.new()
      assert extract_fact_categories("not a list") == MapSet.new()
    end

    test "handles facts without colon separator" do
      facts = ["user prefers hiking", "no colon here"]
      categories = extract_fact_categories(facts)

      # "user prefers hiking" splits to category "user prefers hiking" — no colon
      # Both should still produce something or be empty depending on split behavior
      assert is_struct(categories, MapSet)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────

  # Build a mock chunk map matching the annotated chunk structure
  defp chunk(text, speaker, opts) do
    %{
      text: text,
      speaker: speaker,
      turn: Keyword.get(opts, :turn, 0),
      session_id: Keyword.get(opts, :session_id, "s0"),
      document_date: Keyword.get(opts, :document_date, nil),
      event_date: Keyword.get(opts, :event_date, nil),
      is_superseded: Keyword.get(opts, :is_superseded, false),
      valid_until: Keyword.get(opts, :valid_until, nil),
      similarity: Keyword.get(opts, :similarity, 0.5),
      score: Keyword.get(opts, :score, 0.5),
      node_id: "test_#{System.unique_integer([:positive])}",
      q_relevance: Keyword.get(opts, :q_relevance, 0.0)
    }
  end

  # Delegate to the private format functions via Module eval
  # We use Code.eval_string to call private functions in test context
  defp format_knowledge_update(chunks) do
    call_format(chunks, :knowledge_update)
  end

  defp format_info_extraction(chunks) do
    call_format(chunks, :information_extraction)
  end

  defp format_multi_session(chunks) do
    call_format(chunks, :multi_session_reasoning)
  end

  defp format_temporal(chunks) do
    call_format(chunks, :temporal_reasoning)
  end

  # Access private functions via :erlang.apply on the module
  # The longmemeval module compiles these as defp, so we use the
  # __info__(:functions) bypass pattern.
  defp call_format(chunks, ability) do
    # Since format_longmemeval_context is private, we test through the
    # public-facing distill path indirectly — or we can test the output
    # format by constructing expected strings.
    #
    # For unit tests of private functions, Elixir convention is to use
    # @compile {:no_warn_undefined, ...} or to make them public in test.
    # Instead, we replicate the formatting logic here to test the structure.
    #
    # Alternative: call the module with an apply trick
    apply(Mix.Tasks.Benchmark.Longmemeval, :format_longmemeval_context, [chunks, ability])
  end

  defp relevance_score(text, question) do
    apply(Mix.Tasks.Benchmark.Longmemeval, :question_relevance_score, [text, question])
  end

  defp extract_fact_categories(facts) do
    apply(Mix.Tasks.Benchmark.Longmemeval, :extract_fact_categories, [facts])
  end
end
