defmodule GraphMemBench.Adapters.Mem0 do
  @moduledoc """
  Mem0 adapter stub: simple vector search + LLM.
  Returns `{:error, :not_implemented}` for all operations.
  """

  @behaviour GraphMemBench.Adapter

  @impl true
  def ingest(_session), do: {:error, :not_implemented}

  @impl true
  def retrieve(_query, _opts \\ []), do: {:error, :not_implemented}

  @impl true
  def forget(_node_id), do: {:error, :not_implemented}

  @impl true
  def stats, do: %{adapter: :mem0, status: :stub}
end
