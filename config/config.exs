import Config

config :graphonomous,
  db_path: "priv/graphonomous.db",
  embedding_model_id: "sentence-transformers/all-MiniLM-L6-v2",
  embedder_backend: :auto,
  consolidator_interval_ms: 300_000,
  consolidator_decay_rate: 0.02,
  consolidator_prune_threshold: 0.1,
  consolidator_merge_similarity: 0.95,
  learning_rate: 0.2

import_config "#{config_env()}.exs"
