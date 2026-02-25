defmodule Anubis.Server.Transport.STDIO do
  @moduledoc """
  STDIO transport implementation for MCP servers.

  This module handles communication with MCP clients via standard input/output streams,
  processing incoming JSON-RPC messages and forwarding responses.
  """

  @behaviour Anubis.Transport.Behaviour

  use GenServer
  use Anubis.Logging

  import Peri

  alias Anubis.MCP.Message
  alias Anubis.Telemetry
  alias Anubis.Transport.Behaviour, as: Transport

  require Message

  @type t :: GenServer.server()

  @typedoc """
  STDIO transport options

  - `:server` - The server process (required)
  - `:name` - Optional name for registering the GenServer
  """
  @type option ::
          {:server, GenServer.server()}
          | {:name, GenServer.name()}
          | GenServer.option()

  defschema(:parse_options, [
    {:server, {:required, {:oneof, [{:custom, &Anubis.genserver_name/1}, :pid, {:tuple, [:atom, :any]}]}}},
    {:name, {:custom, &Anubis.genserver_name/1}},
    {:registry, {:atom, {:default, Anubis.Server.Registry}}},
    {:request_timeout, {:integer, {:default, to_timeout(second: 30)}}}
  ])

  @doc """
  Starts a new STDIO transport process.

  ## Parameters
    * `opts` - Options
      * `:server` - (required) The server to forward messages to
      * `:name` - Optional name for the GenServer process

  ## Examples

      iex> Anubis.Server.Transport.STDIO.start_link(server: my_server)
      {:ok, pid}
  """
  @impl Transport
  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    server_name = Keyword.get(opts, :name)

    if server_name do
      GenServer.start_link(__MODULE__, Map.new(opts), name: server_name)
    else
      GenServer.start_link(__MODULE__, Map.new(opts))
    end
  end

  @doc """
  Sends a message to the client via stdout.

  ## Parameters
    * `transport` - The transport process
    * `message` - The message to send

  ## Returns
    * `:ok` if message was sent successfully
    * `{:error, reason}` otherwise
  """
  @impl Transport
  def send_message(transport, message, opts) when is_binary(message) do
    GenServer.call(transport, {:send, message}, opts[:timeout])
  end

  @doc """
  Shuts down the transport connection.

  ## Parameters
    * `transport` - The transport process
  """
  @impl Transport
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(transport) do
    GenServer.cast(transport, :shutdown)
  end

  @impl Transport
  def supported_protocol_versions, do: :all

  @impl GenServer
  def init(opts) do
    :ok = :io.setopts(encoding: :utf8)
    Process.flag(:trap_exit, true)

    state = %{
      server: opts.server,
      reading_task: nil,
      registry: opts.registry,
      request_timeout: opts.request_timeout,
      input_buffer: "",
      framing_mode: :line,
      response_mode: :mirrored
    }

    Logger.metadata(mcp_transport: :stdio, mcp_server: state.server)
    Logging.transport_event("starting", %{transport: :stdio, server: state.server})

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      %{transport: :stdio, server: state.server}
    )

    {:ok, state, {:continue, :start_reading}}
  end

  @impl GenServer
  def handle_continue(:start_reading, state) do
    task = Task.async(fn -> read_from_stdin() end)
    {:noreply, %{state | reading_task: task}}
  end

  @impl GenServer
  def handle_info({ref, result}, %{reading_task: %Task{ref: ref}} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, data} ->
        state = handle_incoming_data(data, state)

        task = Task.async(fn -> read_from_stdin() end)
        {:noreply, %{state | reading_task: task}}

      {:error, reason} ->
        Logging.transport_event("read_error", %{reason: reason}, level: :error)
        {:stop, {:error, reason}, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:send, message}, _from, state) do
    emit_outgoing(message, state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:send, message}, state) do
    emit_outgoing(message, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:shutdown, %{reading_task: task} = state) do
    if task, do: Task.shutdown(task, :brutal_kill)

    Logging.transport_event("shutdown", "Transport shutting down", level: :info)

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{transport: :stdio, reason: :shutdown}
    )

    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(reason, _state) do
    Logging.transport_event("terminating", %{reason: reason}, level: :info)

    Telemetry.execute(
      Telemetry.event_transport_terminate(),
      %{system_time: System.system_time()},
      %{transport: :stdio, reason: reason}
    )

    :ok
  end

  # Private helper functions

  defp read_from_stdin do
    case IO.binread(:stdio, 1) do
      :eof ->
        Logging.transport_event("eof", "End of input stream", level: :info)

        Telemetry.execute(
          Telemetry.event_transport_disconnect(),
          %{system_time: System.system_time()},
          %{transport: :stdio, reason: :eof}
        )

        {:error, :eof}

      {:error, reason} ->
        Logging.transport_event("read_error", %{reason: reason}, level: :error)

        Telemetry.execute(
          Telemetry.event_transport_error(),
          %{system_time: System.system_time()},
          %{transport: :stdio, reason: reason}
        )

        {:error, reason}

      data when is_binary(data) ->
        {:ok, data}
    end
  end

  defp handle_incoming_data(data, state) do
    Logging.transport_event(
      "incoming",
      %{transport: :stdio, message_size: byte_size(data)},
      level: :debug
    )

    Telemetry.execute(
      Telemetry.event_transport_receive(),
      %{system_time: System.system_time()},
      %{transport: :stdio, message_size: byte_size(data)}
    )

    buffer = state.input_buffer <> data
    {payloads, rest, detected_mode} = decode_payloads_from_buffer(buffer)

    Enum.each(payloads, fn payload ->
      process_payload(payload, state)
    end)

    state
    |> Map.put(:input_buffer, rest)
    |> maybe_update_framing_mode(detected_mode)
  end

  defp process_payload(payload, state) when is_binary(payload) do
    case Message.decode(payload) do
      {:ok, messages} when is_list(messages) ->
        Enum.each(messages, fn message ->
          process_message(message, state)
        end)

      {:ok, message} when is_map(message) ->
        process_message(message, state)

      {:ok, other} ->
        Logging.transport_event(
          "parse_error",
          %{reason: {:unexpected_decoded_payload, other}},
          level: :error
        )

      {:error, reason} ->
        Logging.transport_event("parse_error", %{reason: reason}, level: :error)
    end
  end

  defp process_message(message, %{server: server_name, registry: registry} = state) do
    server = registry.whereis_server(server_name)
    timeout = state.request_timeout

    context = %{
      type: :stdio,
      env: System.get_env(),
      pid: System.pid()
    }

    if Message.is_notification(message) do
      GenServer.cast(server, {:notification, message, "stdio", context})
    else
      case GenServer.call(server, {:request, message, "stdio", context}, timeout) do
        {:ok, response} when is_binary(response) ->
          emit_outgoing(response, state)
          :ok

        {:ok, other} ->
          Logging.transport_event(
            "server_error",
            %{reason: {:unexpected_server_response, other}},
            level: :error
          )

        {:error, reason} ->
          Logging.transport_event("server_error", %{reason: reason}, level: :error)
      end
    end
  catch
    :exit, reason ->
      Logging.transport_event("server_call_failed", %{reason: reason}, level: :error)
  end

  defp decode_payloads_from_buffer(buffer) when is_binary(buffer) do
    if starts_with_content_length_header?(buffer) do
      decode_content_length_payloads(buffer, [])
    else
      decode_line_payloads(buffer)
    end
  end

  defp starts_with_content_length_header?(buffer) do
    String.match?(buffer, ~r/^\s*content-length\s*:/i)
  end

  defp decode_line_payloads(buffer) do
    case String.split(buffer, "\n") do
      [_only] ->
        {[], buffer, :line}

      parts ->
        {complete, [rest]} = Enum.split(parts, length(parts) - 1)

        payloads =
          complete
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {payloads, rest, :line}
    end
  end

  defp decode_content_length_payloads(buffer, acc) do
    case header_split(buffer) do
      {:incomplete, _} ->
        {Enum.reverse(acc), buffer, :content_length}

      {:ok, header, body_and_rest} ->
        case parse_content_length(header) do
          {:ok, length} ->
            if byte_size(body_and_rest) < length do
              {Enum.reverse(acc), buffer, :content_length}
            else
              payload = binary_part(body_and_rest, 0, length)
              rest = binary_part(body_and_rest, length, byte_size(body_and_rest) - length)
              rest = trim_leading_crlf(rest)
              decode_content_length_payloads(rest, [payload | acc])
            end

          :error ->
            decode_line_payloads(buffer)
        end
    end
  end

  defp header_split(buffer) do
    cond do
      String.contains?(buffer, "\r\n\r\n") ->
        [header, body] = String.split(buffer, "\r\n\r\n", parts: 2)
        {:ok, header, body}

      String.contains?(buffer, "\n\n") ->
        [header, body] = String.split(buffer, "\n\n", parts: 2)
        {:ok, header, body}

      true ->
        {:incomplete, buffer}
    end
  end

  defp parse_content_length(header) do
    lines = String.split(header, ~r/\r?\n/, trim: true)

    value =
      Enum.find_value(lines, fn line ->
        case Regex.run(~r/^\s*content-length\s*:\s*(\d+)\s*$/i, line) do
          [_, v] -> v
          _ -> nil
        end
      end)

    case value do
      nil -> :error
      v -> {:ok, String.to_integer(v)}
    end
  end

  defp trim_leading_crlf(<<"\r\n", rest::binary>>), do: rest
  defp trim_leading_crlf(<<"\n", rest::binary>>), do: rest
  defp trim_leading_crlf(rest), do: rest

  defp maybe_update_framing_mode(state, mode) when mode in [:line, :content_length],
    do: %{state | framing_mode: mode}

  defp maybe_update_framing_mode(state, _mode), do: state

  defp emit_outgoing(message, state) when is_binary(message) do
    framed = maybe_frame_outgoing(message, state)

    Logging.transport_event(
      "outgoing",
      %{transport: :stdio, message_size: byte_size(framed), framing_mode: framing_mode(state)},
      level: :debug
    )

    Telemetry.execute(
      Telemetry.event_transport_send(),
      %{system_time: System.system_time()},
      %{transport: :stdio, message_size: byte_size(framed), framing_mode: framing_mode(state)}
    )

    IO.write(framed)
  end

  defp maybe_frame_outgoing(message, state) do
    case framing_mode(state) do
      :content_length ->
        payload = String.trim_trailing(message, "\n")
        "Content-Length: #{byte_size(payload)}\r\n\r\n#{payload}"

      _ ->
        if String.ends_with?(message, "\n"), do: message, else: message <> "\n"
    end
  end

  defp framing_mode(%{response_mode: :content_length}), do: :content_length
  defp framing_mode(%{response_mode: :line}), do: :line
  defp framing_mode(%{response_mode: :mirrored, framing_mode: mode}) when mode in [:line, :content_length], do: mode
  defp framing_mode(_), do: :line
end
