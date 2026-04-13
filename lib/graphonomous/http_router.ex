defmodule Graphonomous.HttpRouter do
  @moduledoc """
  Minimal Plug router for serving Graphonomous MCP over HTTP.

  Routes:
  - POST /mcp  → Anubis StreamableHTTP Plug (MCP JSON-RPC)
  - GET  /mcp  → Anubis StreamableHTTP Plug (SSE)
  - GET  /health → JSON health check
  """

  use Plug.Router

  plug Plug.Logger, log: :debug

  plug :add_cors_headers

  plug :match
  plug :dispatch

  # CORS preflight
  match "/mcp", via: :options do
    conn
    |> send_resp(204, "")
  end

  # MCP endpoint — dispatched at runtime to avoid compile-time dependency on
  # the Anubis StreamableHTTP Plug (which is conditionally compiled).
  match "/mcp" do
    mcp_plug = Anubis.Server.Transport.StreamableHTTP.Plug
    opts = mcp_plug.init(server: Graphonomous.MCP.Machines.Server)
    mcp_plug.call(conn, opts)
  end

  get "/health" do
    body = Jason.encode!(%{status: "ok", name: "graphonomous", version: Graphonomous.version()})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp add_cors_headers(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, accept, mcp-session-id")
  end
end
