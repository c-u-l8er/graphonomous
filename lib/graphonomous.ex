defmodule Graphonomous do
  @moduledoc """
  Public API for Graphonomous.

  This module is the single entrypoint used by MCP tools and any direct callers.
  It normalizes incoming payloads and delegates to the core runtime modules.
  """

  alias Graphonomous.{Graph, Learner, Retriever}

  @allowed_node_types [:episodic, :semantic, :procedural]
  @allowed_statuses [:success, :partial_success, :failure, :timeout]

  @doc """
  Store a knowledge node.

  Accepts a map with fields like:

    * `:content` (required)
    * `:node_type` (`:episodic | :semantic | :procedural` or string)
    * `:confidence` (`0.0..1.0`)
    * `:source`
    * `:metadata`

  Returns whatever the underlying graph layer returns, but unwraps `{:ok, value}`
  into `value` for ergonomic MCP usage.
  """
  def store_node(attrs) when is_map(attrs) do
    attrs
    |> normalize_node_attrs()
    |> Graph.store_node()
    |> unwrap_ok()
  end

  @doc """
  Retrieve semantically relevant context nodes for a natural-language query.
  """
  def retrieve_context(query, opts \\ [])

  def retrieve_context(query, opts) when is_binary(query) and is_list(opts) do
    Retriever.retrieve(query, opts)
    |> unwrap_ok()
  end

  @doc """
  Learn from an action outcome and update confidence on causal nodes.

  Expected keys:

    * `:action_id`
    * `:status` (`success|partial_success|failure|timeout`, atom or string)
    * `:confidence` (`0.0..1.0`)
    * `:causal_node_ids` (list of node IDs or JSON array string)
    * `:evidence` (optional)
  """
  def learn_from_outcome(attrs) when is_map(attrs) do
    attrs
    |> normalize_outcome_attrs()
    |> Learner.learn_from_outcome()
    |> unwrap_ok()
  end

  @doc """
  Query graph data (list/filter nodes). Delegates to `Graph.query/1`.
  """
  def query_graph(params \\ %{})

  def query_graph(params) when is_map(params) do
    params
    |> normalize_query_params()
    |> Graph.query()
    |> unwrap_ok()
  end

  @doc """
  Get a single node by ID.
  """
  def get_node(node_id) when is_binary(node_id) do
    Graph.get_node(node_id)
    |> unwrap_ok()
  end

  @doc """
  List nodes with optional filters.
  """
  def list_nodes(filters \\ %{})

  def list_nodes(filters) when is_map(filters) do
    filters
    |> normalize_query_params()
    |> Graph.list_nodes()
    |> unwrap_ok()
  end

  @doc """
  Create an edge between two nodes.
  """
  def link_nodes(source_id, target_id, attrs \\ %{})
      when is_binary(source_id) and is_binary(target_id) and is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:source_id, source_id)
      |> Map.put(:target_id, target_id)

    Graph.create_edge(attrs)
    |> unwrap_ok()
  end

  @doc """
  Update a node.
  """
  def update_node(node_id, attrs) when is_binary(node_id) and is_map(attrs) do
    attrs
    |> normalize_node_attrs()
    |> Graph.update_node(node_id)
    |> unwrap_ok()
  end

  @doc """
  Delete a node by ID.
  """
  def delete_node(node_id) when is_binary(node_id) do
    Graph.delete_node(node_id)
    |> unwrap_ok()
  end

  @doc """
  Basic health information for runtime visibility.
  """
  def health do
    %{
      graph: process_state(Graph),
      retriever: process_state(Retriever),
      learner: process_state(Learner)
    }
  end

  defp process_state(module) do
    case Process.whereis(module) do
      nil -> :down
      _pid -> :up
    end
  end

  defp unwrap_ok({:ok, value}), do: value
  defp unwrap_ok(other), do: other

  defp normalize_node_attrs(attrs) do
    attrs
    |> Map.put(:node_type, normalize_node_type(Map.get(attrs, :node_type) || Map.get(attrs, "node_type")))
    |> Map.put(:confidence, normalize_confidence(Map.get(attrs, :confidence) || Map.get(attrs, "confidence")))
    |> Map.put(:metadata, normalize_metadata(Map.get(attrs, :metadata) || Map.get(attrs, "metadata")))
  end

  defp normalize_outcome_attrs(attrs) do
    attrs
    |> Map.put(:status, normalize_status(Map.get(attrs, :status) || Map.get(attrs, "status")))
    |> Map.put(:confidence, normalize_confidence(Map.get(attrs, :confidence) || Map.get(attrs, "confidence")))
    |> Map.put(
      :causal_node_ids,
      normalize_causal_node_ids(Map.get(attrs, :causal_node_ids) || Map.get(attrs, "causal_node_ids"))
    )
    |> Map.put(:evidence, normalize_metadata(Map.get(attrs, :evidence) || Map.get(attrs, "evidence")))
  end

  defp normalize_query_params(params) do
    case Map.get(params, :node_type) || Map.get(params, "node_type") do
      nil -> params
      node_type -> Map.put(params, :node_type, normalize_node_type(node_type))
    end
  end

  defp normalize_node_type(type) when type in @allowed_node_types, do: type

  defp normalize_node_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.downcase()
    |> case do
      "episodic" -> :episodic
      "semantic" -> :semantic
      "procedural" -> :procedural
      _ -> :semantic
    end
  end

  defp normalize_node_type(_), do: :semantic

  defp normalize_status(status) when status in @allowed_statuses, do: status

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> String.downcase()
    |> case do
      "success" -> :success
      "partial_success" -> :partial_success
      "failure" -> :failure
      "timeout" -> :timeout
      _ -> :failure
    end
  end

  defp normalize_status(_), do: :failure

  defp normalize_confidence(nil), do: 0.5
  defp normalize_confidence(value) when is_integer(value), do: normalize_confidence(value * 1.0)

  defp normalize_confidence(value) when is_float(value) do
    value
    |> max(0.0)
    |> min(1.0)
  end

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _rest} -> normalize_confidence(parsed)
      :error -> 0.5
    end
  end

  defp normalize_confidence(_), do: 0.5

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(value) when is_map(value), do: value

  defp normalize_metadata(value) when is_binary(value) do
    with true <- Code.ensure_loaded?(Jason),
         {:ok, decoded} <- Jason.decode(value),
         true <- is_map(decoded) do
      decoded
    else
      _ -> %{}
    end
  end

  defp normalize_metadata(_), do: %{}

  defp normalize_causal_node_ids(nil), do: []
  defp normalize_causal_node_ids(ids) when is_list(ids), do: Enum.filter(ids, &is_binary/1)

  defp normalize_causal_node_ids(ids) when is_binary(ids) do
    with true <- Code.ensure_loaded?(Jason),
         {:ok, decoded} <- Jason.decode(ids),
         true <- is_list(decoded) do
      Enum.filter(decoded, &is_binary/1)
    else
      _ -> []
    end
  end

  defp normalize_causal_node_ids(_), do: []
end
