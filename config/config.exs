import Config

config :graphonomous,
  db_path: "priv/graphonomous.db",
  embedding_model_id: "sentence-transformers/all-MiniLM-L6-v2",
  embedder_backend: :auto,
  consolidator_interval_ms: 300_000,
  consolidator_decay_rate: 0.02,
  consolidator_prune_threshold: 0.1,
  consolidator_merge_similarity: 0.95,
  learning_rate: 0.2,
  model_tier: :local_small

config :graphonomous, Graphonomous.Attention,
  heartbeat_ms: 300_000,
  enabled: false,
  autonomy_level: :observe,
  escalation_cooldown_ms: 300_000,
  budget: %{
    max_items_per_cycle: 3,
    max_explore_calls: 5,
    max_deliberation_sccs: 2,
    max_action_dispatches: 1,
    total_timeout_ms: 60_000
  }

import_config "#{config_env()}.exs"
