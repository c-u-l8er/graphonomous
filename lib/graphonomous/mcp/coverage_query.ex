defmodule Graphonomous.MCP.CoverageQuery do
  @moduledoc """
  MCP tool for standalone epistemic coverage assessment.

  Evaluates whether the knowledge graph adequately covers a proposed task
  without requiring a goal binding. Returns coverage score, knowledge gaps,
  and an act/learn/escalate recommendation.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:task_description, :string,
      required: true,
      description: "Natural-language description of the task to assess coverage for"
    )

    field(:critical_topics, :string,
      description: "JSON array of critical topic strings that must be covered"
    )

    field(:min_confidence, :number,
      description: "Minimum confidence threshold for relevant nodes (default: 0.3)"
    )

    field(:top_k, :number, description: "Max retrieval results to evaluate (default: 10)")
  end

  @default_min_confidence 0.3
  @default_top_k 10

  @impl true
  def execute(params, frame) do
    task = p(params, :task_description)

    if not is_binary(task) or String.trim(task) == "" do
      {:reply, error_response("task_description is required"), frame}
    else
      top_k = p(params, :top_k, @default_top_k) |> parse_pos_int(@default_top_k)

      min_confidence =
        p(params, :min_confidence, @default_min_confidence)
        |> parse_float(@default_min_confidence)
        |> clamp(0.0, 1.0)

      critical_topics = parse_string_list(p(params, :critical_topics))

      case do_coverage_query(task, top_k, min_confidence, critical_topics) do
        {:ok, result} ->
          {:reply, ok_response(result), frame}

        {:error, reason} ->
          {:reply, error_response(inspect(reason)), frame}
      end
    end
  end

  defp do_coverage_query(task, top_k, min_confidence, critical_topics) do
    # Retrieve relevant context for the task
    retrieval =
      Graphonomous.retrieve_context(task, limit: top_k, expansion_hops: 1, neighbors_per_node: 5)

    case retrieval do
      %{results: results} = _ret when is_list(results) ->
        # Filter by min_confidence
        relevant =
          Enum.filter(results, fn r ->
            conf = Map.get(r, :confidence, 0.0)
            is_number(conf) and conf >= min_confidence
          end)

        # Build coverage signal
        signal = %{
          retrieved_nodes: relevant,
          outcomes: [],
          contradictions: 0,
          graph_support: length(relevant)
        }

        # Evaluate coverage
        evaluation = Graphonomous.evaluate_coverage(signal, top_k: top_k)

        # Find knowledge gaps from critical topics
        knowledge_gaps = find_gaps(critical_topics, relevant)

        # Build recommendation
        decision =
          case evaluation do
            %{decision: d} -> d
            _ -> :learn
          end

        {:ok,
         %{
           task_description: task,
           relevant_node_count: length(relevant),
           total_retrieved: length(results),
           coverage_score: Map.get(evaluation, :coverage_score, 0.0),
           uncertainty_score: Map.get(evaluation, :uncertainty_score, 1.0),
           risk_score: Map.get(evaluation, :risk_score, 0.0),
           decision_confidence: Map.get(evaluation, :decision_confidence, 0.0),
           recommendation: to_string(decision),
           knowledge_gaps: knowledge_gaps,
           rationale: Map.get(evaluation, :rationale, []),
           relevant_nodes:
             Enum.map(relevant, fn r ->
               %{
                 node_id: Map.get(r, :node_id),
                 content: Map.get(r, :content),
                 node_type: Map.get(r, :node_type),
                 confidence: Map.get(r, :confidence),
                 score: Map.get(r, :score)
               }
             end)
         }}

      %{} = ret ->
        # No results key — try to work with what we have
        results = Map.get(ret, :results, [])
        do_coverage_query_from_results(task, results, min_confidence, critical_topics, top_k)

      {:error, _} = err ->
        err
    end
  end

  defp do_coverage_query_from_results(task, results, min_confidence, critical_topics, top_k) do
    relevant =
      Enum.filter(results, fn r ->
        conf = Map.get(r, :confidence, 0.0)
        is_number(conf) and conf >= min_confidence
      end)

    signal = %{
      retrieved_nodes: relevant,
      outcomes: [],
      contradictions: 0,
      graph_support: length(relevant)
    }

    evaluation = Graphonomous.evaluate_coverage(signal, top_k: top_k)
    knowledge_gaps = find_gaps(critical_topics, relevant)

    decision =
      case evaluation do
        %{decision: d} -> d
        _ -> :learn
      end

    {:ok,
     %{
       task_description: task,
       relevant_node_count: length(relevant),
       total_retrieved: length(results),
       coverage_score: Map.get(evaluation, :coverage_score, 0.0),
       uncertainty_score: Map.get(evaluation, :uncertainty_score, 1.0),
       risk_score: Map.get(evaluation, :risk_score, 0.0),
       decision_confidence: Map.get(evaluation, :decision_confidence, 0.0),
       recommendation: to_string(decision),
       knowledge_gaps: knowledge_gaps,
       rationale: Map.get(evaluation, :rationale, []),
       relevant_nodes:
         Enum.map(relevant, fn r ->
           %{
             node_id: Map.get(r, :node_id),
             content: Map.get(r, :content),
             node_type: Map.get(r, :node_type),
             confidence: Map.get(r, :confidence),
             score: Map.get(r, :score)
           }
         end)
     }}
  end

  defp find_gaps([], _relevant), do: []

  defp find_gaps(critical_topics, relevant) when is_list(critical_topics) do
    relevant_text =
      relevant
      |> Enum.map(&(Map.get(&1, :content, "") |> to_string() |> String.downcase()))
      |> Enum.join(" ")

    Enum.filter(critical_topics, fn topic ->
      topic_lower = String.downcase(String.trim(topic))
      not String.contains?(relevant_text, topic_lower)
    end)
  end

  defp find_gaps(_, _), do: []

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

  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value * 1.0

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp parse_string_list(nil), do: []

  defp parse_string_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) ->
        list |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      _ ->
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp parse_string_list(value) when is_list(value) do
    value |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_string_list(_), do: []
end
