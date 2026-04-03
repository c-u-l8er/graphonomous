defmodule Graphonomous.MCP.RetrieveProcedural do
  @moduledoc """
  MCP tool for retrieving how-to / procedural knowledge.

  Performs semantic search scoped to procedural nodes, returning
  ranked results relevant to a given task description.

  P2: Supports optional precondition matching — when `preconditions` is provided,
  nodes whose skill metadata preconditions match get a score boost.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:task, :string,
      required: true,
      description: "Natural-language description of the task to find procedures for"
    )

    field(:preconditions, :string,
      description: "JSON array of required precondition strings (optional)"
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
      preconditions = parse_preconditions(p(params, :preconditions))

      case do_retrieve_procedural(task, limit, preconditions) do
        {:ok, result} ->
          {:reply, ok_response(result), frame}

        {:error, reason} ->
          {:reply, error_response(inspect(reason)), frame}
      end
    end
  end

  defp do_retrieve_procedural(task, limit, preconditions) do
    retrieval =
      Graphonomous.retrieve_context(task,
        limit: limit * 2,
        expansion_hops: 1,
        neighbors_per_node: 3
      )

    case retrieval do
      %{results: results} when is_list(results) ->
        procedures =
          results
          |> Enum.filter(fn r ->
            node_type =
              (Map.get(r, :node_type) || "")
              |> to_string()
              |> String.downcase()

            node_type == "procedural"
          end)
          |> maybe_boost_by_preconditions(preconditions)
          |> Enum.take(limit)

        steps =
          procedures
          |> Enum.flat_map(&extract_steps/1)
          |> Enum.take(20)

        {:ok,
         %{
           task: task,
           count: length(procedures),
           preconditions_filter: preconditions,
           procedures:
             Enum.map(procedures, fn r ->
               skill_meta = get_skill_metadata(r)

               %{
                 node_id: Map.get(r, :node_id),
                 content: Map.get(r, :content),
                 confidence: Map.get(r, :confidence),
                 similarity: Map.get(r, :similarity),
                 score: Map.get(r, :score),
                 skill: skill_meta
               }
             end),
           steps: steps
         }}

      %{} ->
        fallback_procedural(task, limit)

      {:error, _} = err ->
        err
    end
  end

  # P2: Precondition matching boost
  defp maybe_boost_by_preconditions(procedures, []), do: procedures

  defp maybe_boost_by_preconditions(procedures, required_preconds) do
    procedures
    |> Enum.map(fn result ->
      node_preconds = get_node_preconditions(result)
      match_score = precondition_match_score(required_preconds, node_preconds)
      score = Map.get(result, :score, 0.0) || 0.0
      %{result | score: score * (1.0 + match_score)}
    end)
    |> Enum.sort_by(&Map.get(&1, :score, 0.0), :desc)
  end

  defp precondition_match_score([], _available), do: 0.0
  defp precondition_match_score(_required, []), do: 0.0

  defp precondition_match_score(required, available) do
    matched = Enum.count(required, &(&1 in available))
    matched / max(length(required), 1)
  end

  defp get_node_preconditions(result) do
    node_id = Map.get(result, :node_id)

    case node_id && Graphonomous.Store.get_node(node_id) do
      {:ok, node} ->
        meta = if is_map(node.metadata), do: node.metadata, else: %{}
        get_in(meta, ["skill", "preconditions"]) || []

      _ ->
        []
    end
  end

  defp get_skill_metadata(result) do
    node_id = Map.get(result, :node_id)

    case node_id && Graphonomous.Store.get_node(node_id) do
      {:ok, node} ->
        meta = if is_map(node.metadata), do: node.metadata, else: %{}
        Map.get(meta, "skill")

      _ ->
        nil
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
           preconditions_filter: [],
           procedures:
             Enum.map(procedures, fn n ->
               %{
                 node_id: Map.get(n, :id),
                 content: Map.get(n, :content),
                 confidence: Map.get(n, :confidence),
                 similarity: nil,
                 score: nil,
                 skill: nil
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
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line ->
      Regex.match?(~r/^\d+[\.\)]\s+/, line) or
        Regex.match?(~r/^[-*]\s+/, line)
    end)
  end

  defp parse_preconditions(nil), do: []
  defp parse_preconditions(value) when is_list(value), do: Enum.filter(value, &is_binary/1)

  defp parse_preconditions(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> Enum.filter(list, &is_binary/1)
      _ -> []
    end
  end

  defp parse_preconditions(_), do: []

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
