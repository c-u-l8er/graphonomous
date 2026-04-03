defmodule GraphMemBench.Adapters.Graphonomous do
  @moduledoc """
  GraphMemBench adapter wrapping Graphonomous MCP tools.
  """

  @behaviour GraphMemBench.Adapter

  @impl true
  def ingest(session) when is_map(session) do
    content = Map.get(session, :content, "")
    node_type = Map.get(session, :node_type, :semantic)
    confidence = Map.get(session, :confidence, 0.7)

    case Graphonomous.Graph.store_node(%{
           content: content,
           node_type: node_type,
           confidence: confidence,
           metadata: Map.get(session, :metadata, %{})
         }) do
      {:ok, _node} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def retrieve(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    case Graphonomous.Retriever.retrieve(query, limit: limit) do
      {:ok, %{results: result_list}} ->
        formatted =
          Enum.map(result_list, fn r ->
            %{
              node_id: r.node_id,
              content: r.content,
              score: r.score,
              metadata: Map.get(r, :metadata, %{})
            }
          end)

        {:ok, formatted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def forget(node_id) do
    case Graphonomous.Store.delete_node(node_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stats do
    count = Graphonomous.Store.count_nodes()

    %{
      adapter: :graphonomous,
      node_count: count,
      version: Mix.Project.config()[:version]
    }
  end
end
