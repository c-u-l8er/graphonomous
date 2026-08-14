defmodule Graphonomous do
  @moduledoc """
  Public API for Graphonomous.

  This module is the single entrypoint used by MCP tools and any direct callers.
  It normalizes incoming payloads and delegates to the core runtime modules.
  """

  alias Graphonomous.{
    Attention,
    Consolidator,
    Coverage,
    Deliberator,
    GoalGraph,
    Graph,
    Learner,
    Orchestrator,
    Retriever,
    Store
  }

  @allowed_node_types [:episodic, :semantic, :procedural, :temporal, :outcome, :goal]
  @allowed_statuses [:success, :partial_success, :failure, :timeout]

  @doc "Returns the application version string."
  @spec version() :: String.t()
  def version do
    case Application.spec(:graphonomous, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      vsn when is_binary(vsn) -> vsn
      _ -> "0.0.0"
    end
  end

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
    content = Map.get(attrs, :content) || Map.get(attrs, "content")

    if is_binary(content) and String.trim(content) != "" do
      result =
        attrs
        |> normalize_node_attrs()
        |> Graph.store_node()
        |> unwrap_ok()

      Attention.notify_graph_mutation()
      result
    else
      {:error, :content_required}
    end
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Store multiple knowledge nodes in batch, using a single HNSW batch_add call.

  Accepts a list of maps (same shape as `store_node/1`). Returns the list of
  successfully created nodes (unwrapped).
  """
  def store_nodes_batch(attrs_list) when is_list(attrs_list) do
    result =
      attrs_list
      |> Enum.map(&normalize_node_attrs/1)
      |> Graph.store_nodes_batch()
      |> unwrap_ok()

    Attention.notify_graph_mutation()
    result
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Retrieve semantically relevant context nodes for a natural-language query.
  """
  def retrieve_context(query, opts \\ [])

  def retrieve_context(query, opts) when is_binary(query) and is_list(opts) do
    Retriever.retrieve(query, opts)
    |> unwrap_ok()
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Run κ-driven deliberation over a topology and retrieval context.

  Expected arguments:

    * `topology` - map with SCC/routing output (typically from topology analysis)
    * `query` - natural-language problem statement
    * `retrieval_results` - retrieval rows used as deliberation evidence
    * `opts` - optional controls (`:agent_fn`, `:budget`, `:write_back`, etc.)
  """
  def deliberate(topology, query, retrieval_results, opts \\ [])
      when is_map(topology) and is_binary(query) and is_list(retrieval_results) and is_list(opts) do
    Deliberator.deliberate(topology, query, retrieval_results, opts)
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
  SCOPE (OS-012) spatial query: return knowledge nodes whose N-dimensional
  `region` lies within `radius` (Euclidean) of `center`, nearest-first.

  This is the first real consumer of the node `region` field — an N-D
  region-algebra ball query over the graph. Returns `[{node, distance}]`. Nodes
  without a region, or with a region of a different dimensionality than `center`,
  are excluded.

  Options: `:limit` (default 100).
  """
  def nodes_in_region(center, radius, opts \\ [])
      when is_list(center) and is_number(radius) and is_list(opts) do
    Store.nodes_in_region(center, radius, opts)
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

    result =
      Graph.create_edge(attrs)
      |> unwrap_ok()

    Attention.notify_graph_mutation()
    result
  end

  @doc """
  Update a node.
  """
  def update_node(node_id, attrs) when is_binary(node_id) and is_map(attrs) do
    normalized = normalize_node_attrs(attrs)

    result =
      Graph.update_node(node_id, normalized)
      |> unwrap_ok()

    Attention.notify_graph_mutation()
    result
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Delete a node by ID.
  """
  def delete_node(node_id) when is_binary(node_id) do
    result =
      Graph.delete_node(node_id)
      |> unwrap_ok()

    Attention.notify_graph_mutation()
    result
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Create a durable goal in the GoalGraph.
  """
  def create_goal(attrs) when is_map(attrs) do
    GoalGraph.create_goal(attrs)
    |> unwrap_ok()
  end

  @doc """
  Get a goal by ID.
  """
  def get_goal(goal_id) when is_binary(goal_id) do
    GoalGraph.get_goal(goal_id)
    |> unwrap_ok()
  end

  @doc """
  List goals with optional filters.
  """
  def list_goals(filters \\ %{})

  def list_goals(filters) when is_map(filters) do
    GoalGraph.list_goals(filters)
    |> unwrap_ok()
  end

  @doc """
  Update a goal by ID.
  """
  def update_goal(goal_id, attrs) when is_binary(goal_id) and is_map(attrs) do
    GoalGraph.update_goal(goal_id, attrs)
    |> unwrap_ok()
  end

  @doc """
  Delete a goal by ID.
  """
  def delete_goal(goal_id) when is_binary(goal_id) do
    GoalGraph.delete_goal(goal_id)
    |> unwrap_ok()
  end

  @doc """
  Transition a goal to a new status.
  """
  def transition_goal(goal_id, to_status, metadata \\ %{})
      when is_binary(goal_id) and is_map(metadata) do
    GoalGraph.transition_goal(goal_id, to_status, metadata)
    |> unwrap_ok()
  end

  @doc """
  Link node IDs to a goal.
  """
  def link_goal_nodes(goal_id, node_ids) when is_binary(goal_id) and is_list(node_ids) do
    GoalGraph.link_nodes(goal_id, node_ids)
    |> unwrap_ok()
  end

  @doc """
  Unlink node IDs from a goal.
  """
  def unlink_goal_nodes(goal_id, node_ids) when is_binary(goal_id) and is_list(node_ids) do
    GoalGraph.unlink_nodes(goal_id, node_ids)
    |> unwrap_ok()
  end

  @doc """
  Set goal progress (`0.0..1.0`).
  """
  def set_goal_progress(goal_id, progress) when is_binary(goal_id) do
    GoalGraph.set_progress(goal_id, progress)
    |> unwrap_ok()
  end

  @doc """
  Run epistemic review for a goal from a coverage signal.
  """
  def review_goal(goal_id, signal, opts \\ [])
      when is_binary(goal_id) and is_map(signal) and is_list(opts) do
    GoalGraph.review_goal(goal_id, signal, opts)
    |> unwrap_ok()
  end

  @doc """
  Evaluate epistemic coverage and return full scoring output.
  """
  def evaluate_coverage(signal, opts \\ [])
      when is_map(signal) and is_list(opts) do
    Coverage.evaluate(signal, opts)
  end

  @doc """
  Return only the recommended coverage decision.
  """
  def decide_coverage(signal, opts \\ [])
      when is_map(signal) and is_list(opts) do
    Coverage.decide(signal, opts)
  end

  @doc """
  Trigger an immediate consolidation cycle.
  """
  def run_consolidation_now do
    Consolidator.run_now()
  end

  @doc """
  Rebuild the in-memory ETS cache from durable SQLite state.
  """
  def rebuild_cache do
    Graphonomous.Store.rebuild_cache()
  end

  @doc """
  Return consolidator runtime information.
  """
  def consolidator_info do
    Consolidator.info()
  end

  @doc """
  Return orchestrator runtime information (learning rate, plasticity metrics).
  """
  def orchestrator_info do
    Orchestrator.info()
  end

  @doc """
  Get the current adaptive learning rate from the Orchestrator.
  """
  def current_learning_rate do
    Orchestrator.current_learning_rate()
  end

  @doc """
  Recommend a timescale for new knowledge based on type and graph dynamics.
  """
  def recommend_timescale(attrs) when is_map(attrs) do
    Orchestrator.recommend_timescale(attrs)
  end

  @doc """
  Basic health information for runtime visibility.
  """
  def health do
    %{
      graph: process_state(Graph),
      retriever: process_state(Retriever),
      learner: process_state(Learner),
      goal_graph: process_state(GoalGraph),
      orchestrator: process_state(Orchestrator),
      attention: process_state(Graphonomous.Attention),
      consolidator: process_state(Consolidator)
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
    |> Map.put(
      :node_type,
      normalize_node_type(Map.get(attrs, :node_type) || Map.get(attrs, "node_type"))
    )
    |> Map.put(
      :confidence,
      normalize_confidence(Map.get(attrs, :confidence) || Map.get(attrs, "confidence"))
    )
    |> Map.put(
      :metadata,
      normalize_metadata(Map.get(attrs, :metadata) || Map.get(attrs, "metadata"))
    )
  end

  defp normalize_outcome_attrs(attrs) do
    attrs
    |> Map.put(:status, normalize_status(Map.get(attrs, :status) || Map.get(attrs, "status")))
    |> Map.put(
      :confidence,
      normalize_confidence(Map.get(attrs, :confidence) || Map.get(attrs, "confidence"))
    )
    |> Map.put(
      :causal_node_ids,
      normalize_causal_node_ids(
        Map.get(attrs, :causal_node_ids) || Map.get(attrs, "causal_node_ids")
      )
    )
    |> Map.put(
      :evidence,
      normalize_metadata(Map.get(attrs, :evidence) || Map.get(attrs, "evidence"))
    )
    |> Map.put(
      :retrieval_trace_id,
      normalize_optional_string(
        Map.get(attrs, :retrieval_trace_id) || Map.get(attrs, "retrieval_trace_id")
      )
    )
    |> Map.put(
      :decision_trace_id,
      normalize_optional_string(
        Map.get(attrs, :decision_trace_id) || Map.get(attrs, "decision_trace_id")
      )
    )
    |> Map.put(
      :action_linkage,
      normalize_metadata(Map.get(attrs, :action_linkage) || Map.get(attrs, "action_linkage"))
    )
    |> Map.put(
      :grounding,
      normalize_metadata(Map.get(attrs, :grounding) || Map.get(attrs, "grounding"))
    )
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
      "temporal" -> :temporal
      "outcome" -> :outcome
      "goal" -> :goal
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

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value), do: value |> to_string() |> normalize_optional_string()

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
