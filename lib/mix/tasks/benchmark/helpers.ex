defmodule Mix.Tasks.Benchmark.Helpers do
  @moduledoc """
  Shared utilities for the OS-E001 benchmark suite.

  Provides corpus loading, timing, metrics collection, and JSON output.
  """

  # Portfolio root is ProjectAmp2/ — one level above graphonomous/
  @portfolio_root Path.expand("../../../../../", __DIR__)

  @corpus_manifest [
    # Graphonomous spec
    {"graphonomous", "graphonomous/docs/spec/README.md"},
    {"graphonomous", "graphonomous/docs/spec/kappa_integration_spec.md"},
    {"graphonomous", "graphonomous/docs/spec/kappa_theory_applied.md"},
    {"graphonomous", "graphonomous/docs/spec/kappa_product_crosswalk.md"},
    # WebHost.Systems spec
    {"webhost", "WebHost.Systems/docs/spec/00_MASTER_SPEC.md"},
    {"webhost", "WebHost.Systems/docs/spec/10_API_CONTRACTS.md"},
    {"webhost", "WebHost.Systems/docs/spec/20_RUNTIME_PROVIDER_INTERFACE.md"},
    {"webhost", "WebHost.Systems/docs/spec/30_DATA_MODEL_SUPABASE.md"},
    {"webhost", "WebHost.Systems/docs/spec/40_SECURITY_SECRETS_COMPLIANCE.md"},
    {"webhost", "WebHost.Systems/docs/spec/50_OBSERVABILITY_BILLING_LIMITS.md"},
    {"webhost", "WebHost.Systems/docs/spec/60_TESTING_ACCEPTANCE.md"},
    {"webhost", "WebHost.Systems/docs/spec/70_AMPERSAND_PROTOCOL_INTEGRATION.md"},
    # AmpersandBoxDesign prompts
    {"ampersand", "AmpersandBoxDesign/prompts/PROTOCOL_PROMPT.md"},
    {"ampersand", "AmpersandBoxDesign/prompts/KAPPA_BUILD_PROMPT.md"},
    {"ampersand", "AmpersandBoxDesign/prompts/KAPPA_DELIBERATOR_PROMPT.md"},
    {"ampersand", "AmpersandBoxDesign/prompts/ATTENTION_ENGINE_PROMPT.md"},
    {"ampersand", "AmpersandBoxDesign/prompts/MODEL_TIER_PROMPT.md"},
    {"ampersand", "AmpersandBoxDesign/prompts/GRAPHONOMOUS_PROMPT.md"},
    # Portfolio product specs
    {"fleetprompt", "fleetprompt.com/docs/spec/README.md"},
    {"agentromatic", "agentromatic.com/docs/spec/README.md"},
    {"ticktickclock", "ticktickclock.com/docs/spec/README.md"},
    {"geofleetic", "geofleetic.com/docs/spec/README.md"},
    {"bendscript", "bendscript.com/docs/spec/README.md"},
    {"agentelic", "agentelic.com/docs/spec/README.md"},
    {"specprompt", "specprompt.com/docs/spec/README.md"},
    {"delegatic", "delegatic.com/docs/spec/README.md"},
    {"deliberatic", "deliberatic.com/docs/spec/README.md"},
    {"opensentience", "opensentience.org/docs/spec/README.md"},
    {"opensentience", "opensentience.org/docs/spec/OS-008-HARNESS.md"},
    # ADRs (architectural decision records)
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0001-multi-runtime.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0002-supabase-control-plane.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0003-secrets-strategy.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0004-telemetry-integrity.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0005-deployment-immutability.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0006-invocation-protocol.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0007-entitlements-and-limits.md"},
    {"webhost", "WebHost.Systems/docs/spec/adr/ADR-0008-delegated-invocation-auth.md"}
  ]

  @doc "Returns the list of {domain, relative_path} tuples for the corpus."
  def corpus_manifest, do: @corpus_manifest

  @doc "Returns the absolute portfolio root path."
  def portfolio_root, do: @portfolio_root

  @doc "Load and chunk a markdown file into sections by ## headings."
  def load_and_chunk(relative_path) do
    abs_path = Path.join(@portfolio_root, relative_path)

    case File.read(abs_path) do
      {:ok, content} ->
        chunks = chunk_markdown(content, relative_path)
        {:ok, chunks}

      {:error, reason} ->
        {:error, {relative_path, reason}}
    end
  end

  @doc "Split markdown into chunks at ## headings. Each chunk gets the heading as title."
  def chunk_markdown(content, source_path) do
    lines = String.split(content, "\n")

    {chunks, current} =
      Enum.reduce(lines, {[], %{title: Path.basename(source_path), lines: []}}, fn line,
                                                                                   {acc, cur} ->
        if String.match?(line, ~r/^##\s+/) do
          title = String.replace(line, ~r/^##\s+/, "") |> String.trim()
          acc = if cur.lines != [], do: [finalize_chunk(cur) | acc], else: acc
          {acc, %{title: title, lines: []}}
        else
          {acc, %{cur | lines: [line | cur.lines]}}
        end
      end)

    chunks = if current.lines != [], do: [finalize_chunk(current) | chunks], else: chunks

    chunks
    |> Enum.reverse()
    |> Enum.reject(fn c -> String.trim(c.content) == "" end)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      %{
        title: chunk.title,
        content: chunk.content,
        source: source_path,
        chunk_index: idx
      }
    end)
  end

  defp finalize_chunk(%{title: title, lines: lines}) do
    %{title: title, content: lines |> Enum.reverse() |> Enum.join("\n")}
  end

  @doc "Time a function in microseconds and return {duration_us, result}."
  def timed(fun) do
    :timer.tc(fun)
  end

  @doc "Write a JSON results file to the benchmark output directory."
  def write_results(name, data) do
    dir = Path.join([@portfolio_root, "graphonomous", "benchmark_results"])
    Mix.shell().info("  Writing to: #{dir}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{name}.json")
    json = Jason.encode!(data, pretty: true)
    File.write!(path, json)
    Mix.shell().info("Results written to #{path}")
    path
  end

  @doc "Purge all nodes and goals from the graph (for clean benchmarks)."
  def purge_graph do
    node_failures =
      case Graphonomous.list_nodes(%{limit: 100_000}) do
        nodes when is_list(nodes) ->
          Enum.reduce(nodes, 0, fn node, failures ->
            case safe_delete_node(node.id) do
              :ok ->
                failures

              {:error, reason} ->
                Mix.shell().info(
                  "  purge warning: failed to delete node #{node.id}: #{inspect(reason)}"
                )

                failures + 1
            end
          end)

        _ ->
          0
      end

    goal_failures =
      case Graphonomous.list_goals(%{include_abandoned: true, limit: 100_000}) do
        goals when is_list(goals) ->
          Enum.reduce(goals, 0, fn goal, failures ->
            case safe_delete_goal(goal.id) do
              :ok ->
                failures

              {:error, reason} ->
                Mix.shell().info(
                  "  purge warning: failed to delete goal #{goal.id}: #{inspect(reason)}"
                )

                failures + 1
            end
          end)

        _ ->
          0
      end

    if node_failures > 0 or goal_failures > 0 do
      Mix.shell().info(
        "  Purge completed with warnings (node failures: #{node_failures}, goal failures: #{goal_failures})"
      )
    end

    :ok
  end

  defp safe_delete_node(node_id) when is_binary(node_id) do
    try do
      case Graphonomous.delete_node(node_id) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_delete_node_result, other}}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, {:exit, reason}}
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  defp safe_delete_goal(goal_id) when is_binary(goal_id) do
    try do
      case Graphonomous.delete_goal(goal_id) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_delete_goal_result, other}}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, {:exit, reason}}
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  @doc "Ensure the Graphonomous application is started with benchmark DB."
  def ensure_started(opts \\ []) do
    neural = Application.get_env(:graphonomous, :benchmark_neural, false)
    default_backend = if neural, do: :auto, else: :fallback
    backend = Keyword.get(opts, :backend, default_backend)

    # EXLA is only required for Bumblebee. Avoid starting it for ONNX-only runs.
    # (runtime: false in mix.exs means it won't auto-start)
    if backend == :bumblebee do
      case Application.ensure_all_started(:exla) do
        {:ok, _} -> Mix.shell().info("  EXLA application started")
        {:error, reason} -> Mix.shell().info("  EXLA start failed: #{inspect(reason)}")
      end
    end

    # Stop app if running, reconfigure, then restart with benchmark settings.
    # Mix auto-starts the app with dev config; we need to restart with benchmark DB.
    Application.stop(:graphonomous)
    Application.put_env(:graphonomous, :db_path, "priv/benchmark.db")
    Application.put_env(:graphonomous, :embedder_backend, backend)
    Application.put_env(:graphonomous, :consolidator_interval_ms, 999_999_999)
    {:ok, _} = Application.ensure_all_started(:graphonomous)

    # If neural backend, wait for Bumblebee warmup to complete
    if backend != :fallback do
      wait_for_embedder_warmup()
    end

    :ok
  end

  defp wait_for_embedder_warmup do
    Mix.shell().info("  Waiting for Bumblebee model warmup...")

    Enum.reduce_while(1..120, nil, fn _i, _acc ->
      case Graphonomous.Embedder.info() do
        %{backend: :bumblebee} ->
          Mix.shell().info("  Embedder ready (Bumblebee)")
          {:halt, :ok}

        %{backend: :onnx} ->
          Mix.shell().info("  Embedder ready (ONNX)")
          {:halt, :ok}

        %{backend: :fallback} ->
          Mix.shell().info("  Embedder fell back to fallback (Bumblebee unavailable)")
          {:halt, :ok}

        _ ->
          Process.sleep(1_000)
          {:cont, nil}
      end
    end)
  end
end
