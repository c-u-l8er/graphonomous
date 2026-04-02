defmodule Mix.Tasks.Benchmark.Retrieval do
  @moduledoc """
  OS-E001 Benchmark: Retrieval Quality

  Measures cross-domain retrieval precision, recall, and latency using
  a battery of queries designed to test different retrieval scenarios:

  1. Single-domain queries (should return nodes from one domain)
  2. Cross-domain queries (should return nodes from multiple domains)
  3. Conceptual queries (abstract concepts spanning the ecosystem)
  4. Needle-in-haystack queries (specific facts buried in large corpus)

  Requires: `mix benchmark.ingest` to have been run first.

  Usage:
      mix benchmark.retrieval
  """

  use Mix.Task

  alias Mix.Tasks.Benchmark.Helpers

  @shortdoc "Benchmark retrieval quality across [&] portfolio"

  @query_battery [
    # Single-domain: should primarily return graphonomous nodes
    %{
      id: "SD-1",
      query: "How does the knowledge graph store nodes and edges in SQLite?",
      expected_domains: ["graphonomous"],
      category: :single_domain
    },
    %{
      id: "SD-2",
      query: "What are the WebHost.Systems API contracts for runtime deployment?",
      expected_domains: ["webhost"],
      category: :single_domain
    },
    %{
      id: "SD-3",
      query: "How does the agent marketplace handle bidding and reputation?",
      expected_domains: ["fleetprompt"],
      category: :single_domain
    },

    # Cross-domain: should pull from multiple domains
    %{
      id: "CD-1",
      query: "How does governance interact with memory and learning?",
      expected_domains: ["opensentience", "graphonomous", "delegatic"],
      category: :cross_domain
    },
    %{
      id: "CD-2",
      query: "What protocols does the [&] ecosystem define for agent coordination?",
      expected_domains: ["opensentience", "ampersand", "agentromatic"],
      category: :cross_domain
    },
    %{
      id: "CD-3",
      query: "How do spatial and temporal intelligence relate to each other?",
      expected_domains: ["geofleetic", "ticktickclock"],
      category: :cross_domain
    },
    %{
      id: "CD-4",
      query: "What security and compliance requirements exist across the ecosystem?",
      expected_domains: ["webhost", "opensentience", "delegatic"],
      category: :cross_domain
    },

    # Conceptual: abstract queries testing semantic understanding
    %{
      id: "CQ-1",
      query: "What is the relationship between cyclicity and deliberation depth?",
      expected_domains: ["graphonomous", "ampersand", "agentromatic"],
      category: :conceptual
    },
    %{
      id: "CQ-2",
      query: "How does confidence decay over time and why does it matter?",
      expected_domains: ["graphonomous"],
      category: :conceptual
    },
    %{
      id: "CQ-3",
      query: "What does 'the symbol is the system' mean in practice?",
      expected_domains: ["ampersand", "specprompt"],
      category: :conceptual
    },

    # Needle-in-haystack: specific facts that exist in exactly one place
    %{
      id: "NH-1",
      query: "What is the default prune threshold for the consolidator?",
      expected_domains: ["graphonomous"],
      category: :needle
    },
    %{
      id: "NH-2",
      query: "What OTP pattern does the lifecycle manager use?",
      expected_domains: ["opensentience"],
      category: :needle
    },
    %{
      id: "NH-3",
      query: "What is the migration number range for BendScript's kag schema?",
      expected_domains: ["webhost", "bendscript"],
      category: :needle
    }
  ]

  @impl Mix.Task
  def run(_args) do
    Helpers.ensure_started()

    Mix.shell().info("=== OS-E001 Benchmark: Retrieval Quality ===")

    # Verify corpus exists
    nodes = Graphonomous.list_nodes(%{limit: 1})

    if nodes == [] or nodes == nil do
      Mix.shell().error("No nodes found. Run `mix benchmark.ingest` first.")
      exit({:shutdown, 1})
    end

    Mix.shell().info("Running #{length(@query_battery)} queries...")

    query_results =
      Enum.map(@query_battery, fn q ->
        Mix.shell().info("  [#{q.id}] #{q.category} ...")

        # Run with expansion to test graph traversal
        {retrieval_us, retrieval} =
          Helpers.timed(fn ->
            Graphonomous.retrieve_context(q.query,
              limit: 10,
              expansion_hops: 1,
              neighbors_per_node: 3
            )
          end)

        # Also run without expansion (flat similarity baseline)
        {flat_us, flat_retrieval} =
          Helpers.timed(fn ->
            Graphonomous.retrieve_context(q.query,
              limit: 10,
              expansion_hops: 0
            )
          end)

        results = Map.get(retrieval, :results, [])
        flat_results = Map.get(flat_retrieval, :results, [])
        topology = Map.get(retrieval, :topology, %{})

        # Extract domains from results via metadata
        result_domains = extract_domains(results)
        flat_domains = extract_domains(flat_results)

        # Precision: what fraction of returned results are from expected domains?
        precision = domain_precision(result_domains, q.expected_domains)
        flat_precision = domain_precision(flat_domains, q.expected_domains)

        # Recall: what fraction of expected domains appear in results?
        recall = domain_recall(result_domains, q.expected_domains)
        flat_recall = domain_recall(flat_domains, q.expected_domains)

        # Domain diversity: how many unique domains in results?
        unique_domains = result_domains |> Enum.uniq() |> length()
        flat_unique = flat_domains |> Enum.uniq() |> length()

        %{
          id: q.id,
          query: q.query,
          category: q.category,
          expected_domains: q.expected_domains,
          graph_expanded: %{
            latency_us: retrieval_us,
            result_count: length(results),
            domains_returned: Enum.uniq(result_domains),
            unique_domain_count: unique_domains,
            precision: Float.round(precision, 4),
            recall: Float.round(recall, 4),
            f1: Float.round(f1(precision, recall), 4),
            top_3_scores: results |> Enum.take(3) |> Enum.map(& &1.score),
            topology_routing: Map.get(topology, :routing),
            topology_max_kappa: Map.get(topology, :max_kappa, 0),
            seed_count: get_in(retrieval, [:stats, :seed_count]) || 0,
            expanded_count: get_in(retrieval, [:stats, :expanded_count]) || 0
          },
          flat_baseline: %{
            latency_us: flat_us,
            result_count: length(flat_results),
            domains_returned: Enum.uniq(flat_domains),
            unique_domain_count: flat_unique,
            precision: Float.round(flat_precision, 4),
            recall: Float.round(flat_recall, 4),
            f1: Float.round(f1(flat_precision, flat_recall), 4)
          },
          expansion_delta: %{
            precision_gain: Float.round(precision - flat_precision, 4),
            recall_gain: Float.round(recall - flat_recall, 4),
            f1_gain: Float.round(f1(precision, recall) - f1(flat_precision, flat_recall), 4),
            domain_gain: unique_domains - flat_unique
          }
        }
      end)

    # Aggregate by category
    by_category =
      query_results
      |> Enum.group_by(& &1.category)
      |> Enum.map(fn {cat, items} ->
        {cat,
         %{
           count: length(items),
           mean_precision: mean_of(items, [:graph_expanded, :precision]),
           mean_recall: mean_of(items, [:graph_expanded, :recall]),
           mean_f1: mean_of(items, [:graph_expanded, :f1]),
           mean_latency_us: mean_of(items, [:graph_expanded, :latency_us]),
           flat_mean_f1: mean_of(items, [:flat_baseline, :f1]),
           expansion_f1_gain: mean_of(items, [:expansion_delta, :f1_gain])
         }}
      end)
      |> Map.new()

    # Overall stats
    all_precisions = Enum.map(query_results, & &1.graph_expanded.precision)
    all_recalls = Enum.map(query_results, & &1.graph_expanded.recall)
    all_latencies = Enum.map(query_results, & &1.graph_expanded.latency_us)

    # Flat baseline aggregate stats
    flat_precisions = Enum.map(query_results, & &1.flat_baseline.precision)
    flat_recalls = Enum.map(query_results, & &1.flat_baseline.recall)
    flat_f1s = Enum.map(query_results, & &1.flat_baseline.f1)
    flat_latencies = Enum.map(query_results, & &1.flat_baseline.latency_us)

    results = %{
      benchmark: "OS-E001:retrieval",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      query_count: length(@query_battery),
      overall: %{
        mean_precision: Float.round(safe_mean(all_precisions), 4),
        mean_recall: Float.round(safe_mean(all_recalls), 4),
        mean_f1: Float.round(safe_mean(Enum.map(query_results, & &1.graph_expanded.f1)), 4),
        mean_latency_us: round(safe_mean(all_latencies)),
        p95_latency_us: percentile(all_latencies, 95),
        kappa_triggered_count:
          Enum.count(query_results, fn q -> q.graph_expanded.topology_max_kappa > 0 end)
      },
      flat_baseline: %{
        mean_precision: Float.round(safe_mean(flat_precisions), 4),
        mean_recall: Float.round(safe_mean(flat_recalls), 4),
        mean_f1: Float.round(safe_mean(flat_f1s), 4),
        mean_latency_us: round(safe_mean(flat_latencies))
      },
      graph_vs_flat: %{
        f1_delta:
          Float.round(
            safe_mean(Enum.map(query_results, & &1.graph_expanded.f1)) - safe_mean(flat_f1s),
            4
          ),
        precision_delta: Float.round(safe_mean(all_precisions) - safe_mean(flat_precisions), 4),
        recall_delta: Float.round(safe_mean(all_recalls) - safe_mean(flat_recalls), 4)
      },
      by_category: by_category,
      queries: query_results
    }

    path = Helpers.write_results("retrieval", results)

    Mix.shell().info("""

    === Retrieval Benchmark Complete ===
    Queries:      #{results.query_count}

    Graph-expanded retrieval:
      Precision:  #{results.overall.mean_precision}
      Recall:     #{results.overall.mean_recall}
      F1:         #{results.overall.mean_f1}
      Mean lat:   #{div(results.overall.mean_latency_us, 1000)} ms

    Flat baseline (no graph expansion):
      Precision:  #{results.flat_baseline.mean_precision}
      Recall:     #{results.flat_baseline.mean_recall}
      F1:         #{results.flat_baseline.mean_f1}
      Mean lat:   #{div(results.flat_baseline.mean_latency_us, 1000)} ms

    Graph vs Flat delta:
      F1:         #{results.graph_vs_flat.f1_delta}
      Precision:  #{results.graph_vs_flat.precision_delta}
      Recall:     #{results.graph_vs_flat.recall_delta}

    κ triggers:   #{results.overall.kappa_triggered_count}
    Output:       #{path}
    """)
  end

  defp extract_domains(results) do
    Enum.map(results, fn r ->
      # First try node metadata (scan_directory nodes have relative_path)
      node_id = Map.get(r, :node_id)
      domain = if node_id, do: domain_from_node(node_id), else: nil

      # Fall back to content-based domain detection
      domain || domain_from_content(Map.get(r, :content, "")) || "unknown"
    end)
  end

  defp domain_from_node(node_id) do
    case Graphonomous.get_node(node_id) do
      %{metadata: meta} when is_map(meta) ->
        path = Map.get(meta, "relative_path", "") |> to_string()
        path_to_domain(path)

      _ ->
        nil
    end
  end

  defp domain_from_content(content) do
    case Regex.run(~r/^\[(\w+)\]/, content) do
      [_, domain] -> domain
      _ -> nil
    end
  end

  defp path_to_domain(path) do
    cond do
      String.starts_with?(path, "graphonomous/") and
          not String.starts_with?(path, "graphonomous.com/") ->
        "graphonomous"

      String.starts_with?(path, "WebHost.Systems/") ->
        "webhost"

      String.starts_with?(path, "AmpersandBoxDesign/") ->
        "ampersand"

      String.starts_with?(path, "bendscript.com/") ->
        "bendscript"

      String.starts_with?(path, "opensentience.org/") ->
        "opensentience"

      String.starts_with?(path, "agentromatic.com/") ->
        "agentromatic"

      String.starts_with?(path, "agentelic.com/") ->
        "agentelic"

      String.starts_with?(path, "delegatic.com/") ->
        "delegatic"

      String.starts_with?(path, "deliberatic.com/") ->
        "deliberatic"

      String.starts_with?(path, "fleetprompt.com/") ->
        "fleetprompt"

      String.starts_with?(path, "geofleetic.com/") ->
        "geofleetic"

      String.starts_with?(path, "ticktickclock.com/") ->
        "ticktickclock"

      String.starts_with?(path, "specprompt.com/") ->
        "specprompt"

      String.starts_with?(path, "graphonomous.com/") ->
        "graphonomous.com"

      true ->
        nil
    end
  end

  defp domain_precision(returned_domains, expected) do
    if returned_domains == [] do
      0.0
    else
      hits = Enum.count(returned_domains, &(&1 in expected))
      hits / length(returned_domains)
    end
  end

  defp domain_recall(returned_domains, expected) do
    if expected == [] do
      1.0
    else
      unique_returned = Enum.uniq(returned_domains)
      hits = Enum.count(expected, &(&1 in unique_returned))
      hits / length(expected)
    end
  end

  defp f1(precision, recall) when precision + recall > 0 do
    2 * precision * recall / (precision + recall)
  end

  defp f1(_, _), do: 0.0

  defp mean_of(items, path) do
    values = Enum.map(items, fn item -> get_in(item, path) end)
    Float.round(safe_mean(values), 4)
  end

  defp safe_mean([]), do: 0.0
  defp safe_mean(list), do: Enum.sum(list) / length(list)

  defp percentile([], _), do: 0

  defp percentile(list, p) do
    sorted = Enum.sort(list)
    idx = max(0, round(length(sorted) * p / 100) - 1)
    Enum.at(sorted, idx, 0)
  end
end
