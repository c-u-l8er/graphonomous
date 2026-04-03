defmodule Graphonomous.BM25IndexTest do
  use ExUnit.Case, async: false

  alias Graphonomous.BM25Index

  describe "BM25Index" do
    test "upsert and search finds matching nodes" do
      node_id = "bm25_test_#{System.unique_integer([:positive])}"
      BM25Index.upsert(node_id, "Elixir GenServer pattern matching with OTP behaviours")

      # Give cast time to process
      Process.sleep(100)

      {:ok, results} = BM25Index.search("GenServer OTP")

      assert is_list(results)

      matching = Enum.find(results, fn {id, _score} -> id == node_id end)
      assert matching != nil
      {_id, score} = matching
      assert score > 0.0

      # Cleanup
      BM25Index.delete(node_id)
    end

    test "search returns empty list for unmatched query" do
      {:ok, results} = BM25Index.search("xyzzy_nonexistent_term_#{System.unique_integer()}")
      assert results == []
    end

    test "delete removes node from index" do
      node_id = "bm25_del_#{System.unique_integer([:positive])}"
      BM25Index.upsert(node_id, "unique_deletion_test_term_alpha")
      Process.sleep(100)

      {:ok, before_results} = BM25Index.search("unique_deletion_test_term_alpha")
      assert Enum.any?(before_results, fn {id, _} -> id == node_id end)

      BM25Index.delete(node_id)
      Process.sleep(100)

      {:ok, after_results} = BM25Index.search("unique_deletion_test_term_alpha")
      refute Enum.any?(after_results, fn {id, _} -> id == node_id end)
    end

    test "info returns index statistics" do
      info = BM25Index.info()
      assert is_map(info)
      assert Map.has_key?(info, :indexed_count)
      assert Map.has_key?(info, :db_path)
    end

    test "upsert updates existing content" do
      node_id = "bm25_upd_#{System.unique_integer([:positive])}"
      BM25Index.upsert(node_id, "original content about quantum computing")
      Process.sleep(100)

      BM25Index.upsert(node_id, "updated content about neural networks")
      Process.sleep(100)

      {:ok, quantum_results} = BM25Index.search("quantum computing")
      refute Enum.any?(quantum_results, fn {id, _} -> id == node_id end)

      {:ok, neural_results} = BM25Index.search("neural networks")
      assert Enum.any?(neural_results, fn {id, _} -> id == node_id end)

      BM25Index.delete(node_id)
    end

    test "BM25 scores rank more relevant docs higher" do
      id1 = "bm25_rank_1_#{System.unique_integer([:positive])}"
      id2 = "bm25_rank_2_#{System.unique_integer([:positive])}"

      BM25Index.upsert(id1, "Elixir processes and Elixir supervisors and Elixir OTP")
      BM25Index.upsert(id2, "Python web framework with Django templates")
      Process.sleep(100)

      {:ok, results} = BM25Index.search("Elixir OTP processes")
      elixir_match = Enum.find(results, fn {id, _} -> id == id1 end)
      python_match = Enum.find(results, fn {id, _} -> id == id2 end)

      # Elixir doc should match, Python doc should not (or rank lower)
      assert elixir_match != nil

      if python_match do
        {_, elixir_score} = elixir_match
        {_, python_score} = python_match
        assert elixir_score > python_score
      end

      BM25Index.delete(id1)
      BM25Index.delete(id2)
    end
  end
end
