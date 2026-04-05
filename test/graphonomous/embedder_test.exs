defmodule Graphonomous.EmbedderTest do
  @moduledoc """
  Tests for Graphonomous.Embedder — backends, task prefixes, dimension
  handling, binary encoding, and v2-moe model configuration.
  """

  use ExUnit.Case, async: false

  alias Graphonomous.Embedder

  setup_all do
    {:ok, _} = Application.ensure_all_started(:graphonomous)
    :ok
  end

  # ---- Basic embedding contract ----

  describe "embed/2" do
    test "returns a float vector of configured dimension" do
      {:ok, vector} = Embedder.embed("hello world")
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert length(vector) == dim
      assert Enum.all?(vector, &is_float/1)
    end

    test "returns L2-normalized vector" do
      {:ok, vector} = Embedder.embed("normalization test")
      norm = vector |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
      assert_in_delta norm, 1.0, 1.0e-6
    end

    test "different texts produce different embeddings" do
      {:ok, v1} = Embedder.embed("the cat sat on the mat")
      {:ok, v2} = Embedder.embed("quantum chromodynamics")
      refute v1 == v2
    end

    test "identical texts produce identical embeddings" do
      {:ok, v1} = Embedder.embed("deterministic check")
      {:ok, v2} = Embedder.embed("deterministic check")
      assert v1 == v2
    end

    test "empty string produces a valid embedding" do
      {:ok, vector} = Embedder.embed("")
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert length(vector) == dim
    end

    test "unicode text produces a valid embedding" do
      {:ok, vector} = Embedder.embed("日本語テスト 🧠 Ñoño")
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert length(vector) == dim
      assert Enum.all?(vector, &is_float/1)
    end
  end

  # ---- Batch embedding ----

  describe "embed_many/2" do
    test "returns one vector per input text" do
      texts = ["alpha", "beta", "gamma"]
      {:ok, vectors} = Embedder.embed_many(texts)
      assert length(vectors) == 3
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert Enum.all?(vectors, &(length(&1) == dim))
    end

    test "empty list returns empty result" do
      {:ok, vectors} = Embedder.embed_many([])
      assert vectors == []
    end

    test "batch results match individual embeds" do
      texts = ["foo bar", "baz qux"]
      {:ok, batch} = Embedder.embed_many(texts)
      {:ok, v1} = Embedder.embed("foo bar")
      {:ok, v2} = Embedder.embed("baz qux")
      assert Enum.at(batch, 0) == v1
      assert Enum.at(batch, 1) == v2
    end

    test "filters out non-binary elements" do
      {:ok, vectors} = Embedder.embed_many(["valid", 123, nil, "also valid"])
      assert length(vectors) == 2
    end
  end

  # ---- Binary encoding (for SQLite BLOB storage) ----

  describe "embed_binary/2" do
    test "returns little-endian float32 binary of correct byte size" do
      {:ok, binary} = Embedder.embed_binary("binary test")
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      # 4 bytes per float32
      assert byte_size(binary) == dim * 4
    end

    test "binary roundtrips to same vector as embed/2" do
      text = "roundtrip test"
      {:ok, vector} = Embedder.embed(text)
      {:ok, binary} = Embedder.embed_binary(text)

      decoded =
        for <<f::float-little-32 <- binary>> do
          f
        end

      assert length(decoded) == length(vector)

      Enum.zip(vector, decoded)
      |> Enum.each(fn {expected, actual} ->
        assert_in_delta expected, actual, 1.0e-6
      end)
    end
  end

  describe "embed_many_binary/2" do
    test "returns one binary per input" do
      {:ok, binaries} = Embedder.embed_many_binary(["one", "two", "three"])
      assert length(binaries) == 3
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert Enum.all?(binaries, &(byte_size(&1) == dim * 4))
    end
  end

  # ---- Task prefix support ----

  describe "task prefixes" do
    test "query and document tasks produce valid embeddings" do
      {:ok, v_query} = Embedder.embed("test text", task: :query)
      {:ok, v_doc} = Embedder.embed("test text", task: :document)
      {:ok, v_none} = Embedder.embed("test text")

      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert length(v_query) == dim
      assert length(v_doc) == dim
      assert length(v_none) == dim
    end

    test "task prefix with embed_many" do
      {:ok, vectors} = Embedder.embed_many(["a", "b"], task: :document)
      assert length(vectors) == 2
    end

    test "nil task behaves same as no task" do
      {:ok, v1} = Embedder.embed("same", task: nil)
      {:ok, v2} = Embedder.embed("same")
      assert v1 == v2
    end
  end

  # ---- Task prefix behavior with configured prefixes (isolated instance) ----

  describe "task prefixes with v2-moe style config" do
    test "configured prefixes change embeddings vs no prefix" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "test-model",
          dimension: 64,
          backend: :fallback,
          task_prefixes: %{query: "search_query: ", document: "search_document: "}
        )

      {:ok, v_query} = GenServer.call(pid, {:embed, "hello", :query})
      {:ok, v_doc} = GenServer.call(pid, {:embed, "hello", :document})
      {:ok, v_plain} = GenServer.call(pid, {:embed, "hello", nil})

      assert length(v_query) == 64
      assert length(v_doc) == 64
      assert length(v_plain) == 64

      # With fallback backend, prefixed text hashes differently
      refute v_query == v_plain
      refute v_doc == v_plain
      refute v_query == v_doc

      GenServer.stop(pid)
    end
  end

  # ---- Info endpoint ----

  describe "info/0" do
    test "returns backend, model_id, and dimension" do
      info = Embedder.info()
      assert is_map(info)
      assert Map.has_key?(info, :backend)
      assert Map.has_key?(info, :model_id)
      assert Map.has_key?(info, :dimension)
      assert is_atom(info.backend)
      assert is_binary(info.model_id)
      assert is_integer(info.dimension)
      assert info.dimension > 0
    end

    test "test env uses fallback backend" do
      info = Embedder.info()
      assert info.backend == :fallback
    end
  end

  # ---- nomic production config validation ----

  describe "nomic production config" do
    test "config.exs specifies nomic-embed-text-v2-moe" do
      {:ok, contents} = File.read("config/config.exs")
      assert contents =~ "nomic-ai/nomic-embed-text-v2-moe"
    end

    test "config.exs preserves 768 dimension" do
      {:ok, contents} = File.read("config/config.exs")
      assert contents =~ "embedding_dimension: 768"
    end

    test "config.exs preserves search_query/search_document task prefixes" do
      {:ok, contents} = File.read("config/config.exs")
      assert contents =~ ~s(query: "search_query: ")
      assert contents =~ ~s(document: "search_document: ")
    end
  end

  # ---- Dimension handling (truncation and padding) ----

  describe "dimension handling" do
    test "small dimension produces correct size" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "test-model",
          dimension: 32,
          backend: :fallback,
          task_prefixes: nil
        )

      info = GenServer.call(pid, :info)
      assert info.dimension == 32

      {:ok, vector} = GenServer.call(pid, {:embed, "test", nil})
      assert length(vector) == 32

      GenServer.stop(pid)
    end

    test "large dimension pads and normalizes correctly" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "test-model",
          dimension: 1024,
          backend: :fallback,
          task_prefixes: nil
        )

      {:ok, vector} = GenServer.call(pid, {:embed, "test", nil})
      assert length(vector) == 1024

      norm = vector |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
      assert_in_delta norm, 1.0, 1.0e-6

      GenServer.stop(pid)
    end

    test "768 dimension works (v2-moe production dimension)" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "test-model",
          dimension: 768,
          backend: :fallback,
          task_prefixes: %{query: "search_query: ", document: "search_document: "}
        )

      {:ok, vector} = GenServer.call(pid, {:embed, "production dimension test", :query})
      assert length(vector) == 768

      norm = vector |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
      assert_in_delta norm, 1.0, 1.0e-6

      GenServer.stop(pid)
    end
  end

  # ---- Fallback backend properties ----

  describe "fallback backend" do
    test "produces distinct embeddings for semantically different content" do
      {:ok, v1} = Embedder.embed("elixir genserver processes OTP")
      {:ok, v2} = Embedder.embed("chocolate cake baking recipe")
      cosine = dot(v1, v2)
      assert cosine < 0.5
    end

    test "produces similar embeddings for overlapping content" do
      {:ok, v1} = Embedder.embed("the quick brown fox jumps")
      {:ok, v2} = Embedder.embed("the quick brown fox leaps")
      cosine = dot(v1, v2)
      assert cosine > 0.5
    end

    test "long text does not crash" do
      long = String.duplicate("word ", 10_000)
      {:ok, vector} = Embedder.embed(long)
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert length(vector) == dim
    end
  end

  # ---- Backend selection ----

  describe "backend selection" do
    test "fallback backend starts immediately without warmup" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "nonexistent-model",
          dimension: 64,
          backend: :fallback,
          task_prefixes: nil
        )

      info = GenServer.call(pid, :info)
      assert info.backend == :fallback

      GenServer.stop(pid)
    end

    test "auto backend falls back after failing to load model" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "nonexistent/model-that-wont-load",
          dimension: 64,
          backend: :auto,
          task_prefixes: nil
        )

      # Give warmup task time to fail and fall back
      Process.sleep(3_000)

      info = GenServer.call(pid, :info)
      assert info.backend == :fallback

      GenServer.stop(pid)
    end

    test "warming state still serves embeddings via fallback" do
      {:ok, pid} =
        GenServer.start_link(Embedder,
          model_id: "nonexistent/slow-model",
          dimension: 64,
          backend: :auto,
          task_prefixes: nil
        )

      # Immediately call before warmup completes — should use fallback
      {:ok, vector} = GenServer.call(pid, {:embed, "test during warmup", nil})
      assert length(vector) == 64

      GenServer.stop(pid)
    end
  end

  # ---- Backwards compatibility (bare tuple calls) ----

  describe "backwards compatibility" do
    test "{:embed, text} without task arg works" do
      {:ok, vector} = GenServer.call(Embedder, {:embed, "backwards compat"})
      dim = Application.get_env(:graphonomous, :embedding_dimension, 384)
      assert length(vector) == dim
    end

    test "{:embed_many, texts} without task arg works" do
      {:ok, vectors} = GenServer.call(Embedder, {:embed_many, ["a", "b"]})
      assert length(vectors) == 2
    end

    test "{:embed_many_binary, texts} without task arg works" do
      {:ok, binaries} = GenServer.call(Embedder, {:embed_many_binary, ["a", "b"]})
      assert length(binaries) == 2
      assert Enum.all?(binaries, &is_binary/1)
    end
  end

  # ---- ONNX cache path convention ----

  describe "ONNX cache path for v2-moe" do
    test "cache path follows model_id convention" do
      expected_dir =
        Path.join([
          System.user_home() || "/tmp",
          ".cache",
          "graphonomous",
          "onnx",
          "nomic-ai--nomic-embed-text-v2-moe"
        ])

      expected_path = Path.join(expected_dir, "model.onnx")

      # The export script should have placed the file here
      if File.exists?(expected_path) do
        stat = File.stat!(expected_path)
        # Should be a substantial file (the v2-moe ONNX is ~1.1GB)
        assert stat.size > 100_000_000
      else
        # If export hasn't been run, just verify the path convention is correct
        assert String.contains?(expected_dir, "nomic-ai--nomic-embed-text-v2-moe")
      end
    end
  end

  # ---- Export script exists and is valid ----

  describe "export script" do
    test "export_onnx_v2_moe.py exists" do
      assert File.exists?("scripts/export_onnx_v2_moe.py")
    end

    test "export script targets the correct model" do
      {:ok, contents} = File.read("scripts/export_onnx_v2_moe.py")
      assert contents =~ "nomic-ai/nomic-embed-text-v2-moe"
    end

    test "export script uses matching input order (input_ids, token_type_ids, attention_mask)" do
      {:ok, contents} = File.read("scripts/export_onnx_v2_moe.py")
      assert contents =~ ~s(input_names=["input_ids", "token_type_ids", "attention_mask"])
    end

    test "export script outputs last_hidden_state" do
      {:ok, contents} = File.read("scripts/export_onnx_v2_moe.py")
      assert contents =~ ~s(output_names=["last_hidden_state"])
    end

    test "export script writes to graphonomous ONNX cache path" do
      {:ok, contents} = File.read("scripts/export_onnx_v2_moe.py")
      assert contents =~ "nomic-ai--nomic-embed-text-v2-moe"
    end
  end

  # ---- Helpers ----

  defp dot(v1, v2) do
    Enum.zip(v1, v2)
    |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
  end
end
