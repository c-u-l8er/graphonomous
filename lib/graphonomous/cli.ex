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
          optional(:request_timeout) => pos_integer(),
          optional(:recursive) => boolean(),
          optional(:include_hidden) => boolean(),
          optional(:follow_symlinks) => boolean(),
          optional(:extensions) => [String.t()],
          optional(:poll_interval_ms) => pos_integer(),
          optional(:ingest_on_start) => boolean(),
          optional(:max_file_size_bytes) => pos_integer(),
          optional(:max_read_bytes) => pos_integer()
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
        {:ok, monitor_pid} = start_stdio_mcp_server(opts)
        wait_forever(monitor_pid)

      {:scan, root_path, opts} ->
        configure_runtime(opts)
        start_runtime()
        run_scan(root_path, opts)

      {:watch, root_path, opts} ->
        configure_runtime(opts)
        start_runtime()
        run_watch(root_path, opts)

      {:error, message} ->
        IO.puts(:stderr, "graphonomous: #{message}\n")
        IO.puts(:stderr, help_text())
        System.halt(1)
    end
  end

  @spec parse_args([String.t()]) ::
          {:ok, cli_options()}
          | {:scan, String.t(), cli_options()}
          | {:watch, String.t(), cli_options()}
          | {:help}
          | {:version}
          | {:error, String.t()}
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
          request_timeout: :integer,
          recursive: :boolean,
          include_hidden: :boolean,
          follow_symlinks: :boolean,
          extensions: :string,
          poll_interval_ms: :integer,
          ingest_on_start: :boolean,
          max_file_size_bytes: :integer,
          max_read_bytes: :integer
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

      true ->
        parse_command(rest, parsed)
    end
  end

  @spec normalize_parsed_options(keyword()) :: {:ok, cli_options()} | {:error, String.t()}
  defp normalize_parsed_options(parsed) do
    with {:ok, backend} <- normalize_backend(parsed[:embedder_backend] || "fallback"),
         {:ok, level} <- normalize_log_level(parsed[:log_level]),
         {:ok, db_path} <- normalize_filesystem_path(parsed[:db], "--db"),
         {:ok, sqlite_vec_extension_path} <-
           normalize_filesystem_path(
             parsed[:sqlite_vec_extension_path],
             "--sqlite-vec-extension-path"
           ),
         {:ok, interval_ms} <-
           validate_positive_int(parsed[:consolidator_interval_ms], "--consolidator-interval-ms"),
         {:ok, timeout} <- validate_positive_int(parsed[:request_timeout], "--request-timeout"),
         {:ok, poll_interval_ms} <-
           validate_positive_int(parsed[:poll_interval_ms], "--poll-interval-ms"),
         {:ok, max_file_size_bytes} <-
           validate_positive_int(parsed[:max_file_size_bytes], "--max-file-size-bytes"),
         {:ok, max_read_bytes} <-
           validate_positive_int(parsed[:max_read_bytes], "--max-read-bytes"),
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
        |> maybe_put(:db_path, db_path)
        |> maybe_put(:embedding_model_id, parsed[:embedding_model])
        |> maybe_put(:embedder_backend, backend)
        |> maybe_put(:sqlite_vec_extension_path, sqlite_vec_extension_path)
        |> maybe_put(:consolidator_interval_ms, interval_ms)
        |> maybe_put(:consolidator_decay_rate, parsed[:consolidator_decay_rate])
        |> maybe_put(:consolidator_prune_threshold, parsed[:consolidator_prune_threshold])
        |> maybe_put(:consolidator_merge_similarity, parsed[:consolidator_merge_similarity])
        |> maybe_put(:learning_rate, parsed[:learning_rate])
        |> maybe_put(:log_level, level)
        |> maybe_put(:request_timeout, timeout)
        |> maybe_put(:recursive, parsed[:recursive])
        |> maybe_put(:include_hidden, parsed[:include_hidden])
        |> maybe_put(:follow_symlinks, parsed[:follow_symlinks])
        |> maybe_put(:extensions, normalize_extensions(parsed[:extensions]))
        |> maybe_put(:poll_interval_ms, poll_interval_ms)
        |> maybe_put(:ingest_on_start, parsed[:ingest_on_start])
        |> maybe_put(:max_file_size_bytes, max_file_size_bytes)
        |> maybe_put(:max_read_bytes, max_read_bytes)

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

      _ ->
        :ok
    end)

    # Keep STDOUT reserved for MCP protocol frames.
    # Route all Logger output (Elixir + Erlang handlers) to STDERR in CLI/MCP mode.
    force_stderr_logging!()

    # Keep MCP transport/protocol output clean for strict stdio clients.
    # Anubis logs are noisy during handshake and can interfere with clients that
    # aggressively parse startup output, so disable Anubis logging in CLI mode.
    Application.put_env(:anubis_mcp, :log, false)

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
      {:ok, supervisor_pid} ->
        {:ok, monitor_target_pid(supervisor_pid)}

      {:error, {:already_started, supervisor_pid}} ->
        {:ok, monitor_target_pid(supervisor_pid)}

      {:error, reason} ->
        halt_with_error("failed to start MCP stdio server: #{inspect(reason)}")
    end
  end

  @spec wait_forever(pid()) :: no_return()
  defp wait_forever(monitor_pid) when is_pid(monitor_pid) do
    ref = Process.monitor(monitor_pid)

    receive do
      {:DOWN, ^ref, :process, ^monitor_pid, reason} ->
        handle_server_termination(reason)

      {:EXIT, ^monitor_pid, reason} ->
        handle_server_termination(reason)
    after
      :infinity ->
        System.halt(0)
    end
  end

  @spec monitor_target_pid(pid()) :: pid()
  defp monitor_target_pid(supervisor_pid) when is_pid(supervisor_pid) do
    case resolve_stdio_transport_pid(20) do
      pid when is_pid(pid) -> pid
      _ -> supervisor_pid
    end
  end

  @spec resolve_stdio_transport_pid(non_neg_integer()) :: pid() | nil
  defp resolve_stdio_transport_pid(0), do: nil

  defp resolve_stdio_transport_pid(attempts) when is_integer(attempts) and attempts > 0 do
    case Anubis.Server.Registry.whereis_transport(Graphonomous.MCP.Server, :stdio) do
      pid when is_pid(pid) ->
        pid

      _ ->
        Process.sleep(10)
        resolve_stdio_transport_pid(attempts - 1)
    end
  end

  @spec handle_server_termination(term()) :: no_return()
  defp handle_server_termination(reason)
       when reason in [:normal, :shutdown, :eof] do
    System.halt(0)
  end

  defp handle_server_termination({:error, :eof}), do: System.halt(0)
  defp handle_server_termination({:shutdown, :normal}), do: System.halt(0)
  defp handle_server_termination({:shutdown, {:error, :eof}}), do: System.halt(0)

  defp handle_server_termination(reason) do
    halt_with_error("MCP server terminated: #{inspect(reason)}")
  end

  @spec parse_command([String.t()], keyword()) ::
          {:ok, cli_options()}
          | {:scan, String.t(), cli_options()}
          | {:watch, String.t(), cli_options()}
          | {:error, String.t()}
  defp parse_command([], parsed), do: normalize_parsed_options(parsed)

  defp parse_command(["scan", root_path], parsed) do
    with {:ok, opts} <- normalize_parsed_options(parsed) do
      {:scan, root_path, opts}
    end
  end

  defp parse_command(["watch", root_path], parsed) do
    with {:ok, opts} <- normalize_parsed_options(parsed) do
      {:watch, root_path, opts}
    end
  end

  defp parse_command(["scan"], _parsed), do: {:error, "missing required directory path for scan"}

  defp parse_command(["watch"], _parsed),
    do: {:error, "missing required directory path for watch"}

  defp parse_command(rest, _parsed) do
    {:error, "unexpected argument(s): #{Enum.join(rest, " ")}"}
  end

  @spec run_scan(String.t(), cli_options()) :: no_return()
  defp run_scan(root_path, opts) do
    case Graphonomous.FilesystemTraversal.scan_directory(root_path, filesystem_opts(opts)) do
      {:ok, result} ->
        IO.puts("scan complete")
        IO.puts("  root: #{result.root_path}")
        IO.puts("  discovered: #{result.files_discovered}")
        IO.puts("  ingested: #{result.files_ingested}")
        IO.puts("  failed: #{result.files_failed}")
        IO.puts("  duration_ms: #{result.duration_ms}")
        System.halt(0)

      {:error, reason} ->
        halt_with_error("scan failed: #{inspect(reason)}")
    end
  end

  @spec run_watch(String.t(), cli_options()) :: no_return()
  defp run_watch(root_path, opts) do
    IO.puts("watch started: #{root_path}")
    IO.puts("press Ctrl+C to stop")

    case Graphonomous.FilesystemTraversal.watch_directory(root_path, filesystem_opts(opts)) do
      {:stopped, _stats} ->
        System.halt(0)

      :ok ->
        System.halt(0)

      {:error, reason} ->
        halt_with_error("watch failed: #{inspect(reason)}")
    end
  end

  @spec filesystem_opts(cli_options()) :: keyword()
  defp filesystem_opts(opts) do
    []
    |> maybe_kw_put(:recursive, Map.get(opts, :recursive))
    |> maybe_kw_put(:include_hidden, Map.get(opts, :include_hidden))
    |> maybe_kw_put(:follow_symlinks, Map.get(opts, :follow_symlinks))
    |> maybe_kw_put(:extensions, Map.get(opts, :extensions))
    |> maybe_kw_put(:poll_interval_ms, Map.get(opts, :poll_interval_ms))
    |> maybe_kw_put(:ingest_on_start, Map.get(opts, :ingest_on_start))
    |> maybe_kw_put(:max_file_size_bytes, Map.get(opts, :max_file_size_bytes))
    |> maybe_kw_put(:max_read_bytes, Map.get(opts, :max_read_bytes))
  end

  @spec maybe_kw_put(keyword(), atom(), any()) :: keyword()
  defp maybe_kw_put(kw, _key, nil), do: kw
  defp maybe_kw_put(kw, key, value), do: Keyword.put(kw, key, value)

  @spec normalize_extensions(nil | String.t()) :: [String.t()] | nil
  defp normalize_extensions(nil), do: nil

  defp normalize_extensions(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp normalize_extensions(_), do: nil

  @spec normalize_backend(nil | String.t()) ::
          {:ok, :auto | :fallback | nil} | {:error, String.t()}
  defp normalize_backend(nil), do: {:ok, nil}
  defp normalize_backend("auto"), do: {:ok, :auto}
  defp normalize_backend("fallback"), do: {:ok, :fallback}

  defp normalize_backend(other),
    do: {:error, "invalid --embedder-backend=#{inspect(other)} (allowed: auto|fallback)"}

  @spec normalize_log_level(nil | String.t()) ::
          {:ok, Logger.level() | nil} | {:error, String.t()}
  defp normalize_log_level(nil), do: {:ok, :error}
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

  @spec normalize_filesystem_path(nil | String.t(), String.t()) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  defp normalize_filesystem_path(nil, _flag), do: {:ok, nil}

  defp normalize_filesystem_path(path, flag) when is_binary(path) do
    trimmed = String.trim(path)

    if trimmed == "" do
      {:error, "invalid #{flag}=#{inspect(path)} (must not be empty)"}
    else
      normalized =
        trimmed
        |> expand_user_path()
        |> Path.expand()

      {:ok, normalized}
    end
  end

  defp normalize_filesystem_path(other, flag),
    do: {:error, "invalid #{flag}=#{inspect(other)} (must be a string path)"}

  @spec expand_user_path(String.t()) :: String.t()
  defp expand_user_path(""), do: ""

  defp expand_user_path(path) do
    home = System.get_env("HOME") || ""

    cond do
      path == "~" and home != "" ->
        home

      String.starts_with?(path, "~/") and home != "" ->
        Path.join(home, String.trim_leading(path, "~/"))

      true ->
        path
    end
  end

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

  @spec force_stderr_logging!() :: :ok
  defp force_stderr_logging! do
    # Elixir console backend
    Logger.configure_backend(:console, device: :standard_error)

    # OTP logger default handler (and any fallback/legacy path).
    # Keep this best-effort so CLI startup never fails due to logger differences.
    try do
      :logger.set_handler_config(:default, :type, :standard_error)

      :logger.update_handler_config(:default, fn config ->
        handler_config = Map.get(config, :config, %{})
        updated_handler_config = Map.put(handler_config, :type, :standard_error)
        Map.put(config, :config, updated_handler_config)
      end)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
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
    Graphonomous CLI

    Usage:
      graphonomous [options]
      graphonomous scan <directory> [options]
      graphonomous watch <directory> [options]

    Global options:
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

    Filesystem traversal options (scan/watch):
          --recursive                          Traverse directories recursively (default: true)
          --include-hidden                     Include hidden files/directories
          --follow-symlinks                    Follow symlinks during traversal
          --extensions CSV                     Comma-separated extensions (example: .ex,.md,.txt)
          --poll-interval-ms MS                Watch poll interval in milliseconds (> 0)
          --ingest-on-start                    In watch mode, ingest existing files at startup
          --max-file-size-bytes N              Max file size to read for preview (> 0)
          --max-read-bytes N                   Max preview bytes read per file (> 0)

    Examples:
      graphonomous
      graphonomous --db ~/.graphonomous/knowledge.db
      graphonomous scan ./lib --extensions .ex,.exs
      graphonomous watch ./docs --poll-interval-ms 1500 --ingest-on-start
      graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback --log-level info
    """
  end
end
