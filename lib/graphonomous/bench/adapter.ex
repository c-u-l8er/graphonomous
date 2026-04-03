defmodule GraphMemBench.Adapter do
  @moduledoc """
  Behaviour for GraphMemBench competitor adapters.

  Each adapter wraps a memory system (Graphonomous, Mem0, Zep, Hindsight, etc.)
  behind a uniform interface for fair benchmarking. Competitor adapters are stubs
  that define the interface but return `{:error, :not_implemented}` until those
  systems provide APIs for integration.
  """

  @type result :: %{
          node_id: String.t(),
          content: String.t(),
          score: float(),
          metadata: map()
        }

  @callback ingest(session :: map()) :: :ok | {:error, term()}
  @callback retrieve(query :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  @callback forget(node_id :: String.t()) :: :ok | {:error, term()}
  @callback stats() :: map()
end
