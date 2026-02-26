defmodule Graphonomous.FilesystemTraversal do
  @moduledoc """
  Filesystem traversal utilities for Graphonomous.

  This module intentionally stays simple:

  - `scan_directory/2` performs a one-shot traversal and ingestion pass.
  - `watch_directory/2` runs a polling loop and ingests file change events.
  - `start_watch/2` and `stop_watch/1` provide a lightweight process wrapper.

  The default ingestion behavior writes an episodic node through `Graphonomous.store_node/1`.
  You can override ingestion with `:ingest_fun`.
  """

  require Logger

  @default_poll_interval_ms 1_000
  @default_max_file_size_bytes 1_000_000
  @default_max_read_bytes 16_384

  @type change_type :: :added | :modified | :removed

  @type event :: %{
          type: change_type(),
          root_path: String.t(),
          path: String.t(),
          relative_path: String.t(),
          stat: File.Stat.t() | nil
        }

  @type scan_result :: %{
          root_path: String.t(),
          files_discovered: non_neg_integer(),
          files_ingested: non_neg_integer(),
          files_failed: non_neg_integer(),
          duration_ms: non_neg_integer(),
          errors: [map()]
        }

  @type watch_result :: :ok | {:stopped, map()} | {:error, term()}

  @type opts :: [
          {:recursive, boolean()}
          | {:include_hidden, boolean()}
          | {:follow_symlinks, boolean()}
          | {:extensions, [String.t()]}
          | {:poll_interval_ms, pos_integer()}
          | {:max_file_size_bytes, pos_integer()}
          | {:max_read_bytes, pos_integer()}
          | {:ingest_on_start, boolean()}
          | {:respect_gitignore, boolean()}
          | {:on_error, :log | :ignore}
          | {:ingest_fun, (event() -> :ok | {:error, term()})}
          | {:on_cycle, (map() -> any())}
        ]

  @typep snapshot :: %{
           optional(String.t()) => %{
             size: non_neg_integer(),
             mtime: term(),
             content_sig: String.t() | nil
           }
         }

  # --------------------
  # Public API
  # --------------------

  @doc """
  Traverse a directory once and ingest each discovered file as an `:added` event.

  Returns a summary map with counts and per-file errors.
  """
  @spec scan_directory(String.t(), opts()) :: {:ok, scan_result()} | {:error, term()}
  def scan_directory(root_path, opts \\ []) when is_binary(root_path) and is_list(opts) do
    started_ms = System.monotonic_time(:millisecond)

    with {:ok, cfg} <- build_config(root_path, opts),
         {:ok, files} <- list_files(cfg) do
      {ok_count, err_count, errors} =
        Enum.reduce(files, {0, 0, []}, fn path, {ok_acc, err_acc, errs_acc} ->
          event = build_event(:added, cfg.root_path, path, safe_stat(path))

          case run_ingest(cfg.ingest_fun, event) do
            :ok ->
              {ok_acc + 1, err_acc, errs_acc}

            {:error, reason} ->
              {ok_acc, err_acc + 1, [%{path: path, reason: inspect(reason)} | errs_acc]}
          end
        end)

      duration_ms = max(System.monotonic_time(:millisecond) - started_ms, 0)

      {:ok,
       %{
         root_path: cfg.root_path,
         files_discovered: length(files),
         files_ingested: ok_count,
         files_failed: err_count,
         duration_ms: duration_ms,
         errors: Enum.reverse(errors)
       }}
    end
  end

  @doc """
  Start a blocking polling watch loop for filesystem changes.

  Send `:stop` to the process running this function to terminate gracefully.
  """
  @spec watch_directory(String.t(), opts()) :: watch_result()
  def watch_directory(root_path, opts \\ []) when is_binary(root_path) and is_list(opts) do
    startup_notify = Keyword.get(opts, :startup_notify)
    startup_ref = Keyword.get(opts, :startup_ref)

    with {:ok, cfg} <- build_config(root_path, opts),
         {:ok, initial_snapshot} <- build_snapshot(cfg) do
      initial_stats = %{
        root_path: cfg.root_path,
        cycle: 0,
        events_seen: 0,
        ingested: 0,
        failed: 0,
        last_polled_at: nil,
        tracked_files: map_size(initial_snapshot),
        started_at: DateTime.utc_now()
      }

      if cfg.ingest_on_start do
        _ = ingest_snapshot(cfg, initial_snapshot)
      end

      if is_pid(startup_notify) and is_reference(startup_ref) do
        send(startup_notify, {:filesystem_watch_started, self(), startup_ref})
      end

      loop_watch(cfg, initial_snapshot, initial_stats)
    end
  end

  @doc """
  Start watch loop in a linked process and return `{:ok, pid}` once initial
  baseline snapshot is ready.
  """
  @spec start_watch(String.t(), opts()) :: {:ok, pid()} | {:error, term()}
  def start_watch(root_path, opts \\ []) when is_binary(root_path) and is_list(opts) do
    parent = self()
    startup_ref = make_ref()

    pid =
      spawn_link(fn ->
        result =
          watch_directory(
            root_path,
            Keyword.merge(opts, startup_notify: parent, startup_ref: startup_ref)
          )

        send(parent, {:filesystem_watch_exit, self(), result})
      end)

    receive do
      {:filesystem_watch_started, ^pid, ^startup_ref} ->
        {:ok, pid}

      {:filesystem_watch_exit, ^pid, {:error, reason}} ->
        {:error, reason}

      {:filesystem_watch_exit, ^pid, other} ->
        {:error, {:watch_failed_before_start, other}}
    after
      5_000 ->
        {:error, :startup_timeout}
    end
  end

  @doc """
  Stop a watcher process created by `start_watch/2`.
  """
  @spec stop_watch(pid()) :: :ok
  def stop_watch(pid) when is_pid(pid) do
    send(pid, :stop)
    :ok
  end

  # --------------------
  # Watch loop
  # --------------------

  defp loop_watch(cfg, snapshot, stats) do
    receive do
      :stop ->
        {:stopped, Map.put(stats, :stopped_at, DateTime.utc_now())}
    after
      cfg.poll_interval_ms ->
        case build_snapshot(cfg) do
          {:ok, new_snapshot} ->
            changes = diff_snapshots(snapshot, new_snapshot, cfg.root_path)
            {ok_count, err_count} = ingest_changes(cfg, changes)

            new_stats = %{
              stats
              | cycle: stats.cycle + 1,
                events_seen: stats.events_seen + length(changes),
                ingested: stats.ingested + ok_count,
                failed: stats.failed + err_count,
                last_polled_at: DateTime.utc_now(),
                tracked_files: map_size(new_snapshot)
            }

            maybe_emit_cycle(new_stats, cfg.on_cycle)
            loop_watch(cfg, new_snapshot, new_stats)

          {:error, reason} ->
            maybe_handle_error(cfg.on_error, "watch cycle failed: #{inspect(reason)}")

            new_stats = %{
              stats
              | cycle: stats.cycle + 1,
                last_polled_at: DateTime.utc_now()
            }

            maybe_emit_cycle(new_stats, cfg.on_cycle)
            loop_watch(cfg, snapshot, new_stats)
        end
    end
  end

  defp maybe_emit_cycle(stats, on_cycle) when is_function(on_cycle, 1) do
    try do
      on_cycle.(stats)
    rescue
      _ -> :ok
    end
  end

  defp maybe_emit_cycle(_stats, _), do: :ok

  # --------------------
  # Config
  # --------------------

  defp build_config(root_path, opts) do
    with {:ok, root} <- normalize_root(root_path) do
      poll_interval_ms =
        opts
        |> Keyword.get(:poll_interval_ms, @default_poll_interval_ms)
        |> normalize_pos_int(@default_poll_interval_ms)

      max_file_size_bytes =
        opts
        |> Keyword.get(:max_file_size_bytes, @default_max_file_size_bytes)
        |> normalize_pos_int(@default_max_file_size_bytes)

      max_read_bytes =
        opts
        |> Keyword.get(:max_read_bytes, @default_max_read_bytes)
        |> normalize_pos_int(@default_max_read_bytes)

      ingest_fun =
        case Keyword.get(opts, :ingest_fun) do
          fun when is_function(fun, 1) ->
            fun

          _ ->
            fn event ->
              default_ingest(event, max_file_size_bytes, max_read_bytes)
            end
        end

      {:ok,
       %{
         root_path: root,
         recursive: Keyword.get(opts, :recursive, true),
         include_hidden: Keyword.get(opts, :include_hidden, false),
         follow_symlinks: Keyword.get(opts, :follow_symlinks, false),
         extensions: normalize_extensions(Keyword.get(opts, :extensions)),
         poll_interval_ms: poll_interval_ms,
         max_file_size_bytes: max_file_size_bytes,
         max_read_bytes: max_read_bytes,
         ingest_on_start: Keyword.get(opts, :ingest_on_start, false),
         respect_gitignore: Keyword.get(opts, :respect_gitignore, true),
         on_error: normalize_on_error(Keyword.get(opts, :on_error, :log)),
         ingest_fun: ingest_fun,
         on_cycle: Keyword.get(opts, :on_cycle)
       }}
    end
  end

  defp normalize_root(path) when is_binary(path) do
    expanded =
      path
      |> String.trim()
      |> expand_user_path()
      |> Path.expand()

    with true <- expanded != "",
         {:ok, stat} <- File.stat(expanded),
         true <- stat.type == :directory do
      {:ok, expanded}
    else
      false -> {:error, :invalid_root_path}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_a_directory}
    end
  end

  defp expand_user_path("~") do
    System.user_home() || "~"
  end

  defp expand_user_path(path) do
    case System.user_home() do
      home when is_binary(home) and home != "" and is_binary(path) ->
        if String.starts_with?(path, "~/") do
          Path.join(home, String.trim_leading(path, "~/"))
        else
          path
        end

      _ ->
        path
    end
  end

  defp normalize_extensions(nil), do: nil
  defp normalize_extensions([]), do: nil

  defp normalize_extensions(list) when is_list(list) do
    normalized =
      list
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn ext ->
        ext = String.downcase(ext)
        if String.starts_with?(ext, "."), do: ext, else: "." <> ext
      end)

    if normalized == [], do: nil, else: MapSet.new(normalized)
  end

  defp normalize_extensions(_), do: nil

  defp normalize_on_error(:log), do: :log
  defp normalize_on_error(:ignore), do: :ignore
  defp normalize_on_error(_), do: :log

  defp normalize_pos_int(value, fallback) when is_integer(value) and value > 0, do: value
  defp normalize_pos_int(_, fallback), do: fallback

  # --------------------
  # Traversal and snapshots
  # --------------------

  defp list_files(cfg) do
    case do_list_files(cfg.root_path, cfg, [], []) do
      {:ok, files} ->
        files =
          files
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, files}

      {:error, _} = err ->
        err
    end
  end

  defp do_list_files(dir, cfg, acc, inherited_gitignore_rules) do
    current_gitignore_rules =
      if Map.get(cfg, :respect_gitignore, true) do
        parse_gitignore_rules(dir)
      else
        []
      end

    active_gitignore_rules = inherited_gitignore_rules ++ current_gitignore_rules

    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, acc}, fn entry, {:ok, files_acc} ->
          if skip_entry?(entry, cfg.include_hidden) do
            {:cont, {:ok, files_acc}}
          else
            path = Path.join(dir, entry)

            case File.lstat(path) do
              {:ok, %File.Stat{type: :regular}} ->
                ignored? =
                  ignored_by_gitignore?(
                    path,
                    :regular,
                    cfg.root_path,
                    active_gitignore_rules
                  )

                cond do
                  ignored? ->
                    {:cont, {:ok, files_acc}}

                  include_extension?(path, cfg.extensions) ->
                    {:cont, {:ok, [path | files_acc]}}

                  true ->
                    {:cont, {:ok, files_acc}}
                end

              {:ok, %File.Stat{type: :directory}} ->
                ignored? =
                  ignored_by_gitignore?(
                    path,
                    :directory,
                    cfg.root_path,
                    active_gitignore_rules
                  )

                cond do
                  ignored? ->
                    {:cont, {:ok, files_acc}}

                  cfg.recursive ->
                    case do_list_files(path, cfg, files_acc, active_gitignore_rules) do
                      {:ok, nested} -> {:cont, {:ok, nested}}
                      {:error, reason} -> {:halt, {:error, reason}}
                    end

                  true ->
                    {:cont, {:ok, files_acc}}
                end

              {:ok, %File.Stat{type: :symlink}} ->
                if cfg.follow_symlinks do
                  case File.stat(path) do
                    {:ok, %File.Stat{type: :regular}} ->
                      ignored? =
                        ignored_by_gitignore?(
                          path,
                          :regular,
                          cfg.root_path,
                          active_gitignore_rules
                        )

                      cond do
                        ignored? ->
                          {:cont, {:ok, files_acc}}

                        include_extension?(path, cfg.extensions) ->
                          {:cont, {:ok, [path | files_acc]}}

                        true ->
                          {:cont, {:ok, files_acc}}
                      end

                    {:ok, %File.Stat{type: :directory}} ->
                      ignored? =
                        ignored_by_gitignore?(
                          path,
                          :directory,
                          cfg.root_path,
                          active_gitignore_rules
                        )

                      cond do
                        ignored? ->
                          {:cont, {:ok, files_acc}}

                        cfg.recursive ->
                          case do_list_files(path, cfg, files_acc, active_gitignore_rules) do
                            {:ok, nested} -> {:cont, {:ok, nested}}
                            {:error, reason} -> {:halt, {:error, reason}}
                          end

                        true ->
                          {:cont, {:ok, files_acc}}
                      end

                    _ ->
                      {:cont, {:ok, files_acc}}
                  end
                else
                  {:cont, {:ok, files_acc}}
                end

              _ ->
                {:cont, {:ok, files_acc}}
            end
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_gitignore_rules(dir) do
    gitignore_path = Path.join(dir, ".gitignore")

    case File.read(gitignore_path) do
      {:ok, body} ->
        body
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.reduce([], fn {line, line_no}, acc ->
          parsed = parse_gitignore_line(line)

          case parsed do
            nil ->
              acc

            %{pattern: pattern, negated?: negated?, directory_only?: directory_only?, anchored?: anchored?} ->
              acc ++
                [
                  %{
                    base_dir: dir,
                    line_no: line_no,
                    pattern: pattern,
                    negated?: negated?,
                    directory_only?: directory_only?,
                    anchored?: anchored?
                  }
                ]
          end
        end)

      {:error, _reason} ->
        []
    end
  end

  defp parse_gitignore_line(raw_line) when is_binary(raw_line) do
    line = String.trim(raw_line)

    cond do
      line == "" ->
        nil

      String.starts_with?(line, "#") ->
        nil

      true ->
        {negated?, pattern0} =
          if String.starts_with?(line, "!") do
            {true, String.trim_leading(line, "!")}
          else
            {false, line}
          end

        pattern0 = String.trim(pattern0)

        if pattern0 == "" do
          nil
        else
          anchored? = String.starts_with?(pattern0, "/")
          directory_only? = String.ends_with?(pattern0, "/")

          pattern1 =
            pattern0
            |> String.trim_leading("/")
            |> String.trim_trailing("/")

          if pattern1 == "" do
            nil
          else
            %{
              pattern: normalize_rel_path(pattern1),
              negated?: negated?,
              directory_only?: directory_only?,
              anchored?: anchored?
            }
          end
        end
    end
  end

  defp ignored_by_gitignore?(path, type, root_path, rules) do
    Enum.reduce(rules, false, fn rule, ignored? ->
      if gitignore_rule_matches?(rule, path, type, root_path) do
        not rule.negated?
      else
        ignored?
      end
    end)
  end

  defp gitignore_rule_matches?(rule, path, type, root_path) do
    rel_to_rule_dir = Path.relative_to(path, rule.base_dir)

    cond do
      rel_to_rule_dir == "." ->
        false

      String.starts_with?(rel_to_rule_dir, "../") ->
        false

      rule.directory_only? and type != :directory ->
        false

      true ->
        rel = normalize_rel_path(rel_to_rule_dir)

        if rule.anchored? do
          glob_match_path?(rule.pattern, rel)
        else
          unanchored_gitignore_match?(rule.pattern, rel, root_path, path)
        end
    end
  end

  defp unanchored_gitignore_match?(pattern, rel, _root_path, _path) do
    if String.contains?(pattern, "/") do
      glob_match_path?(pattern, rel) or glob_match_path?("**/" <> pattern, rel)
    else
      segments = String.split(rel, "/", trim: true)
      Enum.any?(segments, &glob_match_segment?(pattern, &1))
    end
  end

  defp glob_match_path?(pattern, value) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", "§§DOUBLESTAR§§")
      |> String.replace("\\*", "[^/]*")
      |> String.replace("\\?", "[^/]")
      |> String.replace("§§DOUBLESTAR§§", ".*")
      |> then(&"^" <> &1 <> "$")

    Regex.match?(Regex.compile!(regex), value)
  end

  defp glob_match_segment?(pattern, value) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")
      |> then(&"^" <> &1 <> "$")

    Regex.match?(Regex.compile!(regex), value)
  end

  defp normalize_rel_path(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim_leading("./")
  end

  defp build_snapshot(cfg) do
    with {:ok, files} <- list_files(cfg) do
      snapshot =
        Enum.reduce(files, %{}, fn path, acc ->
          case File.stat(path) do
            {:ok, %File.Stat{} = stat} ->
              Map.put(acc, path, %{
                size: stat.size,
                mtime: stat.mtime,
                content_sig: file_content_signature(path)
              })

            _ ->
              acc
          end
        end)

      {:ok, snapshot}
    end
  end

  defp file_content_signature(path) do
    case File.read(path) do
      {:ok, binary} ->
        :crypto.hash(:sha256, binary)
        |> Base.encode16(case: :lower)

      {:error, _reason} ->
        nil
    end
  end

  defp diff_snapshots(old_snapshot, new_snapshot, root_path) do
    old_keys = old_snapshot |> Map.keys() |> MapSet.new()
    new_keys = new_snapshot |> Map.keys() |> MapSet.new()

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    added_events =
      Enum.map(added_keys, fn path ->
        build_event(:added, root_path, path, safe_stat(path))
      end)

    removed_events =
      Enum.map(removed_keys, fn path ->
        build_event(:removed, root_path, path, nil)
      end)

    modified_events =
      Enum.reduce(common_keys, [], fn path, acc ->
        if Map.get(old_snapshot, path) != Map.get(new_snapshot, path) do
          [build_event(:modified, root_path, path, safe_stat(path)) | acc]
        else
          acc
        end
      end)

    added_events ++ removed_events ++ modified_events
  end

  defp build_event(type, root_path, path, stat) do
    %{
      type: type,
      root_path: root_path,
      path: path,
      relative_path: Path.relative_to(path, root_path),
      stat: stat
    }
  end

  # --------------------
  # Ingestion
  # --------------------

  defp ingest_snapshot(cfg, snapshot) do
    Enum.each(Map.keys(snapshot), fn path ->
      _ =
        run_ingest(
          cfg.ingest_fun,
          build_event(:added, cfg.root_path, path, safe_stat(path))
        )
    end)

    :ok
  end

  defp ingest_changes(cfg, events) do
    Enum.reduce(events, {0, 0}, fn event, {ok_acc, err_acc} ->
      case run_ingest(cfg.ingest_fun, event) do
        :ok ->
          {ok_acc + 1, err_acc}

        {:error, reason} ->
          maybe_handle_error(cfg.on_error, "ingest failed for #{event.path}: #{inspect(reason)}")
          {ok_acc, err_acc + 1}
      end
    end)
  end

  defp run_ingest(ingest_fun, event) when is_function(ingest_fun, 1) do
    try do
      ingest_fun.(event)
    rescue
      error -> {:error, {:exception, error}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp default_ingest(event, max_file_size_bytes, max_read_bytes) do
    payload = build_default_payload(event, max_file_size_bytes, max_read_bytes)

    case Graphonomous.store_node(payload) do
      %{id: _id} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  rescue
    error ->
      {:error, {:store_node_exception, error}}
  end

  defp build_default_payload(event, max_file_size_bytes, max_read_bytes) do
    {preview, read_state} =
      case event.type do
        :removed ->
          {"", :removed}

        _ ->
          read_preview(event.path, max_file_size_bytes, max_read_bytes)
      end

    content =
      case {event.type, preview} do
        {:removed, _} ->
          "[filesystem removed] #{event.relative_path}"

        {_, text} when is_binary(text) and text != "" ->
          "[filesystem #{event.type}] #{event.relative_path}\n\n#{text}"

        _ ->
          "[filesystem #{event.type}] #{event.relative_path}"
      end

    metadata = %{
      "source" => "filesystem_traversal",
      "event_type" => to_string(event.type),
      "path" => event.path,
      "relative_path" => event.relative_path,
      "extension" => Path.extname(event.path),
      "size" => if(is_struct(event.stat, File.Stat), do: event.stat.size, else: nil),
      "mtime" => if(is_struct(event.stat, File.Stat), do: inspect(event.stat.mtime), else: nil),
      "read_state" => to_string(read_state)
    }

    %{
      content: content,
      node_type: :episodic,
      confidence: confidence_for_event(event.type),
      source: "filesystem_traversal",
      metadata: metadata
    }
  end

  defp read_preview(path, max_file_size_bytes, max_read_bytes) do
    with {:ok, %File.Stat{} = stat} <- File.stat(path),
         true <- stat.size <= max_file_size_bytes,
         {:ok, binary} <- File.read(path) do
      snippet = maybe_truncate(binary, max_read_bytes)

      if String.valid?(snippet) do
        {String.trim(snippet), :ok}
      else
        {"", :binary}
      end
    else
      false -> {"", :too_large}
      {:error, reason} -> {"", reason}
      _ -> {"", :unreadable}
    end
  end

  defp maybe_truncate(binary, max_read_bytes)
       when is_binary(binary) and byte_size(binary) > max_read_bytes do
    :binary.part(binary, 0, max_read_bytes)
  end

  defp maybe_truncate(binary, _), do: binary

  defp confidence_for_event(:added), do: 0.65
  defp confidence_for_event(:modified), do: 0.70
  defp confidence_for_event(:removed), do: 0.60
  defp confidence_for_event(_), do: 0.60

  # --------------------
  # Helpers
  # --------------------

  defp skip_entry?(entry, include_hidden) do
    cond do
      entry == ".git" -> true
      entry == ".gitignore" -> true
      not include_hidden and String.starts_with?(entry, ".") -> true
      true -> false
    end
  end

  defp include_extension?(_path, nil), do: true

  defp include_extension?(path, %MapSet{} = exts) do
    ext = path |> Path.extname() |> String.downcase()
    MapSet.member?(exts, ext)
  end

  defp safe_stat(path) do
    case File.stat(path) do
      {:ok, stat} -> stat
      _ -> nil
    end
  end

  defp maybe_handle_error(:ignore, _message), do: :ok

  defp maybe_handle_error(:log, message) when is_binary(message) do
    Logger.warning(message)
    :ok
  end
end
