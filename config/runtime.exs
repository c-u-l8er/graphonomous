import Config

current_graphonomous = Application.get_all_env(:graphonomous)
current_logger = Application.get_all_env(:logger)

get_default = fn env, key, fallback ->
  Keyword.get(env, key, fallback)
end

parse_int = fn env_name, default ->
  case System.get_env(env_name) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {parsed, ""} ->
          parsed

        _ ->
          IO.warn("Invalid integer for #{env_name}=#{inspect(value)}; using #{inspect(default)}")
          default
      end
  end
end

parse_float = fn env_name, default ->
  case System.get_env(env_name) do
    nil ->
      default

    value ->
      case Float.parse(value) do
        {parsed, ""} ->
          parsed

        _ ->
          IO.warn("Invalid float for #{env_name}=#{inspect(value)}; using #{inspect(default)}")
          default
      end
  end
end

parse_choice = fn env_name, allowed, default ->
  case System.get_env(env_name) do
    nil ->
      default

    raw_value ->
      value =
        raw_value
        |> String.trim()
        |> String.downcase()

      parsed_value =
        Enum.find(allowed, fn option ->
          Atom.to_string(option) == value
        end)

      if parsed_value do
        parsed_value
      else
        IO.warn(
          "Invalid value for #{env_name}=#{inspect(raw_value)}; expected one of #{inspect(allowed)}; using #{inspect(default)}"
        )

        default
      end
  end
end

maybe_env = fn env_name, default ->
  case System.get_env(env_name) do
    nil ->
      default

    value ->
      trimmed = String.trim(value)
      if trimmed == "", do: nil, else: trimmed
  end
end

config :graphonomous,
  db_path:
    maybe_env.(
      "GRAPHONOMOUS_DB_PATH",
      get_default.(current_graphonomous, :db_path, "priv/graphonomous.db")
    ),
  embedding_model_id:
    maybe_env.(
      "GRAPHONOMOUS_EMBEDDING_MODEL",
      get_default.(
        current_graphonomous,
        :embedding_model_id,
        "sentence-transformers/all-MiniLM-L6-v2"
      )
    ),
  embedder_backend:
    parse_choice.(
      "GRAPHONOMOUS_EMBEDDER_BACKEND",
      [:auto, :fallback],
      get_default.(current_graphonomous, :embedder_backend, :auto)
    ),
  sqlite_vec_extension_path:
    maybe_env.(
      "GRAPHONOMOUS_SQLITE_VEC_EXTENSION_PATH",
      get_default.(current_graphonomous, :sqlite_vec_extension_path, nil)
    ),
  consolidator_interval_ms:
    parse_int.(
      "GRAPHONOMOUS_CONSOLIDATOR_INTERVAL_MS",
      get_default.(current_graphonomous, :consolidator_interval_ms, 300_000)
    ),
  consolidator_decay_rate:
    parse_float.(
      "GRAPHONOMOUS_CONSOLIDATOR_DECAY_RATE",
      get_default.(current_graphonomous, :consolidator_decay_rate, 0.02)
    ),
  consolidator_prune_threshold:
    parse_float.(
      "GRAPHONOMOUS_CONSOLIDATOR_PRUNE_THRESHOLD",
      get_default.(current_graphonomous, :consolidator_prune_threshold, 0.1)
    ),
  consolidator_merge_similarity:
    parse_float.(
      "GRAPHONOMOUS_CONSOLIDATOR_MERGE_SIMILARITY",
      get_default.(current_graphonomous, :consolidator_merge_similarity, 0.95)
    ),
  learning_rate:
    parse_float.(
      "GRAPHONOMOUS_LEARNING_RATE",
      get_default.(current_graphonomous, :learning_rate, 0.2)
    )

config :logger,
  level:
    parse_choice.(
      "LOG_LEVEL",
      [:debug, :info, :warning, :error],
      get_default.(current_logger, :level, :info)
    ),
  default_handler: [
    config: [
      type: :standard_error
    ]
  ]

config :anubis_mcp,
  log: false
