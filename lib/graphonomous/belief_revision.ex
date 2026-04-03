defmodule Graphonomous.BeliefRevision do
  @moduledoc """
  AGM-rational belief revision operations with provenance tracking.

  Provides the storage/provenance substrate for belief management:
  - **expansion** — add a new belief, checking for contradictions first
  - **revision** — supersede an old belief with new content, propagate confidence
  - **contraction** — remove a belief, retract dependents

  Reasoning about which belief wins in a contradiction is delegated to
  external systems (Deliberatic, BendScript) via pluggable resolution hooks.
  When no hook is registered, a default heuristic (recency + evidence count) is used.

  Emits telemetry:
  - `[:graphonomous, :belief, :expanded]`
  - `[:graphonomous, :belief, :revised]`
  - `[:graphonomous, :belief, :contracted]`
  - `[:graphonomous, :belief, :contradiction_detected]`
  """

  require Logger

  alias Graphonomous.{Graph, Store}
  alias Graphonomous.Types.Node

  @contradiction_similarity_threshold 0.75
  @retraction_decay_factor 0.6

  # ---- Resolution hooks ----

  @doc """
  Register a module as the external contradiction resolver.
  The module must implement `resolve(node_a, node_b) :: {:ok, :keep_a | :keep_b | :keep_both} | {:error, term()}`.
  """
  @spec register_resolution_hook(module()) :: :ok
  def register_resolution_hook(module) when is_atom(module) do
    :persistent_term.put({__MODULE__, :resolution_hook}, module)
    :ok
  end

  @spec get_resolution_hook() :: module() | nil
  def get_resolution_hook do
    :persistent_term.get({__MODULE__, :resolution_hook}, nil)
  rescue
    ArgumentError -> nil
  end

  # ---- Core operations ----

  @doc """
  Expand the knowledge base with new content.

  Stores the node and checks for contradictions. If contradictions are found,
  creates `:contradicts` edges (forming 2-node SCCs = κ=1).

  Returns `{:ok, %{node_id, contradictions, revision_id}}`.
  """
  @spec expand(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def expand(content, opts \\ []) when is_binary(content) do
    node_type = Keyword.get(opts, :node_type, :semantic)
    confidence = Keyword.get(opts, :confidence, 0.6)
    source = Keyword.get(opts, :source, "belief_revision")
    agent_id = Keyword.get(opts, :agent_id, nil)
    metadata = Keyword.get(opts, :metadata, %{})

    # Store the new belief
    case Graph.store_node(%{
           content: content,
           node_type: node_type,
           confidence: confidence,
           source: source,
           metadata: Map.put(metadata, "belief_operation", "expansion")
         }) do
      {:ok, %Node{} = node} ->
        # Detect contradictions with existing knowledge
        contradictions = detect_contradictions(content, node.id)

        # Create :contradicts edges for any contradictions found
        contradiction_edges =
          Enum.reduce(contradictions, 0, fn %{node_id: contra_id}, acc ->
            create_contradiction_edges(node.id, contra_id)
            acc + 1
          end)

        # Record the revision
        {:ok, revision} =
          Store.insert_revision(%{
            operation: "expansion",
            trigger_node_id: node.id,
            affected_node_ids: Enum.map(contradictions, & &1.node_id),
            rationale: "Expanded knowledge base with new belief",
            agent_id: agent_id
          })

        # Update the node with revision_id
        _ = Store.update_node(node.id, %{revision_id: revision.id})

        :telemetry.execute(
          [:graphonomous, :belief, :expanded],
          %{contradictions_found: length(contradictions), edges_created: contradiction_edges},
          %{node_id: node.id, revision_id: revision.id}
        )

        {:ok,
         %{
           node_id: node.id,
           contradictions: contradictions,
           contradiction_edges: contradiction_edges,
           revision_id: revision.id
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Revise an existing belief with new content.

  Supersedes the old node: marks it with `superseded_by`, creates a
  `:superseded_by` edge, and propagates confidence reduction to dependents.
  """
  @spec revise(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def revise(node_id, new_content, opts \\ [])
      when is_binary(node_id) and is_binary(new_content) do
    rationale = Keyword.get(opts, :rationale, nil)
    agent_id = Keyword.get(opts, :agent_id, nil)
    confidence = Keyword.get(opts, :confidence, nil)

    case Store.get_node(node_id) do
      {:ok, %Node{} = old_node} ->
        # Create the replacement node
        new_confidence = confidence || min(old_node.confidence + 0.1, 0.9)

        case Graph.store_node(%{
               content: new_content,
               node_type: old_node.node_type,
               confidence: new_confidence,
               source: old_node.source || "belief_revision",
               metadata:
                 Map.merge(old_node.metadata || %{}, %{
                   "belief_operation" => "revision",
                   "supersedes" => node_id
                 })
             }) do
          {:ok, %Node{} = new_node} ->
            # Mark old node as superseded
            _ =
              Store.update_node(node_id, %{
                superseded_by: new_node.id,
                confidence: old_node.confidence * 0.3
              })

            # Create superseded_by edge
            _ =
              Graph.create_edge(node_id, new_node.id, %{
                edge_type: :superseded_by,
                weight: 0.9
              })

            # Propagate confidence reduction to dependents of old node
            affected = propagate_retraction(node_id)

            # Record revision
            {:ok, revision} =
              Store.insert_revision(%{
                operation: "revision",
                trigger_node_id: node_id,
                affected_node_ids: [new_node.id | affected],
                rationale: rationale || "Belief revised with new content",
                agent_id: agent_id
              })

            _ = Store.update_node(new_node.id, %{revision_id: revision.id})

            :telemetry.execute(
              [:graphonomous, :belief, :revised],
              %{affected_count: length(affected)},
              %{
                old_node_id: node_id,
                new_node_id: new_node.id,
                revision_id: revision.id
              }
            )

            {:ok,
             %{
               old_node_id: node_id,
               new_node_id: new_node.id,
               affected_node_ids: affected,
               revision_id: revision.id
             }}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Contract a belief from the knowledge base.

  Reduces the node's confidence significantly and propagates retraction
  to dependent nodes.
  """
  @spec contract(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def contract(node_id, opts \\ []) when is_binary(node_id) do
    rationale = Keyword.get(opts, :rationale, nil)
    agent_id = Keyword.get(opts, :agent_id, nil)

    case Store.get_node(node_id) do
      {:ok, %Node{} = node} ->
        # Reduce confidence to near-zero (consolidator will prune eventually)
        _ = Store.update_node(node_id, %{confidence: 0.05})

        # Propagate retraction
        affected = propagate_retraction(node_id)

        # Record contraction
        {:ok, revision} =
          Store.insert_revision(%{
            operation: "contraction",
            trigger_node_id: node_id,
            affected_node_ids: affected,
            rationale: rationale || "Belief contracted",
            agent_id: agent_id
          })

        _ = Store.update_node(node_id, %{revision_id: revision.id})

        :telemetry.execute(
          [:graphonomous, :belief, :contracted],
          %{affected_count: length(affected), old_confidence: node.confidence},
          %{node_id: node_id, revision_id: revision.id}
        )

        {:ok,
         %{
           node_id: node_id,
           affected_node_ids: affected,
           revision_id: revision.id
         }}

      {:error, _} = err ->
        err
    end
  end

  # ---- Contradiction detection ----

  @doc """
  Detect nodes that potentially contradict the given content or node.

  Uses embedding cosine similarity to find semantically close nodes,
  then checks for confidence divergence as a signal of contradiction.
  """
  @spec detect_contradictions(String.t(), String.t() | nil) :: [map()]
  def detect_contradictions(content, exclude_node_id \\ nil) when is_binary(content) do
    case Graph.retrieve_similar(content, limit: 20) do
      {:ok, hits} ->
        hits
        |> Enum.filter(fn hit ->
          sim = Map.get(hit, :similarity, 0.0)
          node_id = Map.get(hit, :node_id)
          node_confidence = Map.get(hit, :confidence, 0.5)

          is_binary(node_id) and
            node_id != exclude_node_id and
            sim >= @contradiction_similarity_threshold and
            might_contradict?(content, Map.get(hit, :content, ""), node_confidence)
        end)
        |> Enum.map(fn hit ->
          %{
            node_id: Map.get(hit, :node_id),
            similarity: Map.get(hit, :similarity, 0.0),
            confidence: Map.get(hit, :confidence, 0.5),
            content_preview: String.slice(Map.get(hit, :content, ""), 0..200)
          }
        end)
        |> Enum.take(5)

      {:error, _} ->
        []
    end
  end

  @doc """
  Detect contradictions for an existing node by ID.
  """
  @spec detect_contradictions_for_node(String.t()) :: [map()]
  def detect_contradictions_for_node(node_id) when is_binary(node_id) do
    case Store.get_node(node_id) do
      {:ok, %Node{content: content}} when is_binary(content) ->
        detect_contradictions(content, node_id)

      _ ->
        []
    end
  end

  # ---- Confidence propagation ----

  @doc """
  Propagate confidence reduction through `:derived_from`, `:supports`, and `:causal` edges
  from the given node. Returns list of affected node IDs.
  """
  @spec propagate_retraction(String.t()) :: [String.t()]
  def propagate_retraction(node_id) when is_binary(node_id) do
    propagation_types = [:derived_from, :supports, :causal, :causes]

    case Graph.get_edges_for_node(node_id) do
      {:ok, edges} ->
        edges
        |> Enum.filter(fn edge ->
          edge.source_id == node_id and edge.edge_type in propagation_types
        end)
        |> Enum.flat_map(fn edge ->
          target_id = edge.target_id

          case Store.get_node(target_id) do
            {:ok, %Node{} = target_node} ->
              new_conf = max(target_node.confidence * @retraction_decay_factor, 0.05)

              if abs(new_conf - target_node.confidence) > 0.01 do
                _ = Store.update_node(target_id, %{confidence: new_conf})
                [target_id]
              else
                []
              end

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  end

  # ---- Contradiction resolution ----

  @doc """
  Attempt to resolve a contradiction between two nodes.

  Uses registered hook if available, otherwise falls back to default heuristic
  (recency + outcome evidence count).
  """
  @spec resolve_contradiction(String.t(), String.t()) ::
          {:ok, :keep_a | :keep_b | :keep_both | :unresolved} | {:error, term()}
  def resolve_contradiction(node_a_id, node_b_id)
      when is_binary(node_a_id) and is_binary(node_b_id) do
    with {:ok, %Node{} = node_a} <- Store.get_node(node_a_id),
         {:ok, %Node{} = node_b} <- Store.get_node(node_b_id) do
      case get_resolution_hook() do
        nil ->
          default_resolve(node_a, node_b)

        hook_module ->
          try do
            hook_module.resolve(node_a, node_b)
          rescue
            _ -> default_resolve(node_a, node_b)
          end
      end
    end
  end

  # ---- Private helpers ----

  defp might_contradict?(new_content, existing_content, existing_confidence) do
    # Heuristic: high similarity + presence of negation/update markers suggests contradiction.
    # Also flag confidence divergence (one high, one low) as potential conflict signal.
    has_negation_markers?(new_content, existing_content) or
      existing_confidence > 0.7
  end

  defp has_negation_markers?(new, existing) do
    new_lower = String.downcase(new)
    existing_lower = String.downcase(existing)

    negation_words = ["not", "no longer", "incorrect", "wrong", "false", "deprecated",
                       "outdated", "replaced", "instead", "actually", "contrary",
                       "however", "but", "although"]

    Enum.any?(negation_words, fn word ->
      String.contains?(new_lower, word) or String.contains?(existing_lower, word)
    end)
  end

  defp default_resolve(node_a, node_b) do
    # Heuristic: prefer newer node with more outcome evidence
    a_score = resolution_score(node_a)
    b_score = resolution_score(node_b)

    cond do
      abs(a_score - b_score) < 0.1 -> {:ok, :unresolved}
      a_score > b_score -> {:ok, :keep_a}
      true -> {:ok, :keep_b}
    end
  end

  defp resolution_score(%Node{} = node) do
    meta = node.metadata || %{}
    feedback_count = Map.get(meta, "feedback_count", 0)
    feedback_count = if is_integer(feedback_count), do: feedback_count, else: 0

    recency_bonus =
      case node.updated_at do
        %DateTime{} = dt ->
          hours_ago = DateTime.diff(DateTime.utc_now(), dt, :hour)
          max(1.0 - hours_ago / 720.0, 0.0)

        _ ->
          0.0
      end

    node.confidence * 0.4 + recency_bonus * 0.3 + min(feedback_count / 5.0, 1.0) * 0.3
  end

  defp create_contradiction_edges(node_a_id, node_b_id) do
    # Create bidirectional :contradicts edges — forms a 2-node SCC = κ=1
    _ =
      Graph.create_edge(node_a_id, node_b_id, %{
        edge_type: :contradicts,
        weight: 0.8,
        metadata: %{"source" => "belief_revision", "automated" => true}
      })

    _ =
      Graph.create_edge(node_b_id, node_a_id, %{
        edge_type: :contradicts,
        weight: 0.8,
        metadata: %{"source" => "belief_revision", "automated" => true}
      })

    :telemetry.execute(
      [:graphonomous, :belief, :contradiction_detected],
      %{},
      %{node_a: node_a_id, node_b: node_b_id}
    )

    :ok
  end
end
