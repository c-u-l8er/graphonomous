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

    field(:node_type, :string, description: "Node type: episodic, semantic, or procedural")

    field(:confidence, :number, description: "Confidence score from 0.0 to 1.0")

    field(:source, :string, description: "Where this knowledge came from")

    field(:metadata, :string, description: "Optional JSON object with extra node metadata")
  end

  @impl true
  def execute(params, frame) do
    attrs = %{
      content: get_param(params, :content),
      node_type: normalize_node_type(get_param(params, :node_type, "semantic")),
      confidence: normalize_confidence(get_param(params, :confidence, 0.5)),
      source: get_param(params, :source),
      metadata: normalize_metadata(get_param(params, :metadata, %{}))
    }

    case Graphonomous.store_node(attrs) do
      %{id: id, confidence: confidence} = node when is_binary(id) ->
        payload = %{
          status: "stored",
          node_id: id,
          node_type: Map.get(node, :node_type, :semantic),
          confidence: confidence
        }

        {:ok, Jason.encode!(payload), frame}

      {:error, reason} ->
        payload = %{
          status: "error",
          error: "store_node_failed",
          reason: inspect(reason)
        }

        {:ok, Jason.encode!(payload), frame}

      other ->
        payload = %{
          status: "error",
          error: "unexpected_result",
          reason: inspect(other)
        }

        {:ok, Jason.encode!(payload), frame}
    end
  end

  defp get_param(params, key, default \\ nil) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key), default))
  end

  defp normalize_node_type(type) when is_atom(type), do: normalize_node_type(Atom.to_string(type))

  defp normalize_node_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "episodic" -> "episodic"
      "procedural" -> "procedural"
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

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value
end
