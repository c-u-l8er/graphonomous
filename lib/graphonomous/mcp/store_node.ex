defmodule Graphonomous.MCP.StoreNode do
  @moduledoc """
  MCP tool for storing a knowledge node in the Graphonomous graph.
  """

  use Anubis.Server.Component, type: :tool

  schema do
    field(:content, :string,
      required: true,
      description: "Natural-language knowledge to store"
    )

    field(:node_type, :string,
      description: "Node type: episodic, semantic, procedural, temporal, outcome, or goal"
    )

    field(:confidence, :number, description: "Confidence score from 0.0 to 1.0")

    field(:source, :string, description: "Where this knowledge came from")

    field(:metadata, :string, description: "Optional JSON object with extra node metadata")

    field(:region, :array,
      description:
        "Optional N-dimensional spatial coordinate (list of numbers) anchoring this node in a region (SCOPE / OS-012)"
    )
  end

  @impl true
  def execute(params, frame) do
    raw_content = get_param(params, :content)

    case validate_content(raw_content) do
      {:error, reason} ->
        payload = %{
          status: "error",
          error: "content_required",
          reason: reason
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload)
         |> Map.put(:isError, true), frame}

      {:ok, content} ->
        do_execute(content, params, frame)
    end
  end

  defp do_execute(content, params, frame) do
    attrs = %{
      content: content,
      node_type: normalize_node_type(get_param(params, :node_type, "semantic")),
      confidence: normalize_confidence(get_param(params, :confidence, 0.5)),
      source: get_param(params, :source),
      metadata: normalize_metadata(get_param(params, :metadata, %{})),
      region: normalize_region(get_param(params, :region))
    }

    case Graphonomous.store_node(attrs) do
      %{id: id, confidence: confidence} = node when is_binary(id) ->
        payload = %{
          status: "stored",
          node_id: id,
          node_type: Map.get(node, :node_type, :semantic),
          confidence: confidence
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload), frame}

      {:error, reason} ->
        payload = %{
          status: "error",
          error: "store_node_failed",
          reason: inspect(reason)
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload)
         |> Map.put(:isError, true), frame}

      other ->
        payload = %{
          status: "error",
          error: "unexpected_result",
          reason: inspect(other)
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload)
         |> Map.put(:isError, true), frame}
    end
  end

  defp get_param(params, key, default \\ nil) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key), default))
  end

  # Reject nil/non-binary/empty/whitespace-only content at the MCP boundary.
  # Silently storing empty nodes was a bug that broke durable memory across
  # sessions — see test/store_node_content_validation_test.exs.
  defp validate_content(nil), do: {:error, "content is required and must be a non-empty string"}

  defp validate_content(content) when is_binary(content) do
    case String.trim(content) do
      "" -> {:error, "content must not be empty or whitespace-only"}
      _ -> {:ok, content}
    end
  end

  defp validate_content(other),
    do: {:error, "content must be a string, got: #{inspect(other)}"}

  defp normalize_node_type(type) when is_atom(type), do: normalize_node_type(Atom.to_string(type))

  defp normalize_node_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "episodic" -> "episodic"
      "procedural" -> "procedural"
      "temporal" -> "temporal"
      "outcome" -> "outcome"
      "goal" -> "goal"
      _ -> "semantic"
    end
  end

  defp normalize_node_type(_), do: "semantic"

  defp normalize_confidence(value) when is_float(value), do: clamp(value, 0.0, 1.0)
  defp normalize_confidence(value) when is_integer(value), do: normalize_confidence(value * 1.0)

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> normalize_confidence(parsed)
      :error -> 0.5
    end
  end

  defp normalize_confidence(_), do: 0.5

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(value) when is_map(value), do: value

  defp normalize_metadata(value) when is_binary(value) do
    with {:ok, decoded} <- Jason.decode(value),
         true <- is_map(decoded) do
      decoded
    else
      _ -> %{}
    end
  end

  defp normalize_metadata(_), do: %{}

  # Accept an N-D region as a list of numbers, or a JSON-array string; anything
  # else (including nil) becomes nil. The Store layer re-validates before persist.
  defp normalize_region(value) when is_list(value) do
    if value != [] and Enum.all?(value, &is_number/1), do: value, else: nil
  end

  defp normalize_region(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> normalize_region(decoded)
      _ -> nil
    end
  end

  defp normalize_region(_), do: nil

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value
end
