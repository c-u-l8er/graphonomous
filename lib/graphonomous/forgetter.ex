defmodule Graphonomous.Forgetter do
  @moduledoc """
  Policy-driven intentional forgetting with governance integration.

  Two policies:
    1. **Hybrid pruning** — LRU + priority-decay. Scores each node by
       confidence × recency × access × connectivity. Lowest-priority
       nodes forgotten first when node count exceeds budget.
    2. **GDPR hard delete** — UtU-style constant-time cascade deletion.
       Severs all edges, deletes node. Audit-logged. No recovery.

  Research basis:
    - FiFA (arxiv 2512.12856): hybrid policy achieves 0.911 composite score
    - UtU (arxiv 2402.10695): constant-time graph unlearning via edge unlinking
  """

  require Logger

  alias Graphonomous.{Graph, Store}
  alias Graphonomous.Types.Node

  @type forget_mode :: :soft | :hard | :cascade
  @type forget_result :: %{
          status: :ok | :error,
          node_id: binary(),
          mode: forget_mode(),
          reason: binary() | nil
        }

  @default_max_nodes 10_000
  @default_max_age_hours 720

  ## Configuration

  @doc "Get the forgetting configuration (from forgetting_config table or defaults)."
  @spec get_config() :: map()
  def get_config do
    %{
      policy: :hybrid,
      max_nodes: @default_max_nodes,
      max_age_hours: @default_max_age_hours
    }
  end

  ## Soft forget — set forgotten_at, exclude from retrieval, keep structure

  @doc """
  Forget a node by mode.

    - `:soft` — set forgotten_at timestamp, excluded from retrieval
    - `:hard` — delete node + all edges (UtU constant-time unlink)
    - `:cascade` — hard delete + propagate to nodes whose ONLY support is this node
  """
  @spec forget(binary(), forget_mode(), keyword()) :: {:ok, forget_result()} | {:error, term()}
  def forget(node_id, mode \\ :soft, opts \\ [])

  def forget(node_id, :soft, _opts) when is_binary(node_id) do
    case Store.get_node(node_id) do
      {:ok, %Node{}} ->
        now = DateTime.utc_now()

        case Store.update_node(node_id, %{forgotten_at: now}) do
          {:ok, _} ->
            Logger.info("Forgetter: soft-forgot node #{node_id}")

            :telemetry.execute(
              [:graphonomous, :forgetter, :forgot],
              %{count: 1},
              %{node_id: node_id, mode: :soft}
            )

            {:ok, %{status: :ok, node_id: node_id, mode: :soft, reason: nil}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def forget(node_id, :hard, _opts) when is_binary(node_id) do
    case Store.get_node(node_id) do
      {:ok, %Node{}} ->
        # UtU-style: sever all edges first, then delete node
        sever_all_edges(node_id)

        case Graph.delete_node(node_id) do
          :ok ->
            Logger.info("Forgetter: hard-deleted node #{node_id}")

            :telemetry.execute(
              [:graphonomous, :forgetter, :forgot],
              %{count: 1},
              %{node_id: node_id, mode: :hard}
            )

            {:ok, %{status: :ok, node_id: node_id, mode: :hard, reason: nil}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def forget(node_id, :cascade, _opts) when is_binary(node_id) do
    case Store.get_node(node_id) do
      {:ok, %Node{}} ->
        # Find nodes that depend ONLY on this node
        orphan_ids = find_orphan_dependents(node_id)

        # Hard delete the primary node
        sever_all_edges(node_id)
        Graph.delete_node(node_id)

        # Cascade to orphaned dependents
        cascade_count =
          Enum.reduce(orphan_ids, 0, fn oid, count ->
            sever_all_edges(oid)

            case Graph.delete_node(oid) do
              :ok -> count + 1
              _ -> count
            end
          end)

        total = 1 + cascade_count

        Logger.info(
          "Forgetter: cascade-deleted node #{node_id} + #{cascade_count} orphaned dependents"
        )

        :telemetry.execute(
          [:graphonomous, :forgetter, :forgot],
          %{count: total},
          %{node_id: node_id, mode: :cascade}
        )

        {:ok,
         %{status: :ok, node_id: node_id, mode: :cascade, reason: "cascaded #{cascade_count}"}}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  ## Budget-aware hybrid policy

  @doc """
  Run the hybrid forgetting policy. Scores all nodes by priority,
  forgets lowest-priority nodes until under max_nodes.

  Returns `{:ok, %{forgotten_count: n, surviving_count: m}}`.
  """
  @spec forget_by_policy(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def forget_by_policy(policy \\ :hybrid, opts \\ [])

  def forget_by_policy(:hybrid, opts) do
    max_nodes = Keyword.get(opts, :max_nodes, @default_max_nodes)
    dry_run = Keyword.get(opts, :dry_run, false)

    case Graph.list_nodes(%{}) do
      {:ok, nodes} ->
        # Only consider active (non-forgotten) nodes
        active_nodes = Enum.filter(nodes, &is_nil(&1.forgotten_at))
        count = length(active_nodes)

        if count <= max_nodes do
          {:ok, %{forgotten_count: 0, surviving_count: count}}
        else
          to_forget_count = count - max_nodes

          candidates =
            active_nodes
            |> Enum.map(fn node -> {node, priority_score(node)} end)
            |> Enum.sort_by(fn {_node, score} -> score end, :asc)
            |> Enum.take(to_forget_count)

          if dry_run do
            {:ok,
             %{
               forgotten_count: 0,
               would_forget: length(candidates),
               surviving_count: count,
               candidates:
                 Enum.map(candidates, fn {node, score} ->
                   %{node_id: node.id, priority_score: score}
                 end)
             }}
          else
            forgotten =
              Enum.reduce(candidates, 0, fn {node, _score}, acc ->
                case forget(node.id, :soft) do
                  {:ok, _} -> acc + 1
                  _ -> acc
                end
              end)

            {:ok, %{forgotten_count: forgotten, surviving_count: count - forgotten}}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## GDPR hard erase — no recovery, audit-logged

  @doc """
  GDPR erase: hard delete with audit record. No recovery.
  Removes node, all edges, and embedding data completely.
  """
  @spec gdpr_erase(binary()) :: {:ok, map()} | {:error, term()}
  def gdpr_erase(node_id) when is_binary(node_id) do
    case Store.get_node(node_id) do
      {:ok, %Node{} = node} ->
        # Record audit entry before deletion
        audit = %{
          node_id: node_id,
          node_type: node.node_type,
          erased_at: DateTime.to_iso8601(DateTime.utc_now()),
          reason: "gdpr_erase"
        }

        # Hard delete — no trace
        sever_all_edges(node_id)

        case Graph.delete_node(node_id) do
          :ok ->
            Logger.warning("GDPR erase: node #{node_id} permanently deleted")

            :telemetry.execute(
              [:graphonomous, :forgetter, :gdpr_erased],
              %{count: 1},
              %{node_id: node_id}
            )

            {:ok, %{status: :erased, node_id: node_id, audit: audit}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  ## Dry run — return nodes that WOULD be forgotten

  @doc "Return candidates that would be forgotten, sorted by priority ascending."
  @spec candidates(atom(), keyword()) :: {:ok, [map()]}
  def candidates(policy \\ :hybrid, opts \\ []) do
    forget_by_policy(policy, Keyword.put(opts, :dry_run, true))
  end

  ## Priority scoring

  @doc """
  Compute priority score for a node.

  priority = confidence × recency_factor × (1 + log(access_count + 1)) × (1 + connectivity)

  Higher score = higher priority = less likely to be forgotten.
  """
  @spec priority_score(Node.t() | map()) :: float()
  def priority_score(node) do
    confidence = Map.get(node, :confidence, 0.5)
    recency = recency_factor(node)
    access = 1.0 + :math.log(max(Map.get(node, :access_count, 0), 0) + 1)
    connectivity = connectivity_factor(node)

    confidence * recency * access * (1.0 + connectivity)
  end

  ## Internal helpers

  defp recency_factor(node) do
    case Map.get(node, :last_accessed_at) do
      %DateTime{} = accessed_at ->
        hours_ago = DateTime.diff(DateTime.utc_now(), accessed_at, :second) / 3600.0
        # Decay to near-0 over 30 days (720 hours)
        max(:math.exp(-hours_ago / 360.0), 0.01)

      _ ->
        0.5
    end
  end

  defp connectivity_factor(node) do
    node_id = Map.get(node, :id)

    if is_binary(node_id) do
      case Graph.get_edges_for_node(node_id) do
        {:ok, edges} -> min(length(edges) / 10.0, 1.0)
        _ -> 0.0
      end
    else
      0.0
    end
  end

  defp sever_all_edges(node_id) do
    case Graph.get_edges_for_node(node_id) do
      {:ok, edges} ->
        Enum.each(edges, fn edge ->
          Graph.delete_edge(edge.id)
        end)

      _ ->
        :ok
    end
  end

  defp find_orphan_dependents(node_id) do
    case Graph.get_edges_for_node(node_id) do
      {:ok, edges} ->
        # Find nodes that this node points TO
        dependent_ids =
          edges
          |> Enum.filter(&(&1.source_id == node_id))
          |> Enum.map(& &1.target_id)
          |> Enum.uniq()

        # Check if each dependent has other support
        Enum.filter(dependent_ids, fn dep_id ->
          case Graph.get_edges_for_node(dep_id) do
            {:ok, dep_edges} ->
              # Count incoming edges NOT from the node being deleted
              incoming =
                Enum.count(dep_edges, fn e ->
                  e.target_id == dep_id and e.source_id != node_id
                end)

              incoming == 0

            _ ->
              false
          end
        end)

      _ ->
        []
    end
  end
end
