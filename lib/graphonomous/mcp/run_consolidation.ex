defmodule Graphonomous.MCP.RunConsolidation do
  @moduledoc """
  MCP tool to trigger and inspect consolidation cycles.

  Supported actions:
  - `run`             -> trigger a consolidation cycle
  - `status`          -> return current consolidator runtime info
  - `run_and_status`  -> trigger then return runtime info (default)

  Notes:
  - Consolidation is asynchronous.
  - Use `wait_ms` to optionally wait before reading status.
  """

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response

  @allowed_actions ~w(run status run_and_status)
  @max_wait_ms 30_000

  schema do
    field(:action, :string,
      description: "run | status | run_and_status (default: run_and_status)"
    )

    field(:wait_ms, :number,
      description: "Optional delay in milliseconds before returning status (0..30000)"
    )
  end

  @impl true
  def execute(params, frame) do
    action =
      params
      |> p(:action, "run_and_status")
      |> normalize_action()

    wait_ms =
      params
      |> p(:wait_ms, 0)
      |> normalize_wait_ms()

    result =
      case action do
        :run ->
          do_run(wait_ms)

        :status ->
          do_status()

        :run_and_status ->
          do_run_and_status(wait_ms)
      end

    {payload, is_error} =
      case result do
        {:ok, data} ->
          {%{
             status: "ok",
             action: Atom.to_string(action),
             result: serialize_term(data)
           }, false}

        {:error, reason} ->
          {%{
             status: "error",
             action: Atom.to_string(action),
             error: format_reason(reason)
           }, true}
      end

    {:reply, tool_response(payload, is_error), frame}
  end

  defp do_run(wait_ms) do
    case Graphonomous.run_consolidation_now() do
      :ok ->
        maybe_wait(wait_ms)

        {:ok,
         %{
           triggered: true,
           wait_ms: wait_ms
         }}

      other ->
        {:error, {:unexpected_run_result, other}}
    end
  end

  defp do_status do
    info = Graphonomous.consolidator_info()

    {:ok,
     %{
       consolidator: info,
       health: Graphonomous.health()
     }}
  rescue
    error ->
      {:error, {:status_failed, error}}
  end

  defp do_run_and_status(wait_ms) do
    with {:ok, _run} <- do_run(wait_ms),
         {:ok, status} <- do_status() do
      {:ok, status}
    end
  end

  defp maybe_wait(wait_ms) when is_integer(wait_ms) and wait_ms > 0 do
    Process.sleep(wait_ms)
  end

  defp maybe_wait(_), do: :ok

  defp normalize_action(action) when is_atom(action), do: normalize_action(Atom.to_string(action))

  defp normalize_action(action) when is_binary(action) do
    normalized =
      action
      |> String.trim()
      |> String.downcase()

    if normalized in @allowed_actions do
      String.to_atom(normalized)
    else
      :run_and_status
    end
  end

  defp normalize_action(_), do: :run_and_status

  defp normalize_wait_ms(value) when is_integer(value) do
    value
    |> max(0)
    |> min(@max_wait_ms)
  end

  defp normalize_wait_ms(value) when is_float(value) do
    value
    |> trunc()
    |> normalize_wait_ms()
  end

  defp normalize_wait_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, _rest} -> normalize_wait_ms(parsed)
      :error -> 0
    end
  end

  defp normalize_wait_ms(_), do: 0

  defp p(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp tool_response(payload, is_error) when is_map(payload) do
    response =
      Response.tool()
      |> Response.text(Jason.encode!(payload))

    if is_error, do: %{response | isError: true}, else: response
  end

  defp serialize_term(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp serialize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {serialize_key(k), serialize_term(v)} end)
    |> Map.new()
  end

  defp serialize_term(list) when is_list(list), do: Enum.map(list, &serialize_term/1)
  defp serialize_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp serialize_term(other), do: other

  defp serialize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp serialize_key(k), do: k

  defp format_reason({:unexpected_run_result, other}) do
    "unexpected run response: #{inspect(other)}"
  end

  defp format_reason({:status_failed, error}) do
    "status query failed: #{Exception.message(error)}"
  end

  defp format_reason(other), do: inspect(other)
end
