defmodule Graphonomous.MCP.LearnFromInteraction do
  @moduledoc """
  MCP tool for processing a user-model interaction into knowledge graph nodes.

  Takes a user message and model response, detects novelty, extracts knowledge,
  and stores it as graph nodes with appropriate edges. This is the richest
  automated learning tool — it combines novelty detection with structured
  knowledge extraction.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @novelty_threshold 0.4
  @default_confidence 0.6

  schema do
    field(:user_message, :string,
      required: true,
      description: "The user's message/query"
    )

    field(:model_response, :string,
      required: true,
      description: "The model's response to the user"
    )

    field(:context, :string,
      description: "Optional JSON object with session context (e.g. agent_id, session_id)"
    )

    field(:extract_claims, :boolean,
      description:
        "Whether to extract individual claims as separate semantic nodes (default: true)"
    )
  end

  @impl true
  def execute(params, frame) do
    with {:ok, user_message} <- read_required_string(params, :user_message),
         {:ok, model_response} <- read_required_string(params, :model_response) do
      context = parse_json_map(p(params, :context))
      extract_claims = p(params, :extract_claims, true)

      {:ok, result} =
        learn_from_interaction(user_message, model_response, context, extract_claims)

      {:reply, ok_response(result), frame}
    else
      {:error, reason} ->
        {:reply, error_response(format_reason(reason)), frame}
    end
  end

  defp learn_from_interaction(user_message, model_response, context, extract_claims) do
    # Step 1: Check novelty of the user query
    novelty = check_novelty(user_message)

    # Step 2: Store the interaction as an episodic node
    interaction_content = build_interaction_content(user_message, model_response)

    interaction_metadata =
      Map.merge(context, %{
        "user_message_length" => String.length(user_message),
        "model_response_length" => String.length(model_response),
        "novelty_score" => novelty.novelty_score,
        "is_novel" => novelty.is_novel,
        "learned_at" => DateTime.to_iso8601(DateTime.utc_now())
      })

    episodic_node =
      Graphonomous.store_node(%{
        content: interaction_content,
        node_type: :episodic,
        confidence: @default_confidence,
        source: "learn_from_interaction",
        metadata: interaction_metadata
      })

    episodic_id = extract_node_id(episodic_node)

    # Step 3: If novel, extract and store semantic claims from the response
    {claim_nodes, edges_created} =
      if extract_claims and novelty.is_novel do
        extract_and_store_claims(model_response, episodic_id, context)
      else
        {[], 0}
      end

    # Step 4: Link to nearest existing nodes if they exist
    linking_edges =
      if episodic_id do
        link_to_nearest(episodic_id, novelty.nearest_node_ids)
      else
        0
      end

    learned_ids =
      ([episodic_id] ++ Enum.map(claim_nodes, &extract_node_id/1))
      |> Enum.filter(&is_binary/1)

    {:ok,
     %{
       is_novel: novelty.is_novel,
       novelty_score: novelty.novelty_score,
       learned_count: length(learned_ids),
       learned_node_ids: learned_ids,
       edges_created: edges_created + linking_edges,
       episodic_node_id: episodic_id,
       claim_count: length(claim_nodes)
     }}
  end

  defp check_novelty(query) do
    retrieval =
      Graphonomous.retrieve_context(query,
        limit: 5,
        expansion_hops: 0,
        neighbors_per_node: 0
      )

    results =
      case retrieval do
        %{results: r} when is_list(r) -> r
        _ -> []
      end

    max_similarity =
      case results do
        [] ->
          0.0

        nodes ->
          nodes
          |> Enum.map(&(Map.get(&1, :similarity, 0.0) || 0.0))
          |> Enum.max()
      end

    nearest_ids =
      results
      |> Enum.take(3)
      |> Enum.map(&Map.get(&1, :node_id))
      |> Enum.filter(&is_binary/1)

    %{
      is_novel: max_similarity < @novelty_threshold,
      novelty_score: Float.round(1.0 - clamp(max_similarity, 0.0, 1.0), 4),
      nearest_node_ids: nearest_ids
    }
  end

  defp build_interaction_content(user_message, model_response) do
    user_preview = String.slice(user_message, 0, 500)
    response_preview = String.slice(model_response, 0, 1000)
    "User: #{user_preview}\nAssistant: #{response_preview}"
  end

  defp extract_and_store_claims(model_response, episodic_id, context) do
    # Extract sentences that look like factual claims
    claims =
      model_response
      |> String.split(~r/[.!?]\s+/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(String.length(&1) < 20))
      |> Enum.reject(&(String.length(&1) > 500))
      |> Enum.reject(&conversational?/1)
      |> Enum.take(5)

    nodes =
      Enum.map(claims, fn claim ->
        Graphonomous.store_node(%{
          content: claim,
          node_type: :semantic,
          confidence: 0.5,
          source: "learn_from_interaction",
          metadata:
            Map.merge(context, %{
              "extracted_from" => "model_response",
              "extraction_method" => "sentence_split"
            })
        })
      end)

    # Create derived_from edges from claims to episodic node
    edges_created =
      if episodic_id do
        nodes
        |> Enum.map(&extract_node_id/1)
        |> Enum.filter(&is_binary/1)
        |> Enum.reduce(0, fn claim_id, acc ->
          case Graphonomous.link_nodes(claim_id, episodic_id, %{
                 edge_type: :derived_from,
                 weight: 0.7
               }) do
            %{} -> acc + 1
            _ -> acc
          end
        end)
      else
        0
      end

    {nodes, edges_created}
  end

  defp link_to_nearest(node_id, nearest_ids) do
    nearest_ids
    |> Enum.reduce(0, fn nearest_id, acc ->
      case Graphonomous.link_nodes(node_id, nearest_id, %{
             edge_type: :related,
             weight: 0.4
           }) do
        %{} -> acc + 1
        _ -> acc
      end
    end)
  end

  defp conversational?(text) do
    lower = String.downcase(text)

    Enum.any?(
      [
        "i think",
        "i believe",
        "let me",
        "here's",
        "here is",
        "sure,",
        "of course",
        "you can",
        "you should",
        "hope this helps",
        "feel free"
      ],
      &String.starts_with?(lower, &1)
    )
  end

  defp extract_node_id(%{id: id}) when is_binary(id), do: id
  defp extract_node_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_node_id(_), do: nil

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

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp parse_json_map(nil), do: %{}
  defp parse_json_map(value) when is_map(value), do: value

  defp parse_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp parse_json_map(_), do: %{}

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp format_reason({:missing, key}), do: "#{key} is required"
  defp format_reason(other), do: inspect(other)
end
