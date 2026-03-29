defmodule Graphonomous.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Anubis.Server.Registry, []},
      {Graphonomous.Store, store_opts()},
      {Graphonomous.Embedder, embedder_opts()},
      {Graphonomous.Graph, []},
      {Graphonomous.Retriever, []},
      {Graphonomous.Orchestrator, orchestrator_opts()},
      {Graphonomous.Learner, []},
      {Graphonomous.GoalGraph, []},
      {Graphonomous.Attention, []},
      {Graphonomous.Consolidator, consolidator_opts()}
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
      backend: Application.get_env(:graphonomous, :embedder_backend, :auto)
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

  defp consolidator_opts do
    [
      interval_ms: Application.get_env(:graphonomous, :consolidator_interval_ms, 300_000),
      decay_rate: Application.get_env(:graphonomous, :consolidator_decay_rate, 0.02),
      prune_threshold: Application.get_env(:graphonomous, :consolidator_prune_threshold, 0.1),
      merge_similarity: Application.get_env(:graphonomous, :consolidator_merge_similarity, 0.95)
    ]
  end
end
