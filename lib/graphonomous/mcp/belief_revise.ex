defmodule Graphonomous.MCP.BeliefRevise do
  @moduledoc """
  MCP tool for AGM-rational belief revision operations.

  Supports three operations:
  - `expand` — add a new belief, checking for contradictions
  - `revise` — supersede an existing belief with new content
  - `contract` — remove a belief and retract dependents
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.BeliefRevision

  schema do
    field(:operation, :string,
      required: true,
      description: "Belief revision operation: expand, revise, or contract"
    )

    field(:content, :string,
      description: "New belief content (required for expand and revise)"
    )

    field(:node_id, :string,
      description: "Target node ID (required for revise and contract)"
    )

    field(:rationale, :string,
      description: "Reason for the revision"
    )

    field(:confidence, :number,
      description: "Confidence for new belief (0.0-1.0, default 0.6)"
    )

    field(:agent_id, :string,
      description: "Agent performing the revision"
    )
  end

  @impl true
  def execute(params, frame) do
    operation = p(params, :operation, "") |> String.trim() |> String.downcase()

    case operation do
      "expand" -> handle_expand(params, frame)
      "revise" -> handle_revise(params, frame)
      "contract" -> handle_contract(params, frame)
      _ -> {:reply, error_response("operation must be: expand, revise, or contract"), frame}
    end
  end

  defp handle_expand(params, frame) do
    case read_required_string(params, :content) do
      {:ok, content} ->
        opts = [
          confidence: read_float(params, :confidence, 0.6),
          agent_id: p(params, :agent_id),
          source: "mcp_belief_revise"
        ]

        case BeliefRevision.expand(content, opts) do
          {:ok, result} -> {:reply, ok_response(result), frame}
          {:error, reason} -> {:reply, error_response(format_reason(reason)), frame}
        end

      {:error, reason} ->
        {:reply, error_response(format_reason(reason)), frame}
    end
  end

  defp handle_revise(params, frame) do
    with {:ok, node_id} <- read_required_string(params, :node_id),
         {:ok, content} <- read_required_string(params, :content) do
      opts = [
        rationale: p(params, :rationale),
        agent_id: p(params, :agent_id),
        confidence: read_float_or_nil(params, :confidence)
      ]

      case BeliefRevision.revise(node_id, content, opts) do
        {:ok, result} -> {:reply, ok_response(result), frame}
        {:error, reason} -> {:reply, error_response(format_reason(reason)), frame}
      end
    else
      {:error, reason} -> {:reply, error_response(format_reason(reason)), frame}
    end
  end

  defp handle_contract(params, frame) do
    case read_required_string(params, :node_id) do
      {:ok, node_id} ->
        opts = [
          rationale: p(params, :rationale),
          agent_id: p(params, :agent_id)
        ]

        case BeliefRevision.contract(node_id, opts) do
          {:ok, result} -> {:reply, ok_response(result), frame}
          {:error, reason} -> {:reply, error_response(format_reason(reason)), frame}
        end

      {:error, reason} ->
        {:reply, error_response(format_reason(reason)), frame}
    end
  end

  defp ok_response(data) do
    payload = Map.put(data, :status, "ok")

    Response.tool()
    |> Response.text(Jason.encode!(payload))
  end

  defp error_response(message) do
    payload = %{status: "error", error: message}

    Response.tool()
    |> Response.text(Jason.encode!(payload))
    |> Map.put(:isError, true)
  end

  defp read_required_string(params, key) do
    case p(params, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed != "", do: {:ok, trimmed}, else: {:error, {:missing, key}}

      _ ->
        {:error, {:missing, key}}
    end
  end

  defp read_float(params, key, default) do
    case p(params, key) do
      v when is_number(v) -> max(0.0, min(v * 1.0, 1.0))
      v when is_binary(v) ->
        case Float.parse(v) do
          {f, _} -> max(0.0, min(f, 1.0))
          :error -> default
        end
      _ -> default
    end
  end

  defp read_float_or_nil(params, key) do
    case p(params, key) do
      v when is_number(v) -> max(0.0, min(v * 1.0, 1.0))
      v when is_binary(v) ->
        case Float.parse(v) do
          {f, _} -> max(0.0, min(f, 1.0))
          :error -> nil
        end
      _ -> nil
    end
  end

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp format_reason({:missing, key}), do: "#{key} is required"
  defp format_reason(:not_found), do: "node not found"
  defp format_reason(other), do: inspect(other)
end
