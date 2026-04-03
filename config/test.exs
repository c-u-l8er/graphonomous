import Config

config :graphonomous,
  embedder_backend: :fallback,
  embedding_model_id: "sentence-transformers/all-MiniLM-L6-v2",
  embedding_dimension: 384,
  embedding_task_prefixes: nil,
  reranker_enabled: false,
  db_path: "tmp/graphonomous_test.db",
  consolidator_interval_ms: 3_600_000,
  consolidator_decay_rate: 0.0,
  consolidator_prune_threshold: 0.0,
  learning_rate: 0.2

config :logger, level: :warning
