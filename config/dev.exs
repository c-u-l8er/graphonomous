import Config

# Development environment configuration
config :graphonomous,
  embedder_backend: :auto,
  db_path: "priv/graphonomous_dev.db",
  consolidator_interval_ms: 300_000,
  consolidator_decay_rate: 0.02,
  consolidator_prune_threshold: 0.1,
  consolidator_merge_similarity: 0.95,
  learning_rate: 0.2

# Optional: increase verbosity while building locally
config :logger, level: :debug
