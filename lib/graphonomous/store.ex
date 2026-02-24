defmodule Graphonomous.Store do
  @moduledoc """
  Storage runtime for Graphonomous.

  Responsibilities:
  - own the SQLite connection
  - bootstrap schema on startup
  - provide node / edge / outcome operations
  - keep a hot ETS cache for fast reads in v0.1

  Notes:
  - Writes are persisted to SQLite and mirrored into ETS.
  - Reads are served from ETS (fast path).
  """

  use GenServer

  alias Exqlite.Sqlite3
  alias Graphonomous.Types.{Edge, Goal, Node, Outcome}

  @nodes_table :graphonomous_nodes
  @edges_table :graphonomous_edges
  @outcomes_table :graphonomous_outcomes
  @goals_table :graphonomous_goals

  @type state :: %{
          conn: reference() | nil,
          db_path: binary(),
          vec_extension_path: binary() | nil
        }

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ping, do: GenServer.call(__MODULE__, :ping)

  def insert_node(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:insert_node, attrs})

  def get_node(node_id) when is_binary(node_id),
    do: GenServer.call(__MODULE__, {:get_node, node_id})

  def list_nodes(filters \\ %{}) when is_map(filters),
    do: GenServer.call(__MODULE__, {:list_nodes, filters})

  def update_node(node_id, attrs) when is_binary(node_id) and is_map(attrs),
    do: GenServer.call(__MODULE__, {:update_node, node_id, attrs})

  def delete_node(node_id) when is_binary(node_id),
    do: GenServer.call(__MODULE__, {:delete_node, node_id})

  def increment_access(node_id) when is_binary(node_id),
    do: GenServer.call(__MODULE__, {:increment_access, node_id})

  def upsert_edge(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:upsert_edge, attrs})

  def list_edges_for_node(node_id) when is_binary(node_id),
    do: GenServer.call(__MODULE__, {:list_edges_for_node, node_id})

  def insert_outcome(attrs) when is_map(attrs),
    do: GenServer.call(__MODULE__, {:insert_outcome, attrs})

  def list_outcomes(limit \\ 100) when is_integer(limit) and limit > 0,
    do: GenServer.call(__MODULE__, {:list_outcomes, limit})

  def insert_goal(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:insert_goal, attrs})

  def get_goal(goal_id) when is_binary(goal_id),
    do: GenServer.call(__MODULE__, {:get_goal, goal_id})

  def list_goals(filters \\ %{}) when is_map(filters),
    do: GenServer.call(__MODULE__, {:list_goals, filters})

  def update_goal(goal_id, attrs) when is_binary(goal_id) and is_map(attrs),
    do: GenServer.call(__MODULE__, {:update_goal, goal_id, attrs})

  def delete_goal(goal_id) when is_binary(goal_id),
    do: GenServer.call(__MODULE__, {:delete_goal, goal_id})

  def rebuild_cache, do: GenServer.call(__MODULE__, :rebuild_cache)

  ## GenServer

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, "priv/graphonomous.db")

    vec_extension_path =
      Keyword.get(
        opts,
        :vec_extension_path,
        Application.get_env(:graphonomous, :sqlite_vec_extension_path)
      )

    :ok = ensure_parent_dir(db_path)
    :ok = ensure_cache_tables()

    state = %{
      conn: nil,
      db_path: db_path,
      vec_extension_path: vec_extension_path
    }

    case Sqlite3.open(db_path) do
      {:ok, conn} ->
        with :ok <- bootstrap_schema(conn),
             :ok <- run_migrations(conn),
             :ok <- maybe_load_vec_extension(conn, vec_extension_path),
             :ok <- warm_cache_from_db(conn) do
          {:ok, %{state | conn: conn}}
        else
          {:error, reason} -> {:stop, {:bootstrap_failed, reason}}
        end

      {:error, reason} ->
        {:stop, {:sqlite_open_failed, reason}}
    end
  end

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :pong, state}

  def handle_call(:rebuild_cache, _from, state) do
    reply =
      case warm_cache_from_db(state.conn) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end

    {:reply, reply, state}
  end

  def handle_call({:insert_node, attrs}, _from, state) do
    node = build_node(attrs)

    with :ok <- persist_node(state.conn, node) do
      true = :ets.insert(@nodes_table, {node.id, node})
      {:reply, {:ok, node}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_node, node_id}, _from, state) do
    reply =
      case :ets.lookup(@nodes_table, node_id) do
        [{^node_id, node}] -> {:ok, node}
        _ -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:list_nodes, filters}, _from, state) do
    nodes =
      @nodes_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, node} -> node end)
      |> filter_nodes(filters)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> apply_limit(filters)

    {:reply, {:ok, nodes}, state}
  end

  def handle_call({:update_node, node_id, attrs}, _from, state) do
    case :ets.lookup(@nodes_table, node_id) do
      [{^node_id, existing}] ->
        updated = merge_node(existing, attrs)

        with :ok <- persist_node(state.conn, updated) do
          true = :ets.insert(@nodes_table, {updated.id, updated})
          {:reply, {:ok, updated}, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:delete_node, node_id}, _from, state) do
    :ets.delete(@nodes_table, node_id)

    case execute_prepared(state.conn, "DELETE FROM nodes WHERE id = ?;", [node_id]) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:increment_access, node_id}, _from, state) do
    case :ets.lookup(@nodes_table, node_id) do
      [{^node_id, %Node{} = node}] ->
        now = DateTime.utc_now()

        updated = %Node{
          node
          | access_count: node.access_count + 1,
            last_accessed_at: now,
            updated_at: now
        }

        with :ok <- persist_node(state.conn, updated) do
          true = :ets.insert(@nodes_table, {updated.id, updated})
          {:reply, {:ok, updated}, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:upsert_edge, attrs}, _from, state) do
    edge = build_edge(attrs)

    with :ok <- persist_edge(state.conn, edge) do
      true = :ets.insert(@edges_table, {edge.id, edge})
      {:reply, {:ok, edge}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list_edges_for_node, node_id}, _from, state) do
    edges =
      @edges_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, edge} -> edge end)
      |> Enum.filter(&(&1.source_id == node_id or &1.target_id == node_id))

    {:reply, {:ok, edges}, state}
  end

  def handle_call({:insert_outcome, attrs}, _from, state) do
    outcome = build_outcome(attrs)

    with :ok <- persist_outcome(state.conn, outcome) do
      true =
        :ets.insert(
          @outcomes_table,
          {outcome.action_id <> "::" <> iso8601(outcome.observed_at), outcome}
        )

      {:reply, {:ok, outcome}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list_outcomes, limit}, _from, state) do
    outcomes =
      @outcomes_table
      |> :ets.tab2list()
      |> Enum.map(fn {_k, outcome} -> outcome end)
      |> Enum.sort_by(& &1.observed_at, {:desc, DateTime})
      |> Enum.take(limit)

    {:reply, {:ok, outcomes}, state}
  end

  def handle_call({:insert_goal, attrs}, _from, state) do
    now = DateTime.utc_now()

    goal = %Goal{
      id: map_get(attrs, :id, id("goal")),
      title: map_get(attrs, :title, ""),
      description: map_get(attrs, :description, nil),
      status: normalize_goal_status(map_get(attrs, :status, :proposed)),
      timescale: normalize_goal_timescale(map_get(attrs, :timescale, :short_term)),
      source_type: normalize_goal_source_type(map_get(attrs, :source_type, :user)),
      priority: normalize_goal_priority(map_get(attrs, :priority, :normal)),
      confidence: normalize_probability(map_get(attrs, :confidence, 0.5)),
      progress: normalize_probability(map_get(attrs, :progress, 0.0)),
      owner: map_get(attrs, :owner, nil),
      tags: normalize_string_list(map_get(attrs, :tags, [])),
      constraints: normalize_map(map_get(attrs, :constraints, %{})),
      success_criteria: normalize_map(map_get(attrs, :success_criteria, %{})),
      metadata: normalize_map(map_get(attrs, :metadata, %{})),
      linked_node_ids: normalize_string_list(map_get(attrs, :linked_node_ids, [])),
      parent_goal_id: map_get(attrs, :parent_goal_id, nil),
      created_at: map_get(attrs, :created_at, now) |> normalize_datetime(now),
      updated_at: map_get(attrs, :updated_at, now) |> normalize_datetime(now),
      due_at: map_get(attrs, :due_at, nil) |> normalize_datetime(nil),
      completed_at: map_get(attrs, :completed_at, nil) |> normalize_datetime(nil),
      last_reviewed_at: map_get(attrs, :last_reviewed_at, nil) |> normalize_datetime(nil)
    }

    with :ok <- persist_goal(state.conn, goal) do
      true = :ets.insert(@goals_table, {goal.id, goal})
      {:reply, {:ok, goal}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_goal, goal_id}, _from, state) do
    reply =
      case :ets.lookup(@goals_table, goal_id) do
        [{^goal_id, goal}] -> {:ok, goal}
        _ -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:list_goals, filters}, _from, state) do
    goals =
      @goals_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, goal} -> goal end)
      |> filter_goals(filters)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> apply_goal_limit(filters)

    {:reply, {:ok, goals}, state}
  end

  def handle_call({:update_goal, goal_id, attrs}, _from, state) do
    case :ets.lookup(@goals_table, goal_id) do
      [{^goal_id, %Goal{} = existing}] ->
        now = DateTime.utc_now()

        updated = %Goal{
          existing
          | title: map_get(attrs, :title, existing.title),
            description: map_get(attrs, :description, existing.description),
            status: normalize_goal_status(map_get(attrs, :status, existing.status)),
            timescale: normalize_goal_timescale(map_get(attrs, :timescale, existing.timescale)),
            source_type:
              normalize_goal_source_type(map_get(attrs, :source_type, existing.source_type)),
            priority: normalize_goal_priority(map_get(attrs, :priority, existing.priority)),
            confidence: normalize_probability(map_get(attrs, :confidence, existing.confidence)),
            progress: normalize_probability(map_get(attrs, :progress, existing.progress)),
            owner: map_get(attrs, :owner, existing.owner),
            tags: normalize_string_list(map_get(attrs, :tags, existing.tags)),
            constraints: normalize_map(map_get(attrs, :constraints, existing.constraints)),
            success_criteria:
              normalize_map(map_get(attrs, :success_criteria, existing.success_criteria)),
            metadata: normalize_map(map_get(attrs, :metadata, existing.metadata)),
            linked_node_ids:
              normalize_string_list(map_get(attrs, :linked_node_ids, existing.linked_node_ids)),
            parent_goal_id: map_get(attrs, :parent_goal_id, existing.parent_goal_id),
            updated_at: now,
            due_at:
              map_get(attrs, :due_at, existing.due_at) |> normalize_datetime(existing.due_at),
            completed_at:
              map_get(attrs, :completed_at, existing.completed_at)
              |> normalize_datetime(existing.completed_at),
            last_reviewed_at:
              map_get(attrs, :last_reviewed_at, existing.last_reviewed_at)
              |> normalize_datetime(existing.last_reviewed_at)
        }

        with :ok <- persist_goal(state.conn, updated) do
          true = :ets.insert(@goals_table, {updated.id, updated})
          {:reply, {:ok, updated}, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:delete_goal, goal_id}, _from, state) do
    :ets.delete(@goals_table, goal_id)

    case execute_prepared(state.conn, "DELETE FROM goals WHERE id = ?;", [goal_id]) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, %{conn: nil}), do: :ok

  def terminate(_reason, %{conn: conn}) do
    _ = Sqlite3.close(conn)
    :ok
  end

  ## Cache warm/rebuild

  defp warm_cache_from_db(conn) do
    clear_cache_tables()

    with {:ok, node_rows} <-
           select_all(conn, """
           SELECT id, content, node_type, confidence, embedding, metadata, source, access_count, created_at, updated_at, last_accessed_at
           FROM nodes;
           """),
         {:ok, edge_rows} <-
           select_all(conn, """
           SELECT id, source_id, target_id, edge_type, weight, metadata, created_at, last_activated_at
           FROM edges;
           """),
         {:ok, outcome_rows} <-
           select_all(conn, """
           SELECT id, action_id, status, confidence, causal_node_ids, evidence, retrieval_trace_id, decision_trace_id, action_linkage, grounding, observed_at
           FROM outcomes;
           """),
         {:ok, goal_rows} <-
           select_all(conn, """
           SELECT id, title, description, status, timescale, source_type, priority, confidence, progress, owner, tags, constraints, success_criteria, metadata, linked_node_ids, parent_goal_id, created_at, updated_at, due_at, completed_at, last_reviewed_at
           FROM goals;
           """) do
      Enum.each(node_rows, &cache_node_row/1)
      Enum.each(edge_rows, &cache_edge_row/1)
      Enum.each(outcome_rows, &cache_outcome_row/1)
      Enum.each(goal_rows, &cache_goal_row/1)
      :ok
    end
  end

  defp clear_cache_tables do
    :ets.delete_all_objects(@nodes_table)
    :ets.delete_all_objects(@edges_table)
    :ets.delete_all_objects(@outcomes_table)
    :ets.delete_all_objects(@goals_table)
  end

  defp cache_node_row([
         id,
         content,
         node_type,
         confidence,
         embedding,
         metadata,
         source,
         access_count,
         created_at,
         updated_at,
         last_accessed_at
       ]) do
    now = DateTime.utc_now()

    node = %Node{
      id: id,
      content: to_string(content || ""),
      node_type: normalize_node_type(node_type),
      confidence: normalize_probability(confidence),
      embedding: normalize_db_embedding(embedding),
      metadata: normalize_db_json_map(metadata),
      source: source,
      access_count: normalize_integer(access_count, 0),
      created_at: normalize_datetime(created_at, now),
      updated_at: normalize_datetime(updated_at, now),
      last_accessed_at: normalize_datetime(last_accessed_at, now)
    }

    true = :ets.insert(@nodes_table, {node.id, node})
  end

  defp cache_edge_row([
         id,
         source_id,
         target_id,
         edge_type,
         weight,
         metadata,
         created_at,
         last_activated_at
       ]) do
    now = DateTime.utc_now()

    edge = %Edge{
      id: id,
      source_id: source_id,
      target_id: target_id,
      edge_type: normalize_edge_type(edge_type),
      weight: normalize_probability(weight),
      metadata: normalize_db_json_map(metadata),
      created_at: normalize_datetime(created_at, now),
      last_activated_at: normalize_datetime(last_activated_at, now)
    }

    true = :ets.insert(@edges_table, {edge.id, edge})
  end

  defp cache_outcome_row([
         row_id,
         action_id,
         status,
         confidence,
         causal_node_ids,
         evidence,
         retrieval_trace_id,
         decision_trace_id,
         action_linkage,
         grounding,
         observed_at
       ]) do
    now = DateTime.utc_now()

    outcome = %Outcome{
      action_id: to_string(action_id || ""),
      status: normalize_status(status),
      confidence: normalize_probability(confidence),
      causal_node_ids: normalize_db_json_list(causal_node_ids),
      evidence: normalize_db_json_map(evidence),
      retrieval_trace_id: retrieval_trace_id,
      decision_trace_id: decision_trace_id,
      action_linkage: normalize_db_json_map(action_linkage),
      grounding: normalize_db_json_map(grounding),
      observed_at: normalize_datetime(observed_at, now)
    }

    true = :ets.insert(@outcomes_table, {to_string(row_id || id("outcome")), outcome})
  end

  defp cache_goal_row([
         id,
         title,
         description,
         status,
         timescale,
         source_type,
         priority,
         confidence,
         progress,
         owner,
         tags,
         constraints,
         success_criteria,
         metadata,
         linked_node_ids,
         parent_goal_id,
         created_at,
         updated_at,
         due_at,
         completed_at,
         last_reviewed_at
       ]) do
    now = DateTime.utc_now()

    goal = %Goal{
      id: id,
      title: to_string(title || ""),
      description: description,
      status: normalize_goal_status(status),
      timescale: normalize_goal_timescale(timescale),
      source_type: normalize_goal_source_type(source_type),
      priority: normalize_goal_priority(priority),
      confidence: normalize_probability(confidence),
      progress: normalize_probability(progress),
      owner: owner,
      tags: normalize_db_json_list(tags),
      constraints: normalize_db_json_map(constraints),
      success_criteria: normalize_db_json_map(success_criteria),
      metadata: normalize_db_json_map(metadata),
      linked_node_ids: normalize_db_json_list(linked_node_ids),
      parent_goal_id: parent_goal_id,
      created_at: normalize_datetime(created_at, now),
      updated_at: normalize_datetime(updated_at, now),
      due_at: normalize_datetime(due_at, nil),
      completed_at: normalize_datetime(completed_at, nil),
      last_reviewed_at: normalize_datetime(last_reviewed_at, nil)
    }

    true = :ets.insert(@goals_table, {goal.id, goal})
  end

  defp select_all(conn, sql) when is_binary(sql) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         {:ok, rows} <- Sqlite3.fetch_all(conn, stmt) do
      _ = Sqlite3.release(conn, stmt)
      {:ok, rows}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_prepared(conn, sql, params) when is_binary(sql) and is_list(params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, params),
         {:ok, _rows} <- Sqlite3.fetch_all(conn, stmt) do
      _ = Sqlite3.release(conn, stmt)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  ## Schema bootstrap

  defp bootstrap_schema(conn) do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS nodes (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        node_type TEXT NOT NULL DEFAULT 'semantic',
        confidence REAL NOT NULL DEFAULT 0.5,
        embedding BLOB,
        metadata TEXT DEFAULT '{}',
        source TEXT,
        access_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_accessed_at TEXT NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS edges (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL REFERENCES nodes(id),
        target_id TEXT NOT NULL REFERENCES nodes(id),
        edge_type TEXT NOT NULL DEFAULT 'related',
        weight REAL NOT NULL DEFAULT 0.5,
        metadata TEXT DEFAULT '{}',
        created_at TEXT NOT NULL,
        last_activated_at TEXT NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS outcomes (
        id TEXT PRIMARY KEY,
        action_id TEXT NOT NULL,
        status TEXT NOT NULL,
        confidence REAL NOT NULL,
        causal_node_ids TEXT NOT NULL,
        evidence TEXT DEFAULT '{}',
        retrieval_trace_id TEXT,
        decision_trace_id TEXT,
        action_linkage TEXT DEFAULT '{}',
        grounding TEXT DEFAULT '{}',
        observed_at TEXT NOT NULL,
        processed_at TEXT
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS goals (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'proposed',
        timescale TEXT NOT NULL DEFAULT 'short_term',
        source_type TEXT NOT NULL DEFAULT 'user',
        priority TEXT NOT NULL DEFAULT 'normal',
        confidence REAL NOT NULL DEFAULT 0.5,
        progress REAL NOT NULL DEFAULT 0.0,
        owner TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        constraints TEXT NOT NULL DEFAULT '{}',
        success_criteria TEXT NOT NULL DEFAULT '{}',
        metadata TEXT NOT NULL DEFAULT '{}',
        linked_node_ids TEXT NOT NULL DEFAULT '[]',
        parent_goal_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        due_at TEXT,
        completed_at TEXT,
        last_reviewed_at TEXT
      );
      """,
      "CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(node_type);",
      "CREATE INDEX IF NOT EXISTS idx_nodes_confidence ON nodes(confidence);",
      "CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);",
      "CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);",
      "CREATE INDEX IF NOT EXISTS idx_outcomes_causal ON outcomes(causal_node_ids);",
      "CREATE INDEX IF NOT EXISTS idx_goals_status ON goals(status);",
      "CREATE INDEX IF NOT EXISTS idx_goals_priority ON goals(priority);",
      "CREATE INDEX IF NOT EXISTS idx_goals_due_at ON goals(due_at);",
      "CREATE INDEX IF NOT EXISTS idx_goals_parent ON goals(parent_goal_id);"
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case Sqlite3.execute(conn, sql) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_migrations(conn) do
    with :ok <- ensure_schema_migrations_table(conn),
         {:ok, applied_ids} <- list_applied_migrations(conn),
         :ok <- apply_pending_migrations(conn, applied_ids, migrations()) do
      :ok
    end
  end

  defp ensure_schema_migrations_table(conn) do
    Sqlite3.execute(
      conn,
      """
      CREATE TABLE IF NOT EXISTS schema_migrations (
        id TEXT PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
      """
    )
  end

  defp list_applied_migrations(conn) do
    with {:ok, rows} <- select_all(conn, "SELECT id FROM schema_migrations;") do
      ids =
        rows
        |> Enum.map(fn [id] -> to_string(id) end)
        |> MapSet.new()

      {:ok, ids}
    end
  end

  defp migrations do
    [
      {"2026_02_24_outcomes_grounding_columns",
       [
         "ALTER TABLE outcomes ADD COLUMN retrieval_trace_id TEXT;",
         "ALTER TABLE outcomes ADD COLUMN decision_trace_id TEXT;",
         "ALTER TABLE outcomes ADD COLUMN action_linkage TEXT DEFAULT '{}';",
         "ALTER TABLE outcomes ADD COLUMN grounding TEXT DEFAULT '{}';"
       ]}
    ]
  end

  defp apply_pending_migrations(conn, applied_ids, migration_specs) do
    Enum.reduce_while(migration_specs, :ok, fn {migration_id, statements}, :ok ->
      if MapSet.member?(applied_ids, migration_id) do
        {:cont, :ok}
      else
        case run_migration_statements(conn, statements) do
          :ok ->
            case mark_migration_applied(conn, migration_id) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)
  end

  defp run_migration_statements(conn, statements) when is_list(statements) do
    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case Sqlite3.execute(conn, sql) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          if ignorable_migration_error?(reason) do
            {:cont, :ok}
          else
            {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp mark_migration_applied(conn, migration_id) do
    execute_prepared(
      conn,
      """
      INSERT OR REPLACE INTO schema_migrations (id, applied_at)
      VALUES (?, ?);
      """,
      [migration_id, DateTime.utc_now() |> DateTime.to_iso8601()]
    )
  end

  defp ignorable_migration_error?(reason) do
    normalized = reason |> to_string() |> String.downcase()

    String.contains?(normalized, "duplicate column name") or
      String.contains?(normalized, "already exists")
  end

  defp maybe_load_vec_extension(_conn, nil), do: :ok

  defp maybe_load_vec_extension(conn, path) when is_binary(path) do
    sql = "SELECT load_extension('#{sql_escape(path)}');"

    case Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  ## Persistence helpers

  defp persist_node(conn, %Node{} = node) do
    embedding =
      case node.embedding do
        nil -> nil
        value when is_binary(value) -> Base.encode64(value)
      end

    execute_prepared(
      conn,
      """
      INSERT OR REPLACE INTO nodes
      (id, content, node_type, confidence, embedding, metadata, source, access_count, created_at, updated_at, last_accessed_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """,
      [
        node.id,
        node.content || "",
        to_string(node.node_type),
        normalize_probability(node.confidence),
        embedding,
        json_encode(node.metadata),
        node.source,
        normalize_integer(node.access_count, 0),
        iso8601(node.created_at),
        iso8601(node.updated_at),
        iso8601(node.last_accessed_at)
      ]
    )
  end

  defp persist_edge(conn, %Edge{} = edge) do
    execute_prepared(
      conn,
      """
      INSERT OR REPLACE INTO edges
      (id, source_id, target_id, edge_type, weight, metadata, created_at, last_activated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?);
      """,
      [
        edge.id,
        edge.source_id,
        edge.target_id,
        to_string(edge.edge_type),
        normalize_probability(edge.weight),
        json_encode(edge.metadata),
        iso8601(edge.created_at),
        iso8601(edge.last_activated_at)
      ]
    )
  end

  defp persist_outcome(conn, %Outcome{} = outcome) do
    row_id = id("outcome")

    execute_prepared(
      conn,
      """
      INSERT INTO outcomes
      (id, action_id, status, confidence, causal_node_ids, evidence, retrieval_trace_id, decision_trace_id, action_linkage, grounding, observed_at, processed_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """,
      [
        row_id,
        outcome.action_id,
        to_string(outcome.status),
        normalize_probability(outcome.confidence),
        json_encode(outcome.causal_node_ids),
        json_encode(outcome.evidence),
        outcome.retrieval_trace_id,
        outcome.decision_trace_id,
        json_encode(outcome.action_linkage),
        json_encode(outcome.grounding),
        iso8601(outcome.observed_at),
        nil
      ]
    )
  end

  defp persist_goal(conn, %Goal{} = goal) do
    execute_prepared(
      conn,
      """
      INSERT OR REPLACE INTO goals
      (id, title, description, status, timescale, source_type, priority, confidence, progress, owner, tags, constraints, success_criteria, metadata, linked_node_ids, parent_goal_id, created_at, updated_at, due_at, completed_at, last_reviewed_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """,
      [
        goal.id,
        goal.title || "",
        goal.description,
        to_string(goal.status),
        to_string(goal.timescale),
        to_string(goal.source_type),
        to_string(goal.priority),
        normalize_probability(goal.confidence),
        normalize_probability(goal.progress),
        goal.owner,
        json_encode(goal.tags),
        json_encode(goal.constraints),
        json_encode(goal.success_criteria),
        json_encode(goal.metadata),
        json_encode(goal.linked_node_ids),
        goal.parent_goal_id,
        iso8601(goal.created_at),
        iso8601(goal.updated_at),
        nullable_iso8601(goal.due_at),
        nullable_iso8601(goal.completed_at),
        nullable_iso8601(goal.last_reviewed_at)
      ]
    )
  end

  ## Builders

  defp build_node(attrs) do
    now = DateTime.utc_now()

    %Node{
      id: map_get(attrs, :id, id("node")),
      content: map_get(attrs, :content, ""),
      node_type: normalize_node_type(map_get(attrs, :node_type, :semantic)),
      confidence: normalize_probability(map_get(attrs, :confidence, 0.5)),
      embedding: normalize_embedding(map_get(attrs, :embedding, nil)),
      metadata: normalize_map(map_get(attrs, :metadata, %{})),
      source: map_get(attrs, :source, nil),
      access_count: normalize_integer(map_get(attrs, :access_count, 0), 0),
      created_at: map_get(attrs, :created_at, now) |> normalize_datetime(now),
      updated_at: map_get(attrs, :updated_at, now) |> normalize_datetime(now),
      last_accessed_at: map_get(attrs, :last_accessed_at, now) |> normalize_datetime(now)
    }
  end

  defp merge_node(%Node{} = node, attrs) do
    now = DateTime.utc_now()

    %Node{
      node
      | content: map_get(attrs, :content, node.content),
        node_type: normalize_node_type(map_get(attrs, :node_type, node.node_type)),
        confidence: normalize_probability(map_get(attrs, :confidence, node.confidence)),
        embedding: normalize_embedding(map_get(attrs, :embedding, node.embedding)),
        metadata: normalize_map(map_get(attrs, :metadata, node.metadata)),
        source: map_get(attrs, :source, node.source),
        access_count:
          normalize_integer(map_get(attrs, :access_count, node.access_count), node.access_count),
        updated_at: now
    }
  end

  defp build_edge(attrs) do
    now = DateTime.utc_now()

    %Edge{
      id: map_get(attrs, :id, id("edge")),
      source_id: map_get(attrs, :source_id),
      target_id: map_get(attrs, :target_id),
      edge_type: normalize_edge_type(map_get(attrs, :edge_type, :related)),
      weight: normalize_probability(map_get(attrs, :weight, 0.5)),
      metadata: normalize_map(map_get(attrs, :metadata, %{})),
      created_at: map_get(attrs, :created_at, now) |> normalize_datetime(now),
      last_activated_at: map_get(attrs, :last_activated_at, now) |> normalize_datetime(now)
    }
  end

  defp build_outcome(attrs) do
    now = DateTime.utc_now()

    causal_ids =
      case map_get(attrs, :causal_node_ids, []) do
        list when is_list(list) -> Enum.filter(list, &is_binary/1)
        _ -> []
      end

    %Outcome{
      action_id: map_get(attrs, :action_id, id("action")),
      status: normalize_status(map_get(attrs, :status, :failure)),
      confidence: normalize_probability(map_get(attrs, :confidence, 0.5)),
      causal_node_ids: causal_ids,
      evidence: normalize_map(map_get(attrs, :evidence, %{})),
      retrieval_trace_id: map_get(attrs, :retrieval_trace_id, nil),
      decision_trace_id: map_get(attrs, :decision_trace_id, nil),
      action_linkage: normalize_map(map_get(attrs, :action_linkage, %{})),
      grounding: normalize_map(map_get(attrs, :grounding, %{})),
      observed_at: map_get(attrs, :observed_at, now) |> normalize_datetime(now)
    }
  end

  ## Filters

  defp filter_nodes(nodes, filters) do
    Enum.filter(nodes, fn node ->
      type_ok? =
        case map_get(filters, :node_type, nil) do
          nil -> true
          t -> node.node_type == normalize_node_type(t)
        end

      confidence_ok? =
        case map_get(filters, :min_confidence, nil) do
          nil -> true
          min_c -> node.confidence >= normalize_probability(min_c)
        end

      type_ok? and confidence_ok?
    end)
  end

  defp apply_limit(nodes, filters) do
    case map_get(filters, :limit, nil) do
      nil -> nodes
      limit when is_integer(limit) and limit > 0 -> Enum.take(nodes, limit)
      _ -> nodes
    end
  end

  defp filter_goals(goals, filters) do
    status_filter = map_get(filters, :status, nil) |> normalize_goal_status_optional()
    priority_filter = map_get(filters, :priority, nil) |> normalize_goal_priority_optional()
    owner_filter = map_get(filters, :owner, nil)
    tag_filter = map_get(filters, :tag, nil)
    min_progress = map_get(filters, :min_progress, nil)

    Enum.filter(goals, fn goal ->
      status_ok? = if is_nil(status_filter), do: true, else: goal.status == status_filter
      priority_ok? = if is_nil(priority_filter), do: true, else: goal.priority == priority_filter
      owner_ok? = if is_nil(owner_filter), do: true, else: goal.owner == owner_filter
      tag_ok? = if is_nil(tag_filter), do: true, else: tag_filter in goal.tags

      progress_ok? =
        case min_progress do
          nil -> true
          value -> goal.progress >= normalize_probability(value)
        end

      status_ok? and priority_ok? and owner_ok? and tag_ok? and progress_ok?
    end)
  end

  defp apply_goal_limit(goals, filters) do
    case map_get(filters, :limit, nil) do
      nil -> goals
      limit when is_integer(limit) and limit > 0 -> Enum.take(goals, limit)
      _ -> goals
    end
  end

  ## Utils

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp ensure_cache_tables do
    ensure_table(@nodes_table)
    ensure_table(@edges_table)
    ensure_table(@outcomes_table)
    ensure_table(@goals_table)
    :ok
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [
          :set,
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        :ok
    end
  end

  defp normalize_node_type(type) when type in [:episodic, :semantic, :procedural], do: type

  defp normalize_node_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "episodic" -> :episodic
      "procedural" -> :procedural
      _ -> :semantic
    end
  end

  defp normalize_node_type(_), do: :semantic

  defp normalize_edge_type(type)
       when type in [:causal, :related, :contradicts, :supports, :derived_from], do: type

  defp normalize_edge_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "causal" -> :causal
      "contradicts" -> :contradicts
      "supports" -> :supports
      "derived_from" -> :derived_from
      _ -> :related
    end
  end

  defp normalize_edge_type(_), do: :related

  defp normalize_status(status) when status in [:success, :partial_success, :failure, :timeout],
    do: status

  defp normalize_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "success" -> :success
      "partial_success" -> :partial_success
      "timeout" -> :timeout
      _ -> :failure
    end
  end

  defp normalize_status(_), do: :failure

  defp normalize_goal_status(status)
       when status in [:proposed, :active, :blocked, :completed, :abandoned],
       do: status

  defp normalize_goal_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "active" -> :active
      "blocked" -> :blocked
      "completed" -> :completed
      "abandoned" -> :abandoned
      _ -> :proposed
    end
  end

  defp normalize_goal_status(_), do: :proposed

  defp normalize_goal_status_optional(nil), do: nil
  defp normalize_goal_status_optional(value), do: normalize_goal_status(value)

  defp normalize_goal_timescale(timescale)
       when timescale in [:immediate, :short_term, :medium_term, :long_term],
       do: timescale

  defp normalize_goal_timescale(timescale) when is_binary(timescale) do
    case String.downcase(String.trim(timescale)) do
      "immediate" -> :immediate
      "medium_term" -> :medium_term
      "long_term" -> :long_term
      _ -> :short_term
    end
  end

  defp normalize_goal_timescale(_), do: :short_term

  defp normalize_goal_source_type(source_type)
       when source_type in [:user, :system, :inferred, :policy], do: source_type

  defp normalize_goal_source_type(source_type) when is_binary(source_type) do
    case String.downcase(String.trim(source_type)) do
      "system" -> :system
      "inferred" -> :inferred
      "policy" -> :policy
      _ -> :user
    end
  end

  defp normalize_goal_source_type(_), do: :user

  defp normalize_goal_priority(priority) when priority in [:low, :normal, :high, :critical],
    do: priority

  defp normalize_goal_priority(priority) when is_binary(priority) do
    case String.downcase(String.trim(priority)) do
      "low" -> :low
      "high" -> :high
      "critical" -> :critical
      _ -> :normal
    end
  end

  defp normalize_goal_priority(_), do: :normal

  defp normalize_goal_priority_optional(nil), do: nil
  defp normalize_goal_priority_optional(value), do: normalize_goal_priority(value)

  defp normalize_probability(v) when is_integer(v), do: normalize_probability(v * 1.0)

  defp normalize_probability(v) when is_float(v) do
    v
    |> max(0.0)
    |> min(1.0)
  end

  defp normalize_probability(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> normalize_probability(f)
      :error -> 0.5
    end
  end

  defp normalize_probability(_), do: 0.5

  defp normalize_integer(v, _default) when is_integer(v), do: v
  defp normalize_integer(_v, default), do: default

  defp normalize_map(v) when is_map(v), do: v
  defp normalize_map(_), do: %{}

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(fn
      item when is_binary(item) -> String.trim(item)
      item -> item |> to_string() |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_string_list(_), do: []

  defp normalize_embedding(nil), do: nil
  defp normalize_embedding(v) when is_binary(v), do: v
  defp normalize_embedding(_), do: nil

  defp normalize_db_embedding(nil), do: nil

  defp normalize_db_embedding(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  defp normalize_db_embedding(_), do: nil

  defp normalize_db_json_map(nil), do: %{}

  defp normalize_db_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp normalize_db_json_map(value) when is_map(value), do: value
  defp normalize_db_json_map(_), do: %{}

  defp normalize_db_json_list(nil), do: []

  defp normalize_db_json_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> normalize_string_list(decoded)
      _ -> []
    end
  end

  defp normalize_db_json_list(value) when is_list(value), do: normalize_string_list(value)
  defp normalize_db_json_list(_), do: []

  defp normalize_datetime(%DateTime{} = dt, _fallback), do: dt

  defp normalize_datetime(value, fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> fallback
    end
  end

  defp normalize_datetime(_value, fallback), do: fallback

  defp map_get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp id(prefix) do
    suffix =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "#{prefix}_#{suffix}"
  end

  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(other) when is_binary(other), do: other
  defp iso8601(_), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp nullable_iso8601(nil), do: nil
  defp nullable_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp nullable_iso8601(other) when is_binary(other), do: other
  defp nullable_iso8601(_), do: nil

  defp json_encode(term) do
    case Jason.encode(term) do
      {:ok, json} -> json
      _ -> "{}"
    end
  end

  defp sql_escape(value) when is_binary(value) do
    String.replace(value, "'", "''")
  end

  defp sql_escape(value), do: value |> to_string() |> sql_escape()
end
