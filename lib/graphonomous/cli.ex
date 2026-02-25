defmodule Graphonomous.CLI do
  @moduledoc """
  Executable CLI entrypoint for Graphonomous MCP server over STDIO.

  This module is intended to be used as the `escript` main module so MCP clients
  can launch Graphonomous with a standard command, for example:

      graphonomous --db ~/.graphonomous/knowledge.db

  It starts the Graphonomous OTP app and then starts the MCP server transport on
  standard input/output.
  """

  @default_request_timeout 120_000

  @type cli_options :: %{
          optional(:db_path) => String.t(),
          optional(:embedding_model_id) => String.t(),
          optional(:embedder_backend) => :auto | :fallback,
          optional(:sqlite_vec_extension_path) => String.t(),
          optional(:consolidator_interval_ms) => pos_integer(),
          optional(:consolidator_decay_rate) => float(),
          optional(:consolidator_prune_threshold) => float(),
          optional(:consolidator_merge_similarity) => float(),
          optional(:learning_rate) => float(),
          optional(:log_level) => Logger.level(),
          optional(:request_timeout) => pos_integer()
        }

  @spec main([String.t()]) :: no_return()
  def main(args) when is_list(args) do
    case parse_args(args) do
      {:version} ->
        IO.puts(version_text())
        System.halt(0)

      {:help} ->
        IO.puts(help_text())
        System.halt(0)

      {:ok, opts} ->
        configure_runtime(opts)
        Process.flag(:trap_exit, true)
        start_runtime()
        {:ok, server_pid} = start_stdio_mcp_server(opts)
        wait_forever(server_pid)

      {:error, message} ->
        IO.puts(:stderr, "graphonomous: #{message}\n")
        IO.puts(:stderr, help_text())
        System.halt(1)
    end
  end

  @spec parse_args([String.t()]) ::
          {:ok, cli_options()} | {:help} | {:version} | {:error, String.t()}
  defp parse_args(args) do
    {parsed, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          version: :boolean,
          db: :string,
          embedding_model: :string,
          embedder_backend: :string,
          sqlite_vec_extension_path: :string,
          consolidator_interval_ms: :integer,
          consolidator_decay_rate: :float,
          consolidator_prune_threshold: :float,
          consolidator_merge_similarity: :float,
          learning_rate: :float,
          log_level: :string,
          request_timeout: :integer
        ],
        aliases: [
          h: :help,
          v: :version,
          d: :db,
          m: :embedding_model
        ]
      )

    cond do
      parsed[:version] ->
        {:version}

      parsed[:help] ->
        {:help}

      invalid != [] ->
        {:error, "invalid option(s): #{format_invalid(invalid)}"}

      rest != [] ->
        {:error, "unexpected argument(s): #{Enum.join(rest, " ")}"}

      true ->
        normalize_parsed_options(parsed)
    end
  end

  @spec normalize_parsed_options(keyword()) :: {:ok, cli_options()} | {:error, String.t()}
  defp normalize_parsed_options(parsed) do
    with {:ok, backend} <- normalize_backend(parsed[:embedder_backend] || "fallback"),
         {:ok, level} <- normalize_log_level(parsed[:log_level]),
         {:ok, interval_ms} <-
           validate_positive_int(parsed[:consolidator_interval_ms], "--consolidator-interval-ms"),
         {:ok, timeout} <- validate_positive_int(parsed[:request_timeout], "--request-timeout"),
         :ok <-
           validate_probability(parsed[:consolidator_decay_rate], "--consolidator-decay-rate"),
         :ok <-
           validate_probability(
             parsed[:consolidator_prune_threshold],
             "--consolidator-prune-threshold"
           ),
         :ok <-
           validate_probability(
             parsed[:consolidator_merge_similarity],
             "--consolidator-merge-similarity"
           ),
         :ok <- validate_probability(parsed[:learning_rate], "--learning-rate") do
      opts =
        %{}
        |> maybe_put(:db_path, parsed[:db])
        |> maybe_put(:embedding_model_id, parsed[:embedding_model])
        |> maybe_put(:embedder_backend, backend)
        |> maybe_put(:sqlite_vec_extension_path, parsed[:sqlite_vec_extension_path])
        |> maybe_put(:consolidator_interval_ms, interval_ms)
        |> maybe_put(:consolidator_decay_rate, parsed[:consolidator_decay_rate])
        |> maybe_put(:consolidator_prune_threshold, parsed[:consolidator_prune_threshold])
        |> maybe_put(:consolidator_merge_similarity, parsed[:consolidator_merge_similarity])
        |> maybe_put(:learning_rate, parsed[:learning_rate])
        |> maybe_put(:log_level, level)
        |> maybe_put(:request_timeout, timeout)

      {:ok, opts}
    end
  end

  @spec configure_runtime(cli_options()) :: :ok
  defp configure_runtime(opts) do
    Enum.each(opts, fn
      {:db_path, value} ->
        Application.put_env(:graphonomous, :db_path, value)

      {:embedding_model_id, value} ->
        Application.put_env(:graphonomous, :embedding_model_id, value)

      {:embedder_backend, value} ->
        Application.put_env(:graphonomous, :embedder_backend, value)

      {:sqlite_vec_extension_path, value} ->
        Application.put_env(:graphonomous, :sqlite_vec_extension_path, value)

      {:consolidator_interval_ms, value} ->
        Application.put_env(:graphonomous, :consolidator_interval_ms, value)

      {:consolidator_decay_rate, value} ->
        Application.put_env(:graphonomous, :consolidator_decay_rate, value)

      {:consolidator_prune_threshold, value} ->
        Application.put_env(:graphonomous, :consolidator_prune_threshold, value)

      {:consolidator_merge_similarity, value} ->
        Application.put_env(:graphonomous, :consolidator_merge_similarity, value)

      {:learning_rate, value} ->
        Application.put_env(:graphonomous, :learning_rate, value)

      {:log_level, value} ->
        Logger.configure(level: value)

      {:request_timeout, _value} ->
        :ok
    end)

    # Keep STDOUT reserved for MCP protocol frames.
    # Route all Logger console output to STDERR in CLI/MCP mode.
    Logger.configure_backend(:console, device: :standard_error)

    :ok
  end

  @spec start_runtime() :: :ok
  defp start_runtime do
    case Application.ensure_all_started(:graphonomous) do
      {:ok, _started} ->
        :ok

      {:error, reason} ->
        halt_with_error("failed to start graphonomous application: #{inspect(reason)}")
    end

    case Application.ensure_all_started(:anubis_mcp) do
      {:ok, _started} ->
        :ok

      {:error, reason} ->
        halt_with_error("failed to start anubis_mcp application: #{inspect(reason)}")
    end
  end

  @spec start_stdio_mcp_server(cli_options()) :: {:ok, pid()}
  defp start_stdio_mcp_server(opts) do
    timeout = Map.get(opts, :request_timeout, @default_request_timeout)

    case Anubis.Server.Supervisor.start_link(
           Graphonomous.MCP.Server,
           transport: :stdio,
           request_timeout: timeout
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        halt_with_error("failed to start MCP stdio server: #{inspect(reason)}")
    end
  end

  @spec wait_forever(pid()) :: no_return()
  defp wait_forever(server_pid) when is_pid(server_pid) do
    ref = Process.monitor(server_pid)

    receive do
      {:DOWN, ^ref, :process, ^server_pid, reason} ->
        halt_with_error("MCP server terminated: #{inspect(reason)}")

      {:EXIT, ^server_pid, reason} ->
        halt_with_error("MCP server terminated: #{inspect(reason)}")
    after
      :infinity ->
        System.halt(0)
    end
  end

  @spec normalize_backend(nil | String.t()) ::
          {:ok, :auto | :fallback | nil} | {:error, String.t()}
  defp normalize_backend(nil), do: {:ok, nil}
  defp normalize_backend("auto"), do: {:ok, :auto}
  defp normalize_backend("fallback"), do: {:ok, :fallback}

  defp normalize_backend(other),
    do: {:error, "invalid --embedder-backend=#{inspect(other)} (allowed: auto|fallback)"}

  @spec normalize_log_level(nil | String.t()) ::
          {:ok, Logger.level() | nil} | {:error, String.t()}
  defp normalize_log_level(nil), do: {:ok, nil}
  defp normalize_log_level("debug"), do: {:ok, :debug}
  defp normalize_log_level("info"), do: {:ok, :info}
  defp normalize_log_level("warning"), do: {:ok, :warning}
  defp normalize_log_level("error"), do: {:ok, :error}

  defp normalize_log_level(other),
    do: {:error, "invalid --log-level=#{inspect(other)} (allowed: debug|info|warning|error)"}

  @spec validate_positive_int(nil | integer(), String.t()) ::
          {:ok, pos_integer() | nil} | {:error, String.t()}
  defp validate_positive_int(nil, _flag), do: {:ok, nil}
  defp validate_positive_int(value, _flag) when is_integer(value) and value > 0, do: {:ok, value}

  defp validate_positive_int(value, flag),
    do: {:error, "invalid #{flag}=#{inspect(value)} (must be > 0)"}

  @spec validate_probability(nil | number(), String.t()) :: :ok | {:error, String.t()}
  defp validate_probability(nil, _flag), do: :ok

  defp validate_probability(value, _flag) when is_number(value) and value >= 0.0 and value <= 1.0,
    do: :ok

  defp validate_probability(value, flag),
    do: {:error, "invalid #{flag}=#{inspect(value)} (must be in [0.0, 1.0])"}

  @spec maybe_put(map(), atom(), any()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec format_invalid([{String.t(), any()}]) :: String.t()
  defp format_invalid(invalid) do
    invalid
    |> Enum.map(fn {key, value} -> "--#{key}=#{inspect(value)}" end)
    |> Enum.join(", ")
  end

  @spec halt_with_error(String.t()) :: no_return()
  defp halt_with_error(message) do
    IO.puts(:stderr, "graphonomous: #{message}")
    System.halt(1)
  end

  @spec version_text() :: String.t()
  defp version_text do
    case Application.spec(:graphonomous, :vsn) do
      vsn when is_list(vsn) -> "graphonomous #{List.to_string(vsn)}"
      vsn when is_binary(vsn) -> "graphonomous #{vsn}"
      _ -> "graphonomous unknown"
    end
  end

  @spec help_text() :: String.t()
  defp help_text do
    """
    Graphonomous MCP server (STDIO)

    Usage:
      graphonomous [options]

    Options:
      -h, --help                               Show this help
      -v, --version                            Show CLI/app version
      -d, --db PATH                            SQLite DB path (GRAPHONOMOUS_DB_PATH)
      -m, --embedding-model MODEL              Embedding model id (GRAPHONOMOUS_EMBEDDING_MODEL)
          --embedder-backend MODE              auto | fallback
          --sqlite-vec-extension-path PATH     Path to sqlite-vec extension
          --consolidator-interval-ms MS        Consolidator interval in milliseconds (> 0)
          --consolidator-decay-rate FLOAT      Decay rate in [0.0, 1.0]
          --consolidator-prune-threshold FLOAT Prune threshold in [0.0, 1.0]
          --consolidator-merge-similarity FLOAT Merge similarity in [0.0, 1.0]
          --learning-rate FLOAT                Learning rate in [0.0, 1.0]
          --log-level LEVEL                    debug | info | warning | error
          --request-timeout MS                 MCP request timeout in milliseconds (> 0)

    Examples:
      graphonomous
      graphonomous --db ~/.graphonomous/knowledge.db
      graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback --log-level info
    """
  end
end
