defmodule Mix.Tasks.Reembed do
  @moduledoc """
  Re-embeds all nodes in the knowledge graph with the currently configured embedding model.

  Use this after changing the embedding model or dimension to update all stored embeddings.
  Deletes the HNSW index file so it will be rebuilt on next startup.

  ## Usage

      mix reembed [--db PATH] [--batch-size N] [--dry-run]

  ## Options

    * `--db` — Path to the database (default: config value)
    * `--batch-size` — Number of nodes to embed per batch (default: 16)
    * `--dry-run` — Show what would be re-embedded without making changes
  """

  use Mix.Task

  require Logger

  @shortdoc "Re-embed all nodes with the current embedding model"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [db: :string, batch_size: :integer, dry_run: :boolean]
      )

    batch_size = Keyword.get(opts, :batch_size, 16)
    dry_run = Keyword.get(opts, :dry_run, false)

    # Override db_path if provided
    if db = opts[:db] do
      Application.put_env(:graphonomous, :db_path, db)
    end

    Mix.Task.run("app.start")

    # Wait for embedder warmup
    IO.puts("Waiting for embedder warmup...")
    wait_for_embedder(60_000)

    info = Graphonomous.Embedder.info()

    IO.puts(
      "Embedder: backend=#{info.backend} model=#{info.model_id} dimension=#{info.dimension}"
    )

    if info.backend == :fallback do
      IO.puts("ERROR: Embedder is in fallback mode — cannot produce real embeddings.")
      IO.puts("Check model configuration and try again.")
      System.halt(1)
    end

    # Get all nodes
    {:ok, nodes} = Graphonomous.Store.list_nodes(%{limit: 1_000_000})
    total = length(nodes)

    nodes_with_content =
      Enum.filter(nodes, fn node ->
        content = Map.get(node, :content, "")
        is_binary(content) and String.trim(content) != ""
      end)

    embeddable = length(nodes_with_content)

    IO.puts("Found #{total} nodes total, #{embeddable} with content to re-embed")

    if dry_run do
      IO.puts("[DRY RUN] Would re-embed #{embeddable} nodes. Exiting.")
      :ok
    else
      IO.puts("Re-embedding #{embeddable} nodes in batches of #{batch_size}...")

      {success, errors} =
        nodes_with_content
        |> Enum.chunk_every(batch_size)
        |> Enum.with_index(1)
        |> Enum.reduce({0, 0}, fn {chunk, batch_num}, {ok_acc, err_acc} ->
          texts = Enum.map(chunk, & &1.content)

          case Graphonomous.Embedder.embed_many_binary(texts, task: :document) do
            {:ok, binaries} ->
              Enum.zip(chunk, binaries)
              |> Enum.each(fn {node, embedding_blob} ->
                Graphonomous.Store.update_node(node.id, %{embedding: embedding_blob})
              end)

              done = ok_acc + length(chunk)

              IO.write("\r  Batch #{batch_num}: #{done}/#{embeddable} nodes re-embedded")

              {done, err_acc}

            {:error, reason} ->
              IO.puts("\n  Batch #{batch_num}: ERROR — #{inspect(reason)}")
              {ok_acc, err_acc + length(chunk)}
          end
        end)

      IO.puts("\n\nRe-embedding complete: #{success} succeeded, #{errors} failed")

      # Delete old HNSW index so it rebuilds with new dimensions on next start
      db_path = Application.get_env(:graphonomous, :db_path, "priv/graphonomous.db")
      hnsw_path = "#{db_path}.hnsw"

      if File.exists?(hnsw_path) do
        File.rm!(hnsw_path)
        IO.puts("Deleted old HNSW index: #{hnsw_path}")
      end

      IO.puts("Done. Restart the application to rebuild the HNSW index.")
    end
  end

  defp wait_for_embedder(timeout) when timeout <= 0 do
    IO.puts("Embedder warmup timed out")
  end

  defp wait_for_embedder(timeout) do
    info = Graphonomous.Embedder.info()

    if info.backend == :warming do
      Process.sleep(1_000)
      wait_for_embedder(timeout - 1_000)
    else
      IO.puts("Embedder ready: #{info.backend}")
    end
  end
end
