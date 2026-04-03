defmodule GraphMemBench.Adapters.Hindsight do
  @moduledoc """
  Hindsight adapter stub: 4-way parallel retrieval + RRF.
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
  def stats, do: %{adapter: :hindsight, status: :stub}
end
