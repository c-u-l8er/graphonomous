defmodule Graphonomous.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Anubis.Server.Registry, []},
      {Graphonomous.Store, store_opts()},
      {Graphonomous.Embedder, embedder_opts()},
      {Graphonomous.HNSWIndex, hnsw_opts()},
      {Graphonomous.Graph, []},
      {Graphonomous.BM25Index, []},
      {Graphonomous.Reranker, reranker_opts()},
      {Graphonomous.Retriever, []},
      {Graphonomous.Orchestrator, orchestrator_opts()},
      {Graphonomous.Learner, []},
      {Graphonomous.GoalGraph, []},
      {Graphonomous.Attention, []},
      {Graphonomous.Consolidator, consolidator_opts()},
      {Graphonomous.OpenSentience.HarnessSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Graphonomous.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp store_opts do
    [db_path: Application.get_env(:graphonomous, :db_path, "priv/graphonomous.db")]
  end

  defp embedder_opts do
    [
      model_id:
        Application.get_env(
          :graphonomous,
          :embedding_model_id,
          "sentence-transformers/all-MiniLM-L6-v2"
        ),
      dimension: Application.get_env(:graphonomous, :embedding_dimension, 384),
      task_prefixes: Application.get_env(:graphonomous, :embedding_task_prefixes, nil),
      backend: Application.get_env(:graphonomous, :embedder_backend, :auto),
      onnx_sequence_length: Application.get_env(:graphonomous, :onnx_sequence_length, 64)
    ]
  end

  defp orchestrator_opts do
    [
      learning_rate: Application.get_env(:graphonomous, :learning_rate, 0.2),
      min_learning_rate: Application.get_env(:graphonomous, :min_learning_rate, 0.05),
      max_learning_rate: Application.get_env(:graphonomous, :max_learning_rate, 0.4),
      metrics_interval_ms:
        Application.get_env(:graphonomous, :orchestrator_metrics_interval_ms, 30_000)
    ]
  end

  defp hnsw_opts do
    [
      dimension: Application.get_env(:graphonomous, :embedding_dimension, 384),
      max_elements: Application.get_env(:graphonomous, :hnsw_max_elements, 100_000),
      ef_construction: Application.get_env(:graphonomous, :hnsw_ef_construction, 200),
      m: Application.get_env(:graphonomous, :hnsw_m, 16),
      ef_search: Application.get_env(:graphonomous, :hnsw_ef_search, 50),
      index_path: Application.get_env(:graphonomous, :db_path, "priv/graphonomous.db")
    ]
  end

  defp reranker_opts do
    [
      model_id:
        Application.get_env(
          :graphonomous,
          :reranker_model_id,
          "cross-encoder/ms-marco-MiniLM-L-6-v2"
        ),
      enabled: Application.get_env(:graphonomous, :reranker_enabled, true)
    ]
  end

  defp consolidator_opts do
    [
      interval_ms: Application.get_env(:graphonomous, :consolidator_interval_ms, 300_000),
      decay_rate: Application.get_env(:graphonomous, :consolidator_decay_rate, 0.02),
      prune_threshold: Application.get_env(:graphonomous, :consolidator_prune_threshold, 0.1),
      merge_similarity: Application.get_env(:graphonomous, :consolidator_merge_similarity, 0.95)
    ]
  end
end
