defmodule Graphonomous.MCP.AttentionRunCycle do
  @moduledoc """
  MCP tool to trigger one on-demand attention cycle.

  This performs:
    1) survey
    2) triage
    3) dispatch according to current (or overridden) autonomy level
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @allowed_autonomy ~w(observe advise act)

  schema do
    field(:autonomy_override, :string,
      description: "Optional autonomy override for this cycle only: observe | advise | act"
    )
  end

  @impl true
  def execute(params, frame) do
    override =
      params
      |> p(:autonomy_override, nil)
      |> normalize_autonomy_override()

    opts = if is_nil(override), do: [], else: [autonomy_override: override]

    case Graphonomous.Attention.run_cycle(opts) do
      {:ok, cycle} ->
        status = Graphonomous.Attention.status()

        payload = %{
          status: "ok",
          autonomy_override: override && Atom.to_string(override),
          cycle: serialize_term(cycle),
          attention_status: serialize_term(status)
        }

        {:reply, tool_response(payload, false), frame}

      {:error, reason} ->
        payload = %{
          status: "error",
          autonomy_override: override && Atom.to_string(override),
          error: format_reason(reason)
        }

        {:reply, tool_response(payload, true), frame}

      other ->
        payload = %{
          status: "error",
          autonomy_override: override && Atom.to_string(override),
          error: "unexpected_attention_cycle_response",
          details: inspect(other)
        }

        {:reply, tool_response(payload, true), frame}
    end
  end

  defp normalize_autonomy_override(nil), do: nil

  defp normalize_autonomy_override(v) when is_atom(v),
    do: normalize_autonomy_override(Atom.to_string(v))

  defp normalize_autonomy_override(v) when is_binary(v) do
    normalized = String.downcase(String.trim(v))

    if normalized in @allowed_autonomy do
      String.to_atom(normalized)
    else
      nil
    end
  end

  defp normalize_autonomy_override(_), do: nil

  defp p(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp tool_response(payload, is_error) when is_map(payload) do
    response =
      Response.tool()
      |> Response.text(Jason.encode!(payload))

    if is_error, do: %{response | isError: true}, else: response
  end

  defp serialize_term(nil), do: nil
  defp serialize_term(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp serialize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {serialize_key(k), serialize_term(v)} end)
    |> Map.new()
  end

  defp serialize_term(list) when is_list(list), do: Enum.map(list, &serialize_term/1)
  defp serialize_term(value) when is_boolean(value), do: value
  defp serialize_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp serialize_term(other), do: other

  defp serialize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp serialize_key(k), do: k

  defp format_reason({:invalid_params, msg}) when is_binary(msg), do: msg
  defp format_reason(:not_found), do: "not found"
  defp format_reason(other), do: inspect(other)
end
