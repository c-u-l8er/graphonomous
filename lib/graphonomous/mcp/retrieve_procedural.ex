defmodule Graphonomous.MCP.RetrieveProcedural do
  @moduledoc """
  MCP tool for retrieving how-to / procedural knowledge.

  Performs semantic search scoped to procedural nodes, returning
  ranked results relevant to a given task description.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:task, :string,
      required: true,
      description: "Natural-language description of the task to find procedures for"
    )

    field(:limit, :number, description: "Max procedures to return (default: 10)")
  end

  @default_limit 10

  @impl true
  def execute(params, frame) do
    task = p(params, :task)

    if not is_binary(task) or String.trim(task) == "" do
      {:reply, error_response("task is required"), frame}
    else
      limit = p(params, :limit, @default_limit) |> parse_pos_int(@default_limit)

      case do_retrieve_procedural(task, limit) do
        {:ok, result} ->
          {:reply, ok_response(result), frame}

        {:error, reason} ->
          {:reply, error_response(inspect(reason)), frame}
      end
    end
  end

  defp do_retrieve_procedural(task, limit) do
    # Use retrieve_context with node_type filter for procedural
    retrieval =
      Graphonomous.retrieve_context(task,
        limit: limit,
        expansion_hops: 1,
        neighbors_per_node: 3
      )

    case retrieval do
      %{results: results} when is_list(results) ->
        # Filter to procedural nodes only
        procedures =
          results
          |> Enum.filter(fn r ->
            node_type =
              (Map.get(r, :node_type) || "")
              |> to_string()
              |> String.downcase()

            node_type == "procedural"
          end)
          |> Enum.take(limit)

        # Extract step-like content if possible
        steps =
          procedures
          |> Enum.flat_map(&extract_steps/1)
          |> Enum.take(20)

        {:ok,
         %{
           task: task,
           count: length(procedures),
           procedures:
             Enum.map(procedures, fn r ->
               %{
                 node_id: Map.get(r, :node_id),
                 content: Map.get(r, :content),
                 confidence: Map.get(r, :confidence),
                 similarity: Map.get(r, :similarity),
                 score: Map.get(r, :score)
               }
             end),
           steps: steps
         }}

      %{} ->
        # Fallback: list all procedural nodes and rank by text match
        fallback_procedural(task, limit)

      {:error, _} = err ->
        err
    end
  end

  defp fallback_procedural(task, limit) do
    case Graphonomous.list_nodes(%{node_type: :procedural}) do
      nodes when is_list(nodes) ->
        procedures =
          nodes
          |> Enum.sort_by(&(-(Map.get(&1, :confidence) || 0.0)))
          |> Enum.take(limit)

        steps =
          procedures
          |> Enum.flat_map(&extract_steps_from_node/1)
          |> Enum.take(20)

        {:ok,
         %{
           task: task,
           count: length(procedures),
           procedures:
             Enum.map(procedures, fn n ->
               %{
                 node_id: Map.get(n, :id),
                 content: Map.get(n, :content),
                 confidence: Map.get(n, :confidence),
                 similarity: nil,
                 score: nil
               }
             end),
           steps: steps
         }}

      {:error, _} = err ->
        err
    end
  end

  defp extract_steps(result) do
    content = Map.get(result, :content, "") |> to_string()
    extract_numbered_steps(content)
  end

  defp extract_steps_from_node(node) do
    content = Map.get(node, :content, "") |> to_string()
    extract_numbered_steps(content)
  end

  defp extract_numbered_steps(content) do
    # Match lines starting with digits, dashes, or bullet markers
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line ->
      Regex.match?(~r/^\d+[\.\)]\s+/, line) or
        Regex.match?(~r/^[-*]\s+/, line)
    end)
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

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp parse_pos_int(value, _default) when is_integer(value) and value > 0, do: value
  defp parse_pos_int(value, _default) when is_float(value) and value > 0, do: trunc(value)

  defp parse_pos_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_pos_int(_, default), do: default
end
