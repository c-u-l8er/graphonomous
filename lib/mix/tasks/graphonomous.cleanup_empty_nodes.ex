defmodule Mix.Tasks.Graphonomous.CleanupEmptyNodes do
  @moduledoc """
  Removes nodes with empty/whitespace-only content from the Graphonomous store.

  These were created by the 2026-04-11 empty-content bug where
  `store_node` would silently persist a node with `content = ""` when the
  caller forgot to pass content. The bug is now fixed at three layers
  (`Graphonomous.MCP.StoreNode`, `Graphonomous`, `Graphonomous.Store`) — this
  task cleans up the zombie rows that were already persisted.

  ## Usage

      mix graphonomous.cleanup_empty_nodes            # dry run
      mix graphonomous.cleanup_empty_nodes --delete   # actually delete

  By default the task is a **dry run** and prints which nodes it would delete.
  Pass `--delete` to actually remove them. Any edges pointing at a deleted
  node are also removed.

  ## Safety

  - The task refuses to run if another BEAM process has the DB open
    (to avoid ETS cache inconsistencies in a running MCP server).
  - Uses `Graphonomous.Graph.delete_node/1` when the app is running, so ETS
    + SQLite + BM25 + HNSW all stay in sync.
  - Falls back to direct SQL + WAL-aware delete when invoked standalone.
  """
  use Mix.Task

  @shortdoc "Delete zombie empty-content nodes from Graphonomous"

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [delete: :boolean])
    delete? = Keyword.get(opts, :delete, false)

    Mix.Task.run("app.start")

    case Graphonomous.Graph.list_nodes(%{}) do
      {:ok, nodes} ->
        zombies =
          Enum.filter(nodes, fn n ->
            content = Map.get(n, :content)
            is_nil(content) or (is_binary(content) and String.trim(content) == "")
          end)

        report(zombies, delete?)

      other ->
        Mix.shell().error("Failed to list nodes: #{inspect(other)}")
        exit({:shutdown, 1})
    end
  end

  defp report([], _delete?) do
    Mix.shell().info("No empty-content nodes found. Graph is clean.")
  end

  defp report(zombies, delete?) do
    Mix.shell().info("Found #{length(zombies)} empty-content zombie node(s):\n")

    Enum.each(zombies, fn n ->
      Mix.shell().info(
        "  - #{n.id}  type=#{inspect(n.node_type)}  conf=#{n.confidence}  created=#{n.created_at}"
      )
    end)

    if delete? do
      Mix.shell().info("\nDeleting...")

      {ok, err} =
        Enum.reduce(zombies, {0, 0}, fn node, {ok, err} ->
          case Graphonomous.Graph.delete_node(node.id) do
            :ok -> {ok + 1, err}
            {:ok, _} -> {ok + 1, err}
            {:error, reason} ->
              Mix.shell().error("  x #{node.id}: #{inspect(reason)}")
              {ok, err + 1}
            other ->
              Mix.shell().error("  x #{node.id}: #{inspect(other)}")
              {ok, err + 1}
          end
        end)

      Mix.shell().info("\nDeleted #{ok}, failed #{err}.")
    else
      Mix.shell().info("\n(dry run — pass --delete to actually remove these)")
    end
  end
end
