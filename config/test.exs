import Config

config :graphonomous,
  embedder_backend: :fallback,
  db_path: "tmp/graphonomous_test.db",
  consolidator_interval_ms: 3_600_000,
  consolidator_decay_rate: 0.0,
  consolidator_prune_threshold: 0.0,
  learning_rate: 0.2

config :logger, level: :warning
