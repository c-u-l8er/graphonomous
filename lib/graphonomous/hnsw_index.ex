defmodule Graphonomous.HNSWIndex do
  @moduledoc """
  HNSW approximate nearest-neighbor index for fast vector similarity search.

  Wraps the `hnswlib` NIF (elixir-nx) to provide O(log n) KNN queries
  instead of brute-force O(n) cosine similarity.

  Lifecycle:
    1. Store starts and warms ETS cache from SQLite
    2. HNSWIndex starts, reads all node embeddings from ETS, builds index
    3. Graph uses HNSWIndex.query/2 for similarity search
    4. On node insert/update/delete, Graph calls add/remove to keep index in sync
    5. Index is persisted to disk periodically and on shutdown

  Falls back gracefully: if HNSWIndex is down, Graph reverts to brute-force.
  """

  use GenServer

  require Logger

  @nodes_table :graphonomous_nodes

  @default_dimension 384
  @default_max_elements 100_000
  @default_ef_construction 200
  @default_m 16
  @default_ef_search 50

  # ---- Public API ----

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add a node's embedding to the HNSW index."
  @spec add(binary(), binary()) :: :ok | {:error, term()}
  def add(node_id, embedding_blob) when is_binary(node_id) and is_binary(embedding_blob) do
    GenServer.call(__MODULE__, {:add, node_id, embedding_blob})
  catch
    :exit, _ -> {:error, :hnsw_unavailable}
  end

  @doc """
  Add multiple node embeddings to the HNSW index in a single batched operation.

  Accepts a list of `{node_id, embedding_blob}` tuples. Uses a single
  `HNSWLib.Index.add_items` call with a stacked Nx tensor for efficiency.
  Returns `{:ok, added_count}` or `{:error, reason}`.
  """
  @spec batch_add([{binary(), binary()}]) :: {:ok, non_neg_integer()} | {:error, term()}
  def batch_add(items) when is_list(items) do
    GenServer.call(__MODULE__, {:batch_add, items}, 60_000)
  catch
    :exit, _ -> {:error, :hnsw_unavailable}
  end

  @doc "Remove a node from the HNSW index."
  @spec remove(binary()) :: :ok | {:error, term()}
  def remove(node_id) when is_binary(node_id) do
    GenServer.call(__MODULE__, {:remove, node_id})
  catch
    :exit, _ -> {:error, :hnsw_unavailable}
  end

  @doc """
  Query the HNSW index for k nearest neighbors.

  Accepts either a float list or a binary embedding blob as the query vector.
  Returns `{:ok, [{node_id, distance}]}` sorted by proximity (lowest distance first).
  """
  @spec query(list(float()) | binary(), pos_integer()) ::
          {:ok, [{binary(), float()}]} | {:error, term()}
  def query(query_vec, k \\ 10)

  def query(query_vec, k) when is_list(query_vec) and is_integer(k) and k > 0 do
    GenServer.call(__MODULE__, {:query, query_vec, k}, 10_000)
  catch
    :exit, _ -> {:error, :hnsw_unavailable}
  end

  def query(query_blob, k) when is_binary(query_blob) and is_integer(k) and k > 0 do
    query(decode_f32_le(query_blob), k)
  end

  @doc "Return index statistics."
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  catch
    :exit, _ -> %{status: :unavailable}
  end

  @doc "Check if the HNSW index is available."
  @spec available?() :: boolean()
  def available? do
    Process.whereis(__MODULE__) != nil
  end

  # ---- GenServer callbacks ----

  @impl true
  def init(opts) do
    dimension = Keyword.get(opts, :dimension, @default_dimension)
    max_elements = Keyword.get(opts, :max_elements, @default_max_elements)
    ef_construction = Keyword.get(opts, :ef_construction, @default_ef_construction)
    m = Keyword.get(opts, :m, @default_m)
    ef_search = Keyword.get(opts, :ef_search, @default_ef_search)
    index_path = Keyword.get(opts, :index_path, nil)

    state = %{
      index: nil,
      dimension: dimension,
      max_elements: max_elements,
      ef_construction: ef_construction,
      m: m,
      ef_search: ef_search,
      index_path: index_path,
      id_to_label: %{},
      label_to_id: %{},
      next_label: 0,
      element_count: 0,
      inserts_since_save: 0
    }

    # Build index asynchronously to not block supervision tree startup
    send(self(), :build_index)

    {:ok, state}
  end

  @impl true
  def handle_info(:build_index, state) do
    case build_hnsw_index(state) do
      {:ok, new_state} ->
        Logger.info(
          "HNSWIndex: built index with #{new_state.element_count} vectors " <>
            "(dim=#{state.dimension}, M=#{state.m}, ef_construction=#{state.ef_construction})"
        )

        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("HNSWIndex: failed to build index: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:save_index, state) do
    save_index_to_disk(state)
    {:noreply, %{state | inserts_since_save: 0}}
  end

  @impl true
  def handle_call({:add, node_id, embedding_blob}, _from, state) do
    case do_add(state, node_id, embedding_blob) do
      {:ok, new_state} ->
        new_state = maybe_schedule_save(new_state)
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:batch_add, items}, _from, state) do
    case do_batch_add(state, items) do
      {:ok, new_state, added} ->
        new_state = maybe_schedule_save(new_state)
        {:reply, {:ok, added}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove, node_id}, _from, state) do
    case do_remove(state, node_id) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, query_vec, k}, _from, state) do
    case do_query(state, query_vec, k) do
      {:ok, results} ->
        {:reply, {:ok, results}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:info, _from, state) do
    info = %{
      status: if(state.index != nil, do: :ready, else: :building),
      dimension: state.dimension,
      element_count: state.element_count,
      max_elements: state.max_elements,
      ef_construction: state.ef_construction,
      m: state.m,
      ef_search: state.ef_search,
      id_map_size: map_size(state.id_to_label)
    }

    {:reply, info, state}
  end

  @impl true
  def terminate(_reason, state) do
    save_index_to_disk(state)
    :ok
  end

  # ---- Internal: Index construction ----

  defp build_hnsw_index(state) do
    space = :cosine
    dim = state.dimension

    case HNSWLib.Index.new(space, dim, state.max_elements,
           ef_construction: state.ef_construction,
           m: state.m
         ) do
      {:ok, index} ->
        # Try loading from disk first
        state = %{state | index: index}
        state = try_load_from_disk(state)

        # Then rebuild from ETS to ensure consistency
        state = rebuild_from_ets(state)

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_load_from_disk(%{index_path: nil} = state), do: state
  defp try_load_from_disk(%{index_path: ""} = state), do: state

  defp try_load_from_disk(%{index_path: path, dimension: dim} = state) do
    hnsw_path = "#{path}.hnsw"

    if File.exists?(hnsw_path) do
      case HNSWLib.Index.load_index(:cosine, dim, hnsw_path) do
        {:ok, loaded_index} ->
          Logger.info("HNSWIndex: loaded persisted index from #{hnsw_path}")
          %{state | index: loaded_index}

        {:error, _reason} ->
          Logger.info("HNSWIndex: could not load #{hnsw_path}, will rebuild from ETS")
          state
      end
    else
      state
    end
  end

  defp rebuild_from_ets(state) do
    # Read all nodes directly from ETS (Store has already warmed the cache)
    nodes =
      try do
        :ets.tab2list(@nodes_table)
      rescue
        ArgumentError -> []
      end

    {new_state, count} =
      Enum.reduce(nodes, {state, 0}, fn {_id, node}, {acc_state, acc_count} ->
        node_id = Map.get(node, :id)
        embedding = Map.get(node, :embedding)

        if is_binary(node_id) and is_binary(embedding) and byte_size(embedding) > 0 do
          case do_add(acc_state, node_id, embedding) do
            {:ok, updated} -> {updated, acc_count + 1}
            {:error, _} -> {acc_state, acc_count}
          end
        else
          {acc_state, acc_count}
        end
      end)

    %{new_state | element_count: count, inserts_since_save: 0}
  end

  # ---- Internal: Add / Remove / Query ----

  defp do_add(%{index: nil} = _state, _node_id, _blob), do: {:error, :index_not_ready}

  defp do_add(state, node_id, embedding_blob) do
    vec = decode_f32_le(embedding_blob)

    if length(vec) != state.dimension do
      {:error, {:dimension_mismatch, length(vec), state.dimension}}
    else
      # If node already exists, remove old label first
      state = maybe_remove_existing(state, node_id)

      label = state.next_label
      tensor = Nx.tensor([vec], type: :f32)

      case HNSWLib.Index.add_items(state.index, tensor, ids: Nx.tensor([label])) do
        :ok ->
          new_state = %{
            state
            | id_to_label: Map.put(state.id_to_label, node_id, label),
              label_to_id: Map.put(state.label_to_id, label, node_id),
              next_label: label + 1,
              element_count: state.element_count + 1,
              inserts_since_save: state.inserts_since_save + 1
          }

          {:ok, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_batch_add(%{index: nil}, _items), do: {:error, :index_not_ready}

  defp do_batch_add(state, items) when items == [], do: {:ok, state, 0}

  defp do_batch_add(state, items) do
    # Decode and validate all items, removing existing labels
    {valid, state} =
      Enum.reduce(items, {[], state}, fn {node_id, blob}, {acc, st} ->
        vec = decode_f32_le(blob)

        if length(vec) == st.dimension do
          st = maybe_remove_existing(st, node_id)
          {[{node_id, vec} | acc], st}
        else
          {acc, st}
        end
      end)

    valid = Enum.reverse(valid)

    if valid == [] do
      {:ok, state, 0}
    else
      # Assign contiguous labels
      start_label = state.next_label

      {rows, labels, id_to_label, label_to_id} =
        valid
        |> Enum.with_index()
        |> Enum.reduce({[], [], state.id_to_label, state.label_to_id}, fn
          {{node_id, vec}, idx}, {r_acc, l_acc, i2l, l2i} ->
            label = start_label + idx

            {[vec | r_acc], [label | l_acc], Map.put(i2l, node_id, label),
             Map.put(l2i, label, node_id)}
        end)

      batch_tensor = rows |> Enum.reverse() |> Nx.tensor(type: :f32)
      labels_tensor = labels |> Enum.reverse() |> Nx.tensor(type: :s64)
      count = length(valid)

      case HNSWLib.Index.add_items(state.index, batch_tensor, ids: labels_tensor) do
        :ok ->
          new_state = %{
            state
            | id_to_label: id_to_label,
              label_to_id: label_to_id,
              next_label: start_label + count,
              element_count: state.element_count + count,
              inserts_since_save: state.inserts_since_save + count
          }

          {:ok, new_state, count}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_remove(%{index: nil} = _state, _node_id), do: {:error, :index_not_ready}

  defp do_remove(state, node_id) do
    case Map.get(state.id_to_label, node_id) do
      nil ->
        {:ok, state}

      label ->
        # hnswlib supports mark_delete for soft removal
        _ =
          try do
            HNSWLib.Index.mark_deleted(state.index, label)
          rescue
            _ -> :ok
          end

        new_state = %{
          state
          | id_to_label: Map.delete(state.id_to_label, node_id),
            label_to_id: Map.delete(state.label_to_id, label),
            element_count: max(state.element_count - 1, 0)
        }

        {:ok, new_state}
    end
  end

  defp do_query(%{index: nil}, _query_vec, _k), do: {:error, :index_not_ready}

  defp do_query(state, query_vec, k) when is_list(query_vec) do
    if state.element_count == 0 do
      {:ok, []}
    else
      # Don't request more results than we have elements
      effective_k = min(k, state.element_count)
      tensor = Nx.tensor([query_vec], type: :f32)

      case HNSWLib.Index.knn_query(state.index, tensor, k: effective_k) do
        {:ok, labels_tensor, distances_tensor} ->
          labels = Nx.to_flat_list(labels_tensor)
          distances = Nx.to_flat_list(distances_tensor)

          results =
            Enum.zip(labels, distances)
            |> Enum.flat_map(fn {label, distance} ->
              label_int = trunc(label)

              case Map.get(state.label_to_id, label_int) do
                nil -> []
                node_id -> [{node_id, distance}]
              end
            end)

          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_remove_existing(state, node_id) do
    case Map.get(state.id_to_label, node_id) do
      nil ->
        state

      label ->
        _ =
          try do
            HNSWLib.Index.mark_deleted(state.index, label)
          rescue
            _ -> :ok
          end

        %{
          state
          | id_to_label: Map.delete(state.id_to_label, node_id),
            label_to_id: Map.delete(state.label_to_id, label),
            element_count: max(state.element_count - 1, 0)
        }
    end
  end

  # ---- Internal: Persistence ----

  defp maybe_schedule_save(%{inserts_since_save: n} = state) when n >= 100 do
    send(self(), :save_index)
    state
  end

  defp maybe_schedule_save(state), do: state

  defp save_index_to_disk(%{index: nil}), do: :ok
  defp save_index_to_disk(%{index_path: nil}), do: :ok
  defp save_index_to_disk(%{index_path: ""}), do: :ok

  defp save_index_to_disk(%{index: index, index_path: path}) do
    hnsw_path = "#{path}.hnsw"

    case HNSWLib.Index.save_index(index, hnsw_path) do
      :ok ->
        Logger.debug("HNSWIndex: saved index to #{hnsw_path}")
        :ok

      {:error, reason} ->
        Logger.warning("HNSWIndex: failed to save index: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---- Internal: Embedding decode ----

  defp decode_f32_le(blob) when is_binary(blob), do: decode_f32_le_acc(blob, [])
  defp decode_f32_le(_), do: []

  defp decode_f32_le_acc(<<>>, acc), do: Enum.reverse(acc)

  defp decode_f32_le_acc(<<f::float-little-32, rest::binary>>, acc),
    do: decode_f32_le_acc(rest, [f | acc])

  defp decode_f32_le_acc(_partial, acc), do: Enum.reverse(acc)
end
