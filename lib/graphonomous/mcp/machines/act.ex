defmodule Graphonomous.MCP.Machines.Act do
  @moduledoc """
  Loop Phase 3: ACT — "Do it"

  Unified mutation machine for the Graphonomous memory loop.
  The agent calls this to modify the knowledge graph.

  Actions:
  - `store_node`     — store a knowledge node
  - `store_edge`     — store a relationship edge
  - `delete_node`    — remove a node
  - `manage_edge`    — CRUD on edges
  - `manage_goal`    — goal CRUD + lifecycle transitions
  - `belief_revise`  — expand/contract/replace beliefs
  - `forget_node`    — soft-hide from retrieval
  - `forget_policy`  — budget-aware priority pruning
  - `gdpr_erase`     — hard delete with audit trail

  Replaces: store_node, store_edge, delete_node, manage_edge,
            manage_goal, belief_revise, forget_node, forget_by_policy, gdpr_erase
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(
    store_node store_edge delete_node manage_edge
    manage_goal belief_revise
    forget_node forget_policy gdpr_erase
  )

  schema do
    field(:action, :string,
      required: true,
      description:
        "Mutation action: store_node | store_edge | delete_node | manage_edge | manage_goal | belief_revise | forget_node | forget_policy | gdpr_erase"
    )

    # -- store_node --
    field(:content, :string,
      description: "Knowledge content to store (store_node, belief_revise)"
    )

    field(:node_type, :string,
      description:
        "Node type: episodic, semantic, procedural, temporal, outcome, goal (store_node)"
    )

    field(:confidence, :number, description: "Confidence 0.0-1.0 (store_node)")
    field(:source, :string, description: "Source of the knowledge (store_node)")
    field(:metadata, :string, description: "JSON metadata object (store_node)")

    # -- store_edge --
    field(:source_id, :string, description: "Source node ID (store_edge, manage_edge)")
    field(:target_id, :string, description: "Target node ID (store_edge, manage_edge)")

    field(:relationship, :string,
      description:
        "Edge relationship: causal, supports, contradicts, related, derived_from (store_edge, manage_edge)"
    )

    field(:weight, :number, description: "Edge weight 0.0-1.0 (store_edge, manage_edge)")

    # -- delete_node --
    field(:node_id, :string, description: "Node ID (delete_node, forget_node, belief_revise)")

    # -- manage_edge --
    field(:edge_operation, :string,
      description: "Edge operation: create, update, delete, list (manage_edge)"
    )

    field(:edge_id, :string, description: "Edge ID for update/delete (manage_edge)")

    # -- manage_goal --
    field(:goal_operation, :string,
      description:
        "Goal operation: create_goal, get_goal, list_goals, update_goal, delete_goal, transition_goal, set_progress, link_nodes, unlink_nodes (manage_goal)"
    )

    field(:goal_id, :string, description: "Goal ID (manage_goal)")
    field(:title, :string, description: "Goal title (manage_goal create)")
    field(:description, :string, description: "Goal description (manage_goal create/update)")
    field(:status, :string, description: "Goal status for transition (manage_goal)")
    field(:progress, :number, description: "Progress 0.0-1.0 (manage_goal set_progress)")
    field(:node_ids, :array, description: "Node IDs to link/unlink (manage_goal)")

    # -- belief_revise --
    field(:revision_type, :string,
      description: "Revision: expand | contract | replace (belief_revise)"
    )

    field(:evidence, :string, description: "JSON evidence for revision (belief_revise)")

    # -- forget_policy --
    field(:policy, :string,
      description: "Forgetting policy: age_decay | low_confidence | orphan_prune (forget_policy)"
    )

    field(:budget, :number, description: "Max nodes to forget (forget_policy)")

    # -- gdpr_erase --
    field(:entity, :string, description: "Entity identifier to erase (gdpr_erase)")
    field(:reason, :string, description: "Audit reason for erasure (gdpr_erase)")
  end

  @impl true
  def execute(params, frame) do
    action = params |> p(:action) |> normalize_action()

    if action in @valid_actions do
      dispatch(action, params, frame)
    else
      {:reply,
       error_response(
         "Invalid action '#{inspect(p(params, :action))}'. Must be one of: #{Enum.join(@valid_actions, ", ")}"
       ), frame}
    end
  end

  defp dispatch("store_node", params, frame) do
    Graphonomous.MCP.StoreNode.execute(params, frame)
  end

  defp dispatch("store_edge", params, frame) do
    Graphonomous.MCP.StoreEdge.execute(params, frame)
  end

  defp dispatch("delete_node", params, frame) do
    Graphonomous.MCP.DeleteNode.execute(params, frame)
  end

  defp dispatch("manage_edge", params, frame) do
    # Map edge_operation → operation for the existing tool
    params =
      if is_binary(p(params, :edge_operation)),
        do: Map.put(params, :operation, p(params, :edge_operation)),
        else: params

    Graphonomous.MCP.ManageEdge.execute(params, frame)
  end

  defp dispatch("manage_goal", params, frame) do
    # Map goal_operation → operation for the existing tool
    params =
      if is_binary(p(params, :goal_operation)),
        do: Map.put(params, :operation, p(params, :goal_operation)),
        else: params

    Graphonomous.MCP.ManageGoal.execute(params, frame)
  end

  defp dispatch("belief_revise", params, frame) do
    Graphonomous.MCP.BeliefRevise.execute(params, frame)
  end

  defp dispatch("forget_node", params, frame) do
    Graphonomous.MCP.ForgetNode.execute(params, frame)
  end

  defp dispatch("forget_policy", params, frame) do
    Graphonomous.MCP.ForgetByPolicy.execute(params, frame)
  end

  defp dispatch("gdpr_erase", params, frame) do
    Graphonomous.MCP.GdprErase.execute(params, frame)
  end

  # -- Helpers --

  defp normalize_action(nil), do: nil
  defp normalize_action(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_action(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_action(_), do: nil

  defp error_response(message) do
    Response.tool()
    |> Response.structured(%{status: "error", error: message})
    |> Map.put(:isError, true)
  end

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
