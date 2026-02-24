defmodule Graphonomous.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Graphonomous.Store, store_opts()},
      {Graphonomous.Embedder, embedder_opts()},
      {Graphonomous.Graph, []},
      {Graphonomous.Retriever, []},
      {Graphonomous.Learner, []},
      {Graphonomous.GoalGraph, []},
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
        )
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
