defmodule GraphMemBench.Adapters.Baseline do
  @moduledoc """
  Baseline adapter: full-context LLM (stuff everything in prompt).
  Stub — returns `{:error, :not_implemented}` for all operations.
  """

  @behaviour GraphMemBench.Adapter

  @impl true
  def ingest(_session), do: {:error, :not_implemented}

  @impl true
  def retrieve(_query, _opts \\ []), do: {:error, :not_implemented}

  @impl true
  def forget(_node_id), do: {:error, :not_implemented}

  @impl true
  def stats, do: %{adapter: :baseline, status: :stub}
end
