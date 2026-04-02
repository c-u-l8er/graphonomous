defmodule Graphonomous.Consolidator do
  @moduledoc """
  Periodic memory maintenance for Graphonomous.

  Implements the spec §6 seven-stage consolidation pipeline:

    1. **decay** — exponential confidence decay on all nodes
    2. **prune_weak_nodes** — remove nodes below confidence threshold
    3. **prune_weak_edges** — remove edges below weight threshold
    4. **strengthen_coactivated** — boost edges between frequently co-retrieved nodes
    5. **merge_similar_nodes** — merge nodes with embedding similarity > threshold
    6. **promote_timescale** — move reinforced fast-memory to slow-memory
    7. **generate_abstractions** — create semantic nodes from episodic clusters

  Telemetry events emitted:
    - `[:graphonomous, :node, :decayed]`
    - `[:graphonomous, :node, :pruned]`
    - `[:graphonomous, :edge, :pruned]`
    - `[:graphonomous, :edge, :strengthened]`
    - `[:graphonomous, :node, :merged]`
    - `[:graphonomous, :node, :promoted]`
    - `[:graphonomous, :node, :abstracted]`
    - `[:graphonomous, :consolidator, :cycle]`
  """

  use GenServer

  require Logger

  alias Graphonomous.Graph

  @default_interval_ms 300_000
  @default_decay_rate 0.02
  @default_prune_threshold 0.1
  @default_edge_prune_threshold 0.1
  @default_merge_similarity 0.95
  @default_coactivation_boost 0.05
  @default_promotion_access_threshold 5
  @min_interval_ms 1_000

  @type state :: %{
          interval_ms: pos_integer(),
          decay_rate: float(),
          prune_threshold: float(),
          edge_prune_threshold: float(),
          merge_similarity: float(),
          coactivation_boost: float(),
          promotion_access_threshold: non_neg_integer(),
          timer_ref: reference() | nil,
          cycle_count: non_neg_integer(),
          last_run_at: DateTime.t() | nil
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an immediate consolidation cycle.

  Useful for tests and manual verification.
  """
  @spec run_now() :: :ok
  def run_now do
    GenServer.cast(__MODULE__, :run_now)
  end

  @doc """
  Returns consolidator runtime info.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      interval_ms:
        opts
        |> Keyword.get(:interval_ms, @default_interval_ms)
        |> normalize_interval(),
      decay_rate:
        opts
        |> Keyword.get(:decay_rate, @default_decay_rate)
        |> normalize_probability(),
      prune_threshold:
        opts
        |> Keyword.get(:prune_threshold, @default_prune_threshold)
        |> normalize_probability(),
      edge_prune_threshold:
        opts
        |> Keyword.get(:edge_prune_threshold, @default_edge_prune_threshold)
        |> normalize_probability(),
      merge_similarity:
        opts
        |> Keyword.get(:merge_similarity, @default_merge_similarity)
        |> normalize_probability(),
      coactivation_boost:
        opts
        |> Keyword.get(:coactivation_boost, @default_coactivation_boost)
        |> normalize_probability(),
      promotion_access_threshold:
        opts
        |> Keyword.get(:promotion_access_threshold, @default_promotion_access_threshold)
        |> max(1),
      timer_ref: nil,
      cycle_count: 0,
      last_run_at: nil
    }

    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, Map.drop(state, [:timer_ref]), state}
  end

  @impl true
  def handle_cast(:run_now, state) do
    {:noreply, run_cycle(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    state = %{state | timer_ref: nil}
    {:noreply, run_cycle(state)}
  end

  @impl true
  def terminate(_reason, state) do
    cancel_timer(state.timer_ref)
    :ok
  end

  ## Core cycle — full 7-stage pipeline

  defp run_cycle(state) do
    started_at = DateTime.utc_now()

    # Load all data once
    {nodes, edges} = load_graph_data()

    # Stage 1 & 2: decay + prune weak nodes
    {decayed, pruned_nodes, node_errors} =
      stage_decay_and_prune_nodes(nodes, state.decay_rate, state.prune_threshold)

    # Stage 3: prune weak edges
    {pruned_edges, edge_errors} = stage_prune_weak_edges(edges, state.edge_prune_threshold)

    # Stage 4: strengthen coactivated edges
    strengthened = stage_strengthen_coactivated(edges, state.coactivation_boost)

    # Stage 5: merge similar nodes (reload nodes after pruning)
    merged = stage_merge_similar_nodes(state.merge_similarity)

    # Stage 6: promote timescale
    promoted = stage_promote_timescale(state.promotion_access_threshold)

    # Stage 7: generate abstractions from episodic clusters
    abstracted = stage_generate_abstractions()

    duration_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

    :telemetry.execute(
      [:graphonomous, :consolidator, :cycle],
      %{
        decayed: decayed,
        pruned_nodes: pruned_nodes,
        pruned_edges: pruned_edges,
        strengthened: strengthened,
        merged: merged,
        promoted: promoted,
        abstracted: abstracted,
        errors: node_errors + edge_errors,
        duration_ms: duration_ms
      },
      %{
        cycle: state.cycle_count + 1,
        prune_threshold: state.prune_threshold,
        edge_prune_threshold: state.edge_prune_threshold,
        decay_rate: state.decay_rate,
        merge_similarity: state.merge_similarity
      }
    )

    Logger.info(
      "Consolidator cycle=#{state.cycle_count + 1} " <>
        "decayed=#{decayed} pruned_nodes=#{pruned_nodes} pruned_edges=#{pruned_edges} " <>
        "strengthened=#{strengthened} merged=#{merged} promoted=#{promoted} " <>
        "abstracted=#{abstracted} errors=#{node_errors + edge_errors} duration_ms=#{duration_ms}"
    )

    state
    |> Map.put(:cycle_count, state.cycle_count + 1)
    |> Map.put(:last_run_at, DateTime.utc_now())
    |> schedule_next()
  end

  defp load_graph_data do
    nodes =
      case Graph.list_nodes(%{}) do
        {:ok, n} when is_list(n) -> n
        _ -> []
      end

    edges =
      case Graph.list_all_edges() do
        {:ok, e} when is_list(e) -> e
        _ -> []
      end

    {nodes, edges}
  end

  ## Stage 1 & 2: Decay confidence + prune weak nodes

  defp stage_decay_and_prune_nodes(nodes, decay_rate, prune_threshold) do
    Enum.reduce(nodes, {0, 0, 0}, fn node, {d, p, e} ->
      case process_node(node, decay_rate, prune_threshold) do
        :decayed -> {d + 1, p, e}
        :pruned -> {d, p + 1, e}
        :unchanged -> {d, p, e}
        :error -> {d, p, e + 1}
      end
    end)
  end

  defp process_node(node, decay_rate, prune_threshold) do
    node_id = Map.get(node, :id)
    old_conf = node |> Map.get(:confidence, 0.5) |> normalize_probability()
    # Use per-node decay_rate if set, otherwise global
    effective_decay = Map.get(node, :decay_rate) || decay_rate
    new_conf = clamp(old_conf * (1.0 - effective_decay), 0.0, 1.0)

    cond do
      not is_binary(node_id) ->
        :error

      new_conf < prune_threshold ->
        case Graph.delete_node(node_id) do
          :ok ->
            :telemetry.execute(
              [:graphonomous, :node, :pruned],
              %{old_confidence: old_conf, new_confidence: new_conf},
              %{node_id: node_id, threshold: prune_threshold}
            )

            :pruned

          {:error, _reason} ->
            :error
        end

      abs(new_conf - old_conf) <= 1.0e-12 ->
        :unchanged

      true ->
        case Graph.update_node(node_id, %{confidence: new_conf}) do
          {:ok, _updated} ->
            :telemetry.execute(
              [:graphonomous, :node, :decayed],
              %{old_confidence: old_conf, new_confidence: new_conf, delta: new_conf - old_conf},
              %{node_id: node_id}
            )

            :decayed

          {:error, _reason} ->
            :error
        end
    end
  end

  ## Stage 3: Prune weak edges

  defp stage_prune_weak_edges(edges, threshold) do
    Enum.reduce(edges, {0, 0}, fn edge, {pruned, errors} ->
      if edge.weight < threshold do
        case Graph.delete_edge(edge.id) do
          :ok ->
            :telemetry.execute(
              [:graphonomous, :edge, :pruned],
              %{weight: edge.weight},
              %{edge_id: edge.id, threshold: threshold}
            )

            {pruned + 1, errors}

          {:error, _} ->
            {pruned, errors + 1}
        end
      else
        {pruned, errors}
      end
    end)
  end

  ## Stage 4: Strengthen coactivated edges
  #
  # Boost edges between nodes that have both been accessed recently.
  # Uses co_activation_count as the signal — edges with higher co-activation
  # get a weight boost proportional to the boost rate.

  defp stage_strengthen_coactivated(edges, boost) do
    Enum.reduce(edges, 0, fn edge, count ->
      if edge.co_activation_count > 0 do
        new_weight = clamp(edge.weight + boost * edge.co_activation_count, 0.0, 1.0)

        if abs(new_weight - edge.weight) > 1.0e-12 do
          case Graph.update_edge(edge.id, %{
                 weight: new_weight,
                 co_activation_count: 0
               }) do
            {:ok, _} ->
              :telemetry.execute(
                [:graphonomous, :edge, :strengthened],
                %{old_weight: edge.weight, new_weight: new_weight},
                %{edge_id: edge.id, co_activation_count: edge.co_activation_count}
              )

              count + 1

            {:error, _} ->
              count
          end
        else
          count
        end
      else
        count
      end
    end)
  end

  ## Stage 5: Merge similar nodes
  #
  # Find pairs of nodes with embedding cosine similarity > threshold.
  # Merge the lower-confidence node into the higher-confidence one:
  # - Combine content
  # - Keep the higher confidence
  # - Re-point edges from the merged node to the survivor
  # - Delete the merged node

  defp stage_merge_similar_nodes(similarity_threshold) do
    case Graph.list_nodes(%{}) do
      {:ok, nodes} when is_list(nodes) ->
        # Build candidate pairs from nodes that have embeddings
        nodes_with_embeddings =
          nodes
          |> Enum.filter(&(not is_nil(&1.embedding) and &1.embedding != <<>>))
          |> Enum.map(fn node ->
            {node, Graph.decode_embedding_blob(node.embedding)}
          end)
          |> Enum.filter(fn {_node, vec} -> vec != [] end)

        merge_pairs(nodes_with_embeddings, similarity_threshold, MapSet.new(), 0)

      _ ->
        0
    end
  end

  defp merge_pairs([], _threshold, _merged_ids, count), do: count

  defp merge_pairs([{node_a, vec_a} | rest], threshold, merged_ids, count) do
    if MapSet.member?(merged_ids, node_a.id) do
      merge_pairs(rest, threshold, merged_ids, count)
    else
      case find_merge_candidate(node_a, vec_a, rest, threshold, merged_ids) do
        nil ->
          merge_pairs(rest, threshold, merged_ids, count)

        {node_b, _vec_b} ->
          {survivor, victim} =
            if node_a.confidence >= node_b.confidence,
              do: {node_a, node_b},
              else: {node_b, node_a}

          case do_merge(survivor, victim) do
            :ok ->
              :telemetry.execute(
                [:graphonomous, :node, :merged],
                %{},
                %{survivor_id: survivor.id, victim_id: victim.id}
              )

              new_merged = merged_ids |> MapSet.put(victim.id)
              merge_pairs(rest, threshold, new_merged, count + 1)

            :error ->
              merge_pairs(rest, threshold, merged_ids, count)
          end
      end
    end
  end

  defp find_merge_candidate(_node_a, _vec_a, [], _threshold, _merged_ids), do: nil

  defp find_merge_candidate(node_a, vec_a, [{node_b, vec_b} | rest], threshold, merged_ids) do
    if MapSet.member?(merged_ids, node_b.id) or node_a.node_type != node_b.node_type do
      find_merge_candidate(node_a, vec_a, rest, threshold, merged_ids)
    else
      sim = Graph.cosine_similarity(vec_a, vec_b)

      if sim >= threshold do
        {node_b, vec_b}
      else
        find_merge_candidate(node_a, vec_a, rest, threshold, merged_ids)
      end
    end
  end

  defp do_merge(survivor, victim) do
    merged_content =
      survivor.content <>
        "\n\n[Merged from #{victim.id}]: " <> (victim.content || "")

    merged_causal_ids =
      Enum.uniq((survivor.causal_parent_ids || []) ++ (victim.causal_parent_ids || []))

    # Update survivor with combined content
    case Graph.update_node(survivor.id, %{
           content: merged_content,
           causal_parent_ids: merged_causal_ids,
           creation_source: :consolidation
         }) do
      {:ok, _} ->
        # Re-point victim's edges to survivor
        repoint_edges(victim.id, survivor.id)
        # Delete victim
        Graph.delete_node(victim.id)
        :ok

      {:error, _} ->
        :error
    end
  end

  defp repoint_edges(old_node_id, new_node_id) do
    case Graph.get_edges_for_node(old_node_id) do
      {:ok, edges} ->
        Enum.each(edges, fn edge ->
          new_source = if edge.source_id == old_node_id, do: new_node_id, else: edge.source_id
          new_target = if edge.target_id == old_node_id, do: new_node_id, else: edge.target_id

          # Skip self-loops
          if new_source != new_target do
            Graph.create_edge(%{
              source_id: new_source,
              target_id: new_target,
              edge_type: edge.edge_type,
              weight: edge.weight,
              metadata: edge.metadata,
              co_activation_count: edge.co_activation_count,
              decay_rate: edge.decay_rate
            })
          end

          Graph.delete_edge(edge.id)
        end)

      _ ->
        :ok
    end
  end

  ## Stage 6: Promote timescale
  #
  # Nodes that have been accessed many times and are in :fast timescale
  # get promoted to :medium; :medium with high access → :slow.

  defp stage_promote_timescale(access_threshold) do
    case Graph.list_nodes(%{}) do
      {:ok, nodes} when is_list(nodes) ->
        Enum.reduce(nodes, 0, fn node, count ->
          new_timescale = promotion_target(node.timescale, node.access_count, access_threshold)

          if new_timescale != node.timescale do
            case Graph.update_node(node.id, %{timescale: new_timescale}) do
              {:ok, _} ->
                :telemetry.execute(
                  [:graphonomous, :node, :promoted],
                  %{access_count: node.access_count},
                  %{
                    node_id: node.id,
                    from: node.timescale,
                    to: new_timescale
                  }
                )

                count + 1

              {:error, _} ->
                count
            end
          else
            count
          end
        end)

      _ ->
        0
    end
  end

  defp promotion_target(:fast, access_count, threshold) when access_count >= threshold,
    do: :medium

  defp promotion_target(:medium, access_count, threshold) when access_count >= threshold * 3,
    do: :slow

  defp promotion_target(:slow, access_count, threshold) when access_count >= threshold * 10,
    do: :glacial

  defp promotion_target(current, _access_count, _threshold), do: current

  ## Stage 7: Generate abstractions
  #
  # Find clusters of 3+ episodic nodes from the same source domain that share
  # edges. Create a semantic summary node that captures the common pattern.
  # This is conservative — only creates abstractions for obvious clusters.

  defp stage_generate_abstractions do
    case Graph.list_nodes(%{node_type: :episodic}) do
      {:ok, episodic_nodes} when length(episodic_nodes) >= 3 ->
        # Group by source domain
        groups =
          episodic_nodes
          |> Enum.filter(&(not is_nil(&1.source)))
          |> Enum.group_by(fn node ->
            node.source
            |> String.split("/")
            |> Enum.take(2)
            |> Enum.join("/")
          end)

        Enum.reduce(groups, 0, fn {domain, nodes}, count ->
          if length(nodes) >= 3 do
            case maybe_create_abstraction(domain, nodes) do
              :created -> count + 1
              :skip -> count
            end
          else
            count
          end
        end)

      _ ->
        0
    end
  end

  defp maybe_create_abstraction(domain, nodes) do
    # Check if an abstraction already exists for this domain
    case Graph.list_nodes(%{node_type: :semantic}) do
      {:ok, semantic_nodes} ->
        abstraction_marker = "[Abstraction: #{domain}]"

        already_exists? =
          Enum.any?(semantic_nodes, fn n ->
            String.contains?(n.content || "", abstraction_marker)
          end)

        if already_exists? do
          :skip
        else
          # Create a summary node from the episodic cluster
          avg_confidence =
            nodes
            |> Enum.map(& &1.confidence)
            |> then(fn confs -> Enum.sum(confs) / length(confs) end)

          summary_content =
            abstraction_marker <>
              " Abstracted from #{length(nodes)} episodic nodes. " <>
              "Themes: " <>
              (nodes
               |> Enum.take(5)
               |> Enum.map(fn n -> String.slice(n.content || "", 0..80) end)
               |> Enum.join("; "))

          case Graph.store_node(%{
                 content: summary_content,
                 node_type: :semantic,
                 confidence: clamp(avg_confidence * 0.8, 0.1, 0.9),
                 source: domain,
                 creation_source: :consolidation,
                 timescale: :medium,
                 causal_parent_ids: Enum.map(nodes, & &1.id)
               }) do
            {:ok, abstract_node} ->
              # Link abstraction to source episodic nodes
              Enum.each(Enum.take(nodes, 5), fn source_node ->
                Graph.create_edge(source_node.id, abstract_node.id, %{
                  edge_type: :derived_from,
                  weight: 0.6
                })
              end)

              :telemetry.execute(
                [:graphonomous, :node, :abstracted],
                %{source_count: length(nodes), confidence: avg_confidence},
                %{node_id: abstract_node.id, domain: domain}
              )

              :created

            {:error, _} ->
              :skip
          end
        end

      _ ->
        :skip
    end
  end

  ## Timer helpers

  defp schedule_next(state) do
    cancel_timer(state.timer_ref)
    ref = Process.send_after(self(), :tick, state.interval_ms)
    %{state | timer_ref: ref}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref, async: true, info: false)

  ## Normalization helpers

  defp normalize_interval(v) when is_integer(v), do: max(v, @min_interval_ms)
  defp normalize_interval(_), do: @default_interval_ms

  defp normalize_probability(v) when is_float(v), do: clamp(v, 0.0, 1.0)
  defp normalize_probability(v) when is_integer(v), do: normalize_probability(v * 1.0)

  defp normalize_probability(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> normalize_probability(f)
      :error -> 0.5
    end
  end

  defp normalize_probability(_), do: 0.5

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end
