defmodule Graphonomous.MCP.ForgetByPolicy do
  @moduledoc """
  MCP tool for running the budget-aware hybrid forgetting policy.

  Scores all nodes by priority (confidence × recency × access × connectivity),
  forgets lowest-priority nodes until under max_nodes budget.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Graphonomous.Forgetter

  schema do
    field(:policy, :string, description: "Forgetting policy: hybrid (default)")

    field(:dry_run, :boolean, description: "If true, return candidates without forgetting them")

    field(:max_nodes, :integer, description: "Override max_nodes budget (default: from config)")
  end

  @impl true
  def execute(params, frame) do
    policy = parse_policy(p(params, :policy, "hybrid"))
    dry_run = p(params, :dry_run, false)
    max_nodes = p(params, :max_nodes)

    opts =
      [dry_run: to_bool(dry_run)]
      |> maybe_add(:max_nodes, max_nodes)

    case Forgetter.forget_by_policy(policy, opts) do
      {:ok, result} ->
        payload = Map.put(result, :status, "ok")

        {:reply,
         Response.tool()
         |> Response.text(Jason.encode!(payload)), frame}

      {:error, reason} ->
        payload = %{status: "error", error: inspect(reason)}

        {:reply,
         Response.tool()
         |> Response.text(Jason.encode!(payload))
         |> Map.put(:isError, true), frame}
    end
  end

  defp parse_policy("hybrid"), do: :hybrid
  defp parse_policy(_), do: :hybrid

  defp to_bool(true), do: true
  defp to_bool("true"), do: true
  defp to_bool(_), do: false

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value) when is_integer(value), do: Keyword.put(opts, key, value)

  defp maybe_add(opts, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {i, _} -> Keyword.put(opts, key, i)
      _ -> opts
    end
  end

  defp maybe_add(opts, _key, _value), do: opts

  defp p(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
