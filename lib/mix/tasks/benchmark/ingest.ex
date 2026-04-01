defmodule Mix.Tasks.Benchmark.Ingest do
  @moduledoc """
  OS-E001 Benchmark: Corpus Ingestion via scan_directory

  Uses Graphonomous's native FilesystemTraversal.scan_directory to ingest
  the entire ProjectAmp2 codebase — the actual product feature, not a
  manual chunking workaround. Measures scan throughput, file discovery,
  and the resulting graph shape.

  Usage:
      mix benchmark.ingest [--purge] [--extensions .ex,.md,.json]

  Options:
      --purge       Clear existing graph before ingestion (default: true)
      --extensions  Comma-separated file extensions (default: .ex,.exs,.md,.json,.ts,.tsx,.js,.html,.css,.toml,.yml,.yaml)
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Ingest full ProjectAmp2 codebase via scan_directory"

  @default_extensions ~w(.ex .exs .md .json .ts .tsx .js .html .css .toml .yml .yaml)

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [purge: :boolean, extensions: :string])
    purge? = Keyword.get(opts, :purge, true)

    extensions =
      case Keyword.get(opts, :extensions) do
        nil -> @default_extensions
        ext_str -> String.split(ext_str, ",", trim: true)
      end

    Helpers.ensure_started()
    if purge?, do: Helpers.purge_graph()

    portfolio_root = Helpers.portfolio_root()

    Mix.shell().info("=== OS-E001 Benchmark: Corpus Ingestion (scan_directory) ===")
    Mix.shell().info("Scanning: #{portfolio_root}")
    Mix.shell().info("Extensions: #{Enum.join(extensions, ", ")}")

    # Phase 1: Run scan_directory on the full portfolio
    {scan_us, scan_result} =
      Helpers.timed(fn ->
        Graphonomous.FilesystemTraversal.scan_directory(
          portfolio_root,
          recursive: true,
          include_hidden: false,
          follow_symlinks: false,
          extensions: extensions,
          respect_gitignore: false,
          max_file_size_bytes: 1_000_000,
          max_read_bytes: 16_384
        )
      end)

    case scan_result do
      {:ok, result} ->
        Mix.shell().info(
          "Scan complete: #{result.files_discovered} discovered, #{result.files_ingested} ingested, #{result.files_failed} failed"
        )

        if result.errors != [] do
          Enum.take(result.errors, 5)
          |> Enum.each(fn err -> Mix.shell().info("  ERR: #{inspect(err)}") end)

          if length(result.errors) > 5 do
            Mix.shell().info("  ... and #{length(result.errors) - 5} more")
          end
        end

        # Phase 2: Analyze what scan produced
        Mix.shell().info("Analyzing graph state after scan...")

        nodes = Graphonomous.list_nodes(%{limit: 100_000}) || []
        node_count = length(nodes)

        by_type =
          nodes
          |> Enum.group_by(& &1.node_type)
          |> Enum.map(fn {type, items} -> {type, length(items)} end)
          |> Map.new()

        by_source =
          nodes
          |> Enum.group_by(fn n -> Map.get(n, :source, "unknown") end)
          |> Enum.map(fn {src, items} -> {src, length(items)} end)
          |> Map.new()

        # Extract extension distribution from metadata
        ext_dist =
          nodes
          |> Enum.map(fn n ->
            meta = Map.get(n, :metadata, %{})
            Map.get(meta, "extension", "unknown")
          end)
          |> Enum.frequencies()

        confidences = Enum.map(nodes, & &1.confidence)

        # Phase 3: Create cross-domain edges for known [&] ecosystem relationships
        Mix.shell().info("Creating cross-domain edges...")
        {edge_us, edge_count} = Helpers.timed(fn -> create_cross_domain_edges(nodes) end)

        results = %{
          benchmark: "OS-E001:ingest",
          method: "scan_directory",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          scan: %{
            root_path: result.root_path,
            files_discovered: result.files_discovered,
            files_ingested: result.files_ingested,
            files_failed: result.files_failed,
            scan_duration_ms: result.duration_ms,
            error_count: length(result.errors)
          },
          extensions: extensions,
          performance: %{
            total_scan_us: scan_us,
            edge_creation_us: edge_us,
            throughput_files_per_sec:
              result.files_ingested / max(result.duration_ms / 1000, 0.001)
          },
          graph: %{
            node_count: node_count,
            edges_created: edge_count,
            by_type: by_type,
            by_source: by_source,
            extension_distribution: ext_dist,
            confidence: %{
              min: Enum.min(confidences, fn -> 0.0 end),
              max: Enum.max(confidences, fn -> 0.0 end),
              mean: safe_mean(confidences)
            }
          }
        }

        path = Helpers.write_results("ingest", results)

        Mix.shell().info("""

        === Ingestion Complete (scan_directory) ===
        Files discovered: #{result.files_discovered}
        Files ingested:   #{result.files_ingested}
        Files failed:     #{result.files_failed}
        Scan time:        #{result.duration_ms} ms
        Nodes in graph:   #{node_count}
        Edges created:    #{edge_count}
        By type:          #{inspect(by_type)}
        Throughput:       #{Float.round(results.performance.throughput_files_per_sec, 1)} files/sec
        Output:           #{path}
        """)

      {:error, reason} ->
        Mix.shell().error("Scan failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # Create edges between nodes from different subdirectories that have known relationships.
  # Detects domain from the file path in node metadata.
  defp create_cross_domain_edges(nodes) do
    # Group nodes by detected project domain
    by_domain =
      nodes
      |> Enum.map(fn n ->
        meta = Map.get(n, :metadata, %{})
        path = Map.get(meta, "relative_path", "") |> to_string()
        domain = detect_domain(path)
        {domain, n}
      end)
      |> Enum.filter(fn {d, _} -> d != nil end)
      |> Enum.group_by(fn {d, _} -> d end, fn {_, n} -> n end)

    edges = [
      {"opensentience.org", "graphonomous", :derived_from, 0.9},
      {"graphonomous", "AmpersandBoxDesign", :derived_from, 0.85},
      {"WebHost.Systems", "AmpersandBoxDesign", :derived_from, 0.8},
      {"agentromatic.com", "opensentience.org", :derived_from, 0.85},
      {"delegatic.com", "opensentience.org", :derived_from, 0.85},
      {"bendscript.com", "graphonomous", :related, 0.7},
      {"fleetprompt.com", "agentelic.com", :related, 0.7},
      {"geofleetic.com", "ticktickclock.com", :related, 0.8},
      # κ cycle: ampersand defines → graphonomous implements → ampersand references
      {"AmpersandBoxDesign", "graphonomous", :supports, 0.9}
    ]

    Enum.reduce(edges, 0, fn {src_domain, tgt_domain, edge_type, weight}, count ->
      src_nodes = Map.get(by_domain, src_domain, [])
      tgt_nodes = Map.get(by_domain, tgt_domain, [])

      if src_nodes != [] and tgt_nodes != [] do
        src = List.first(src_nodes)
        tgt = List.first(tgt_nodes)

        Graphonomous.link_nodes(src.id, tgt.id, %{
          edge_type: Atom.to_string(edge_type),
          weight: weight,
          metadata: %{"benchmark" => "OS-E001", "cross_domain" => true}
        })

        count + 1
      else
        count
      end
    end)
  end

  defp detect_domain(path) do
    cond do
      String.starts_with?(path, "graphonomous/") and
          not String.starts_with?(path, "graphonomous.com/") ->
        "graphonomous"

      String.starts_with?(path, "WebHost.Systems/") ->
        "WebHost.Systems"

      String.starts_with?(path, "AmpersandBoxDesign/") ->
        "AmpersandBoxDesign"

      String.starts_with?(path, "bendscript.com/") ->
        "bendscript.com"

      String.starts_with?(path, "opensentience.org/") ->
        "opensentience.org"

      String.starts_with?(path, "agentromatic.com/") ->
        "agentromatic.com"

      String.starts_with?(path, "agentelic.com/") ->
        "agentelic.com"

      String.starts_with?(path, "delegatic.com/") ->
        "delegatic.com"

      String.starts_with?(path, "deliberatic.com/") ->
        "deliberatic.com"

      String.starts_with?(path, "fleetprompt.com/") ->
        "fleetprompt.com"

      String.starts_with?(path, "geofleetic.com/") ->
        "geofleetic.com"

      String.starts_with?(path, "ticktickclock.com/") ->
        "ticktickclock.com"

      String.starts_with?(path, "specprompt.com/") ->
        "specprompt.com"

      String.starts_with?(path, "graphonomous.com/") ->
        "graphonomous.com"

      true ->
        nil
    end
  end

  defp safe_mean([]), do: 0.0
  defp safe_mean(list), do: Enum.sum(list) / length(list)
end
