defmodule Graphonomous.BM25Index do
  @moduledoc """
  BM25 keyword index for hybrid retrieval using SQLite FTS5.

  Maintains a full-text search index alongside the main knowledge graph.
  Provides BM25-ranked keyword search that complements vector similarity search.

  The FTS5 table is kept in sync with node content via explicit upsert/delete calls
  from the Store module.
  """

  use GenServer

  require Logger

  alias Exqlite.Sqlite3

  @fts_table "nodes_fts"

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Search for nodes matching a keyword query, ranked by BM25 relevance.
  Returns `{:ok, [{node_id, bm25_score}]}` sorted by descending relevance.
  """
  @spec search(String.t(), keyword()) :: {:ok, [{String.t(), float()}]} | {:error, term()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    GenServer.call(__MODULE__, {:search, query, limit})
  end

  @doc """
  Index or update a node's content in the FTS5 index.
  """
  @spec upsert(String.t(), String.t()) :: :ok | {:error, term()}
  def upsert(node_id, content) when is_binary(node_id) and is_binary(content) do
    GenServer.cast(__MODULE__, {:upsert, node_id, content})
  end

  @doc """
  Remove a node from the FTS5 index.
  """
  @spec delete(String.t()) :: :ok
  def delete(node_id) when is_binary(node_id) do
    GenServer.cast(__MODULE__, {:delete, node_id})
  end

  @doc """
  Rebuild the entire FTS5 index from all nodes in the Store.
  """
  @spec rebuild() :: :ok | {:error, term()}
  def rebuild do
    GenServer.call(__MODULE__, :rebuild, 120_000)
  end

  @doc """
  Returns index statistics.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    db_path =
      Application.get_env(:graphonomous, :db_path, "priv/graphonomous.db") <> ".fts"

    case Sqlite3.open(db_path) do
      {:ok, conn} ->
        :ok = bootstrap_fts(conn)
        count = count_indexed(conn)
        Logger.info("BM25Index: opened #{db_path} with #{count} indexed nodes")

        # If empty and Store is running, rebuild from existing nodes
        if count == 0 do
          Process.send_after(self(), :auto_rebuild, 2_000)
        end

        {:ok, %{conn: conn, db_path: db_path}}

      {:error, reason} ->
        Logger.error("BM25Index: failed to open #{db_path}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:search, query, limit}, _from, %{conn: conn} = state) do
    result = do_search(conn, query, limit)
    {:reply, result, state}
  end

  def handle_call(:rebuild, _from, %{conn: conn} = state) do
    result = do_rebuild(conn)
    {:reply, result, state}
  end

  def handle_call(:info, _from, %{conn: conn} = state) do
    count = count_indexed(conn)
    {:reply, %{indexed_count: count, db_path: state.db_path}, state}
  end

  @impl true
  def handle_cast({:upsert, node_id, content}, %{conn: conn} = state) do
    do_upsert(conn, node_id, content)
    {:noreply, state}
  end

  def handle_cast({:delete, node_id}, %{conn: conn} = state) do
    do_delete(conn, node_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(:auto_rebuild, %{conn: conn} = state) do
    case do_rebuild(conn) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("BM25Index: auto-rebuild failed: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal

  defp bootstrap_fts(conn) do
    # FTS5 virtual table with content column and node_id as the rowid key
    # Using content="" makes it an "external content" table — we manage content ourselves
    Sqlite3.execute(conn, """
    CREATE VIRTUAL TABLE IF NOT EXISTS #{@fts_table}
    USING fts5(node_id, content, tokenize='porter unicode61');
    """)
  end

  defp do_search(conn, query, limit) do
    # Sanitize query for FTS5 — remove special chars that could break syntax
    sanitized = sanitize_fts_query(query)

    if sanitized == "" do
      {:ok, []}
    else
      sql = """
      SELECT node_id, bm25(#{@fts_table}) as score
      FROM #{@fts_table}
      WHERE #{@fts_table} MATCH ?
      ORDER BY score
      LIMIT ?;
      """

      case prepared_select(conn, sql, [sanitized, limit]) do
        {:ok, rows} ->
          results =
            Enum.map(rows, fn [node_id, score] ->
              # FTS5 bm25() returns negative values (lower = more relevant)
              # Negate to get positive scores where higher = better
              {to_string(node_id), -to_float(score)}
            end)

          {:ok, results}

        {:error, reason} ->
          Logger.warning("BM25Index search error: #{inspect(reason)}")
          {:ok, []}
      end
    end
  end

  defp do_upsert(conn, node_id, content) do
    # Delete existing entry first (FTS5 doesn't have native upsert)
    do_delete(conn, node_id)

    sql = "INSERT INTO #{@fts_table}(node_id, content) VALUES (?, ?);"

    case prepared_execute(conn, sql, [node_id, content]) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("BM25Index upsert error: #{inspect(reason)}")
    end
  end

  defp do_delete(conn, node_id) do
    sql = "DELETE FROM #{@fts_table} WHERE node_id = ?;"

    case prepared_execute(conn, sql, [node_id]) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("BM25Index delete error: #{inspect(reason)}")
    end
  end

  defp do_rebuild(conn) do
    case Graphonomous.Store.list_nodes(%{limit: 1_000_000}) do
      {:ok, nodes} ->
        # Clear existing index
        Sqlite3.execute(conn, "DELETE FROM #{@fts_table};")

        # Bulk insert
        nodes_with_content =
          Enum.filter(nodes, fn n ->
            content = Map.get(n, :content, "")
            is_binary(content) and String.trim(content) != ""
          end)

        Enum.each(nodes_with_content, fn node ->
          do_upsert(conn, node.id, node.content)
        end)

        Logger.info("BM25Index: rebuilt with #{length(nodes_with_content)} nodes")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:rebuild_exception, Exception.message(e)}}
  end

  defp count_indexed(conn) do
    case prepared_select(conn, "SELECT count(*) FROM #{@fts_table};", []) do
      {:ok, [[count]]} -> count
      _ -> 0
    end
  end

  defp sanitize_fts_query(query) do
    # Convert natural language query to FTS5 compatible format
    # Remove FTS5 operators and special characters, keep alphanumeric + spaces
    query
    |> String.replace(~r/[^\w\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in ~w(AND OR NOT NEAR)))
    |> Enum.join(" ")
  end

  ## SQLite helpers

  defp prepared_select(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, params),
         {:ok, rows} <- collect_rows(conn, stmt) do
      Sqlite3.release(conn, stmt)
      {:ok, rows}
    end
  end

  defp prepared_execute(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, params) do
      result = Sqlite3.step(conn, stmt)
      Sqlite3.release(conn, stmt)

      case result do
        :done -> :ok
        {:row, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp collect_rows(conn, stmt, acc \\ []) do
    case Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, [row | acc])
      :done -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(_), do: 0.0
end
