defmodule Graphonomous.Graph do
  @moduledoc """
  Graph orchestrator.

  This GenServer coordinates:

  - Node CRUD (`Graphonomous.Store`)
  - Edge CRUD (`Graphonomous.Store`)
  - Embedding generation (`Graphonomous.Embedder`)
  - Basic similarity retrieval over stored embeddings

  It provides a single runtime surface for higher-level modules and MCP tools.
  """

  use GenServer

  alias Graphonomous.{Embedder, HNSWIndex, Store}
  alias Graphonomous.Types.Node

  @default_similarity_limit 10
  @default_call_timeout 30_000
  @default_retrieve_timeout 30_000

  @type node_id :: binary()
  @type edge_id :: binary()

  @type state :: %{
          started_at: DateTime.t()
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec store_node(map()) :: {:ok, Node.t()} | {:error, term()}
  def store_node(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:store_node, attrs}, @default_call_timeout)
  end

  @doc "Store multiple nodes in batch, using a single HNSW batch_add call."
  @spec store_nodes_batch([map()]) :: {:ok, [Node.t()]} | {:error, term()}
  def store_nodes_batch(attrs_list) when is_list(attrs_list) do
    GenServer.call(__MODULE__, {:store_nodes_batch, attrs_list}, 60_000)
  end

  @spec get_node(node_id()) :: {:ok, Node.t()} | {:error, term()}
  def get_node(node_id) when is_binary(node_id) do
    GenServer.call(__MODULE__, {:get_node, node_id}, @default_call_timeout)
  end

  @spec list_nodes(map()) :: {:ok, [Node.t()]} | {:error, term()}
  def list_nodes(filters \\ %{}) when is_map(filters) do
    GenServer.call(__MODULE__, {:list_nodes, filters}, @default_call_timeout)
  end

  @spec update_node(node_id(), map()) :: {:ok, Node.t()} | {:error, term()}
  def update_node(node_id, attrs) when is_binary(node_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:update_node, node_id, attrs}, @default_call_timeout)
  end

  @spec delete_node(node_id()) :: :ok | {:error, term()}
  def delete_node(node_id) when is_binary(node_id) do
    GenServer.call(__MODULE__, {:delete_node, node_id}, @default_call_timeout)
  end

  @spec create_edge(map()) :: {:ok, map()} | {:error, term()}
  def create_edge(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:create_edge, attrs}, @default_call_timeout)
  end

  @spec create_edge(node_id(), node_id(), map()) :: {:ok, map()} | {:error, term()}
  def create_edge(source_id, target_id, attrs)
      when is_binary(source_id) and is_binary(target_id) and is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:source_id, source_id)
      |> Map.put(:target_id, target_id)

    GenServer.call(__MODULE__, {:create_edge, attrs}, @default_call_timeout)
  end

  @spec get_edges_for_node(node_id()) :: {:ok, [map()]} | {:error, term()}
  def get_edges_for_node(node_id) when is_binary(node_id) do
    GenServer.call(__MODULE__, {:get_edges_for_node, node_id}, @default_call_timeout)
  end

  @spec list_all_edges() :: {:ok, [map()]} | {:error, term()}
  def list_all_edges do
    Store.list_all_edges()
  end

  @spec update_edge(edge_id(), map()) :: {:ok, map()} | {:error, term()}
  def update_edge(edge_id, attrs) when is_binary(edge_id) and is_map(attrs) do
    Store.update_edge(edge_id, attrs)
  end

  @spec delete_edge(edge_id()) :: :ok | {:error, term()}
  def delete_edge(edge_id) when is_binary(edge_id) do
    Store.delete_edge(edge_id)
  end

  @spec query(map()) :: {:ok, term()} | {:error, term()}
  def query(params \\ %{}) when is_map(params) do
    operation =
      Map.get(params, :operation) ||
        Map.get(params, "operation") ||
        Map.get(params, :action) ||
        Map.get(params, "action")

    timeout =
      case operation do
        :similarity_search -> @default_retrieve_timeout
        "similarity_search" -> @default_retrieve_timeout
        _ -> @default_call_timeout
      end

    GenServer.call(__MODULE__, {:query, params}, timeout)
  end

  @spec retrieve_similar(binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def retrieve_similar(text, opts \\ []) when is_binary(text) and is_list(opts) do
    timeout =
      opts
      |> Keyword.get(:timeout, @default_retrieve_timeout)
      |> case do
        value when is_integer(value) and value > 0 -> value
        _ -> @default_retrieve_timeout
      end

    GenServer.call(__MODULE__, {:retrieve_similar, text, opts}, timeout)
  end

  @spec touch_node(node_id()) :: {:ok, Node.t()} | {:error, term()}
  def touch_node(node_id) when is_binary(node_id) do
    GenServer.call(__MODULE__, {:touch_node, node_id}, @default_call_timeout)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:store_node, attrs}, _from, state) do
    attrs = normalize_map_keys(attrs)

    with {:ok, enriched} <- maybe_attach_embedding(attrs),
         {:ok, node} <- Store.insert_node(enriched) do
      hnsw_sync_add(node)
      # Post-store hook: entity resolution (async, best-effort)
      if is_binary(node.id) and is_binary(node.content) and node.content != "" do
        Task.start(fn -> safe_entity_resolve(node.id, node.content) end)
      end

      {:reply, {:ok, node}, state}
    else
      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:store_nodes_batch, attrs_list}, _from, state) do
    results =
      Enum.map(attrs_list, fn attrs ->
        attrs = normalize_map_keys(attrs)

        with {:ok, enriched} <- maybe_attach_embedding(attrs),
             {:ok, node} <- Store.insert_node(enriched) do
          {:ok, node}
        end
      end)

    # Collect successful nodes for batch HNSW add
    nodes = for {:ok, node} <- results, do: node

    hnsw_items =
      for %Node{id: id, embedding: emb} <- nodes,
          is_binary(id) and is_binary(emb) and byte_size(emb) > 0,
          do: {id, emb}

    if hnsw_items != [] do
      HNSWIndex.batch_add(hnsw_items)
    end

    # Post-store hook: entity resolution for all batch nodes (async)
    entity_candidates =
      for %Node{id: id, content: content} <- nodes,
          is_binary(id) and is_binary(content) and content != "",
          do: {id, content}

    if entity_candidates != [] do
      Task.start(fn ->
        Enum.each(entity_candidates, fn {id, content} ->
          safe_entity_resolve(id, content)
        end)
      end)
    end

    {:reply, {:ok, nodes}, state}
  end

  def handle_call({:get_node, node_id}, _from, state) do
    reply = Store.get_node(node_id)
    {:reply, reply, state}
  end

  def handle_call({:list_nodes, filters}, _from, state) do
    filters =
      filters
      |> normalize_map_keys()
      |> normalize_list_filters()

    reply = Store.list_nodes(filters)
    {:reply, reply, state}
  end

  def handle_call({:update_node, node_id, attrs}, _from, state) do
    attrs = normalize_map_keys(attrs)

    with {:ok, update_attrs} <- maybe_attach_embedding_for_update(attrs),
         {:ok, node} <- Store.update_node(node_id, update_attrs) do
      if Map.has_key?(attrs, :content) or Map.has_key?(attrs, :embedding) do
        hnsw_sync_add(node)
      end

      {:reply, {:ok, node}, state}
    else
      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:delete_node, node_id}, _from, state) do
    HNSWIndex.remove(node_id)
    reply = Store.delete_node(node_id)
    {:reply, reply, state}
  end

  def handle_call({:create_edge, attrs}, _from, state) do
    attrs =
      attrs
      |> normalize_map_keys()
      |> normalize_edge_attrs()

    reply = Store.upsert_edge(attrs)
    {:reply, reply, state}
  end

  def handle_call({:get_edges_for_node, node_id}, _from, state) do
    reply = Store.list_edges_for_node(node_id)
    {:reply, reply, state}
  end

  def handle_call({:touch_node, node_id}, _from, state) do
    reply = Store.increment_access(node_id)
    {:reply, reply, state}
  end

  def handle_call({:retrieve_similar, text, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, @default_similarity_limit)

    with {:ok, query_vec} <- Embedder.embed(text, task: :query),
         {:ok, ranked} <- hnsw_retrieve_with_fallback(query_vec, limit) do
      {:reply, {:ok, ranked}, state}
    else
      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:query, params}, _from, state) do
    params = normalize_map_keys(params)

    operation =
      Map.get(params, :operation) ||
        Map.get(params, :action) ||
        "list_nodes"

    reply =
      case normalize_operation(operation) do
        :get_node ->
          node_id = Map.get(params, :node_id) || Map.get(params, :id)

          if is_binary(node_id) do
            Store.get_node(node_id)
          else
            {:error, {:invalid_params, :node_id_required}}
          end

        :list_nodes ->
          filters =
            params
            |> Map.take([:node_type, :min_confidence, :limit])
            |> normalize_list_filters()

          Store.list_nodes(filters)

        :get_edges ->
          node_id = Map.get(params, :node_id) || Map.get(params, :id)

          if is_binary(node_id) do
            Store.list_edges_for_node(node_id)
          else
            {:error, {:invalid_params, :node_id_required}}
          end

        :similarity_search ->
          query = Map.get(params, :query) || Map.get(params, :text) || ""
          limit = Map.get(params, :limit, @default_similarity_limit)

          with {:ok, vector} <- Embedder.embed(query, task: :query),
               {:ok, ranked} <- hnsw_retrieve_with_fallback(vector, normalize_limit(limit)) do
            {:ok, ranked}
          end
      end

    {:reply, reply, state}
  end

  ## Embedding helpers

  defp maybe_attach_embedding(attrs) do
    content = Map.get(attrs, :content, "")

    cond do
      Map.has_key?(attrs, :embedding) and is_binary(Map.get(attrs, :embedding)) ->
        {:ok, attrs}

      not is_binary(content) or String.trim(content) == "" ->
        {:ok, Map.put(attrs, :embedding, nil)}

      true ->
        # Truncate content for embedding — models have token limits anyway,
        # and very long texts can cause embedder timeouts during batch ingestion.
        embed_text = String.slice(content, 0, 2048)

        try do
          case Embedder.embed_binary(embed_text, task: :document) do
            {:ok, embedding_blob} -> {:ok, Map.put(attrs, :embedding, embedding_blob)}
            {:error, _reason} -> {:ok, Map.put(attrs, :embedding, nil)}
          end
        catch
          :exit, {:timeout, _} ->
            # Embedder busy or overloaded — proceed without embedding rather than
            # crashing the Graph GenServer (which would kill all concurrent ingestion).
            {:ok, Map.put(attrs, :embedding, nil)}

          :exit, _reason ->
            {:ok, Map.put(attrs, :embedding, nil)}
        end
    end
  end

  defp maybe_attach_embedding_for_update(attrs) do
    content_changed? = Map.has_key?(attrs, :content)
    embedding_present? = Map.has_key?(attrs, :embedding)

    cond do
      embedding_present? ->
        {:ok, attrs}

      content_changed? ->
        maybe_attach_embedding(attrs)

      true ->
        {:ok, attrs}
    end
  end

  ## Similarity ranking

  defp rank_nodes_by_similarity(nodes, query_vec, limit)
       when is_list(nodes) and is_list(query_vec) and is_integer(limit) do
    ranked =
      nodes
      |> Enum.map(fn node ->
        node_vec = decode_embedding_blob(node.embedding)
        similarity = cosine_similarity(query_vec, node_vec)
        score = similarity * clamp(to_float(node.confidence), 0.0, 1.0)

        %{
          node: node,
          node_id: node.id,
          content: node.content,
          node_type: node.node_type,
          confidence: node.confidence,
          similarity: similarity,
          score: score
        }
      end)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(limit)

    {:ok, ranked}
  end

  @doc "Decode a binary blob of little-endian f32 floats into a list."
  def decode_embedding_blob(nil), do: []

  def decode_embedding_blob(blob) when is_binary(blob) do
    decode_f32_le(blob, [])
  end

  def decode_embedding_blob(_), do: []

  defp decode_f32_le(<<>>, acc), do: Enum.reverse(acc)

  defp decode_f32_le(<<f::float-little-32, rest::binary>>, acc),
    do: decode_f32_le(rest, [f | acc])

  defp decode_f32_le(_partial, acc), do: Enum.reverse(acc)

  @doc "Cosine similarity between two float lists. Returns 0.0 for empty/zero vectors."
  def cosine_similarity([], _), do: 0.0
  def cosine_similarity(_, []), do: 0.0

  def cosine_similarity(a, b) when is_list(a) and is_list(b) do
    n = min(length(a), length(b))

    if n == 0 do
      0.0
    else
      a_n = Enum.take(a, n)
      b_n = Enum.take(b, n)

      dot =
        Enum.zip(a_n, b_n)
        |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)

      mag_a = :math.sqrt(Enum.reduce(a_n, 0.0, fn x, acc -> acc + x * x end))
      mag_b = :math.sqrt(Enum.reduce(b_n, 0.0, fn x, acc -> acc + x * x end))

      if mag_a <= 1.0e-12 or mag_b <= 1.0e-12 do
        0.0
      else
        dot / (mag_a * mag_b)
      end
    end
  end

  ## Normalization helpers

  defp normalize_map_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_atom(k) ->
        Map.put(acc, k, v)

      {k, v}, acc when is_binary(k) ->
        atom_key =
          try do
            String.to_existing_atom(k)
          rescue
            _ -> String.to_atom(k)
          end

        Map.put(acc, atom_key, v)

      {k, v}, acc ->
        Map.put(acc, k, v)
    end)
  end

  defp normalize_list_filters(filters) do
    filters
    |> maybe_put_normalized_type()
    |> maybe_put_normalized_min_confidence()
    |> maybe_put_normalized_limit()
  end

  defp maybe_put_normalized_type(filters) do
    case Map.get(filters, :node_type) do
      nil -> filters
      type -> Map.put(filters, :node_type, normalize_node_type(type))
    end
  end

  defp maybe_put_normalized_min_confidence(filters) do
    case Map.get(filters, :min_confidence) do
      nil -> filters
      val -> Map.put(filters, :min_confidence, clamp(to_float(val), 0.0, 1.0))
    end
  end

  defp maybe_put_normalized_limit(filters) do
    case Map.get(filters, :limit) do
      nil -> filters
      val -> Map.put(filters, :limit, normalize_limit(val))
    end
  end

  defp normalize_edge_attrs(attrs) do
    attrs
    |> Map.update(:edge_type, :related, &normalize_edge_type/1)
    |> Map.update(:weight, 0.3, &clamp(to_float(&1), 0.0, 1.0))
    |> Map.update(:metadata, %{}, &normalize_metadata/1)
  end

  defp normalize_operation(op) when is_atom(op), do: normalize_operation(Atom.to_string(op))

  defp normalize_operation(op) when is_binary(op) do
    case String.downcase(String.trim(op)) do
      "get_node" -> :get_node
      "get" -> :get_node
      "list_nodes" -> :list_nodes
      "list" -> :list_nodes
      "get_edges" -> :get_edges
      "edges" -> :get_edges
      "similarity_search" -> :similarity_search
      "retrieve_context" -> :similarity_search
      _ -> :list_nodes
    end
  end

  defp normalize_operation(_), do: :list_nodes

  @valid_node_types [:episodic, :semantic, :procedural, :temporal, :outcome, :goal]

  defp normalize_node_type(type) when type in @valid_node_types, do: type

  defp normalize_node_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "episodic" -> :episodic
      "procedural" -> :procedural
      "temporal" -> :temporal
      "outcome" -> :outcome
      "goal" -> :goal
      _ -> :semantic
    end
  end

  defp normalize_node_type(_), do: :semantic

  @valid_edge_types [
    :causal,
    :causes,
    :resolves,
    :related,
    :related_to,
    :part_of,
    :follows,
    :contradicts,
    :supersedes,
    :superseded_by,
    :depends_on,
    :similar_to,
    :supports,
    :derived_from,
    :temporal_before,
    :temporal_after,
    :co_occurs
  ]

  defp normalize_edge_type(type) when type in @valid_edge_types, do: type

  defp normalize_edge_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "causal" -> :causal
      "causes" -> :causes
      "resolves" -> :resolves
      "related" -> :related
      "related_to" -> :related_to
      "part_of" -> :part_of
      "follows" -> :follows
      "contradicts" -> :contradicts
      "supersedes" -> :supersedes
      "superseded_by" -> :superseded_by
      "depends_on" -> :depends_on
      "similar_to" -> :similar_to
      "supports" -> :supports
      "derived_from" -> :derived_from
      "temporal_before" -> :temporal_before
      "temporal_after" -> :temporal_after
      "co_occurs" -> :co_occurs
      _ -> :related
    end
  end

  defp normalize_edge_type(_), do: :related

  defp normalize_metadata(v) when is_map(v), do: v
  defp normalize_metadata(_), do: %{}

  defp normalize_limit(v) when is_integer(v) and v > 0, do: v

  defp normalize_limit(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} when i > 0 -> i
      _ -> @default_similarity_limit
    end
  end

  defp normalize_limit(_), do: @default_similarity_limit

  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_float(v), do: v

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  ## HNSW integration

  defp hnsw_retrieve_with_fallback(query_vec, limit) when is_list(query_vec) do
    if HNSWIndex.available?() do
      # Over-fetch from HNSW, then rerank by confidence-weighted score
      case HNSWIndex.query(query_vec, limit * 3) do
        {:ok, hnsw_results} when hnsw_results != [] ->
          ranked =
            hnsw_results
            |> Enum.flat_map(fn {node_id, distance} ->
              case Store.get_node(node_id) do
                {:ok, %Node{} = node} ->
                  # cosine distance -> similarity: sim = 1 - distance
                  similarity = max(1.0 - distance, 0.0)
                  score = similarity * clamp(to_float(node.confidence), 0.0, 1.0)

                  [
                    %{
                      node: node,
                      node_id: node.id,
                      content: node.content,
                      node_type: node.node_type,
                      confidence: node.confidence,
                      similarity: similarity,
                      score: score
                    }
                  ]

                _ ->
                  []
              end
            end)
            |> Enum.sort_by(& &1.score, :desc)
            |> Enum.take(limit)

          {:ok, ranked}

        _ ->
          # HNSW returned empty or errored — fall back to brute-force
          brute_force_retrieve(query_vec, limit)
      end
    else
      brute_force_retrieve(query_vec, limit)
    end
  end

  defp brute_force_retrieve(query_vec, limit) do
    with {:ok, nodes} <- Store.list_nodes(%{}),
         {:ok, ranked} <- rank_nodes_by_similarity(nodes, query_vec, limit) do
      {:ok, ranked}
    end
  end

  defp hnsw_sync_add(%Node{id: id, embedding: embedding})
       when is_binary(id) and is_binary(embedding) and byte_size(embedding) > 0 do
    HNSWIndex.add(id, embedding)
  end

  defp hnsw_sync_add(_), do: :ok

  defp safe_entity_resolve(node_id, content) do
    Graphonomous.EntityResolver.resolve_and_link(node_id, content)
  rescue
    error ->
      require Logger
      Logger.debug("Entity resolution failed for node #{node_id}: #{inspect(error)}")
      :ok
  end
end
