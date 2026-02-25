#!/usr/bin/env python3
"""
MCP STDIO smoke test for Graphonomous.

Purpose:
- Validate that a server command can complete MCP handshake and basic discovery
  before deployment (helps catch "Context server request timeout" regressions).

Default behavior:
1) Start server command
2) Send initialize
3) Send notifications/initialized
4) Send tools/list
5) Send resources/list
6) Assert expected fields and timing constraints
"""

from __future__ import annotations

import argparse
import json
import os
import selectors
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_PROTOCOL_VERSION = "2025-03-26"
DEFAULT_EXPECTED_TOOL = "store_node"


class SmokeTestError(RuntimeError):
    pass


@dataclass
class StepResult:
    name: str
    ok: bool
    latency_ms: float
    details: str = ""


class MCPStdioClient:
    def __init__(self, proc: subprocess.Popen, io_timeout_s: float) -> None:
        self.proc = proc
        self.io_timeout_s = io_timeout_s
        self._buffer = bytearray()
        self._selector = selectors.DefaultSelector()
        assert self.proc.stdout is not None
        self._stdout_fd = self.proc.stdout.fileno()

        try:
            os.set_blocking(self._stdout_fd, False)
        except (AttributeError, OSError):
            pass

        self._selector.register(self._stdout_fd, selectors.EVENT_READ)

    def close(self) -> None:
        try:
            self._selector.close()
        except Exception:
            pass

    def send(self, message: Dict[str, Any]) -> None:
        if self.proc.poll() is not None:
            raise SmokeTestError(f"Server exited before send (code={self.proc.returncode})")

        payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
        frame = f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii") + payload

        assert self.proc.stdin is not None
        try:
            self.proc.stdin.write(frame)
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            raise SmokeTestError("Broken pipe writing to MCP server stdin") from exc

    def recv_message(self, timeout_s: Optional[float] = None) -> Dict[str, Any]:
        timeout_s = self.io_timeout_s if timeout_s is None else timeout_s
        deadline = time.monotonic() + timeout_s

        while True:
            # Try parse from existing buffer first
            parsed = self._try_parse_one()
            if parsed is not None:
                return parsed

            # Need more bytes
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SmokeTestError("Timed out waiting for MCP response frame")

            events = self._selector.select(remaining)
            if not events:
                raise SmokeTestError("Timed out waiting for MCP server stdout readability")

            for key, _mask in events:
                try:
                    chunk = os.read(key.fd, 4096)
                except BlockingIOError:
                    continue

                if chunk == b"":
                    code = self.proc.poll()
                    raise SmokeTestError(f"MCP stdout closed (server code={code})")

                self._buffer.extend(chunk)

    def recv_response_for_id(self, request_id: int, timeout_s: Optional[float] = None) -> Dict[str, Any]:
        timeout_s = self.io_timeout_s if timeout_s is None else timeout_s
        deadline = time.monotonic() + timeout_s

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SmokeTestError(f"Timed out waiting for response id={request_id}")

            msg = self.recv_message(timeout_s=remaining)

            if isinstance(msg, dict) and msg.get("id") == request_id:
                return msg
            # Ignore notifications / unrelated traffic

    def _try_parse_one(self) -> Optional[Dict[str, Any]]:
        if not self._buffer:
            return None

        header_end = self._find_header_end(self._buffer)
        if header_end is None:
            return None

        header_bytes = bytes(self._buffer[:header_end])
        body_start = header_end + (4 if self._buffer[header_end:header_end + 4] == b"\r\n\r\n" else 2)
        content_length = self._parse_content_length(header_bytes)
        if content_length is None:
            raise SmokeTestError(f"Invalid MCP frame header (missing Content-Length): {header_bytes!r}")

        if len(self._buffer) < body_start + content_length:
            return None

        body = bytes(self._buffer[body_start:body_start + content_length])
        del self._buffer[:body_start + content_length]

        try:
            msg = json.loads(body.decode("utf-8"))
        except Exception as exc:
            raise SmokeTestError(f"Failed to decode JSON response: {body!r}") from exc

        if not isinstance(msg, dict):
            raise SmokeTestError(f"MCP response is not a JSON object: {msg!r}")
        return msg

    @staticmethod
    def _find_header_end(buf: bytearray) -> Optional[int]:
        i = buf.find(b"\r\n\r\n")
        if i != -1:
            return i
        i = buf.find(b"\n\n")
        if i != -1:
            return i
        return None

    @staticmethod
    def _parse_content_length(header: bytes) -> Optional[int]:
        text = header.decode("utf-8", errors="replace")
        for line in text.replace("\r\n", "\n").split("\n"):
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            if k.strip().lower() == "content-length":
                v = v.strip()
                if not v.isdigit():
                    return None
                return int(v)
        return None


def _pump_stderr(pipe, sink: List[str], tee: bool) -> None:
    try:
        for raw in iter(pipe.readline, b""):
            line = raw.decode("utf-8", errors="replace")
            sink.append(line)
            if tee:
                sys.stderr.write(line)
                sys.stderr.flush()
    except Exception as exc:
        sink.append(f"[stderr-pump-error] {exc}\n")


def _build_command(command_template: str, db_path: str, embedder_backend: str) -> str:
    return command_template.format(db_path=db_path, embedder_backend=embedder_backend)


def _validate_initialize_response(resp: Dict[str, Any], protocol_version: str) -> None:
    if "error" in resp:
        raise SmokeTestError(f"initialize returned error: {resp['error']}")

    result = resp.get("result")
    if not isinstance(result, dict):
        raise SmokeTestError(f"initialize response missing result object: {resp}")

    pv = result.get("protocolVersion")
    if pv != protocol_version:
        raise SmokeTestError(f"initialize protocolVersion mismatch: got={pv!r} expected={protocol_version!r}")

    server_info = result.get("serverInfo")
    if not isinstance(server_info, dict) or not server_info.get("name"):
        raise SmokeTestError(f"initialize serverInfo invalid: {server_info!r}")


def _validate_tools_list(resp: Dict[str, Any], expected_tool: Optional[str]) -> int:
    if "error" in resp:
        raise SmokeTestError(f"tools/list returned error: {resp['error']}")

    result = resp.get("result")
    if not isinstance(result, dict):
        raise SmokeTestError(f"tools/list response missing result object: {resp}")

    tools = result.get("tools")
    if not isinstance(tools, list):
        raise SmokeTestError(f"tools/list result.tools is not a list: {tools!r}")

    if expected_tool:
        names = {t.get("name") for t in tools if isinstance(t, dict)}
        if expected_tool not in names:
            raise SmokeTestError(
                f"Expected tool {expected_tool!r} not found. Available: {sorted(n for n in names if n)}"
            )

    return len(tools)


def _validate_resources_list(resp: Dict[str, Any]) -> int:
    if "error" in resp:
        raise SmokeTestError(f"resources/list returned error: {resp['error']}")

    result = resp.get("result")
    if not isinstance(result, dict):
        raise SmokeTestError(f"resources/list response missing result object: {resp}")

    resources = result.get("resources")
    if not isinstance(resources, list):
        raise SmokeTestError(f"resources/list result.resources is not a list: {resources!r}")

    return len(resources)


def _terminate_process(proc: subprocess.Popen, grace_s: float = 2.0) -> None:
    if proc.poll() is not None:
        return

    try:
        if proc.stdin:
            proc.stdin.close()
    except Exception:
        pass

    deadline = time.monotonic() + grace_s
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.05)

    # escalate
    try:
        proc.terminate()
    except Exception:
        pass

    try:
        proc.wait(timeout=2.0)
        return
    except Exception:
        pass

    try:
        proc.kill()
    except Exception:
        pass


def run_smoke(args: argparse.Namespace) -> Tuple[List[StepResult], List[str]]:
    db_path = os.path.expanduser(args.db_path)
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    command = _build_command(args.command, db_path, args.embedder_backend)
    stderr_lines: List[str] = []

    proc = subprocess.Popen(
        command,
        shell=True,
        cwd=args.cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
        preexec_fn=os.setsid if os.name != "nt" else None,
    )

    assert proc.stderr is not None
    stderr_thread = threading.Thread(
        target=_pump_stderr,
        args=(proc.stderr, stderr_lines, args.tee_stderr),
        daemon=True,
    )
    stderr_thread.start()

    client = MCPStdioClient(proc=proc, io_timeout_s=args.io_timeout_s)
    steps: List[StepResult] = []

    try:
        # Step 1: initialize
        t0 = time.monotonic()
        client.send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": args.protocol_version,
                    "capabilities": {},
                    "clientInfo": {"name": args.client_name, "version": args.client_version},
                },
            }
        )
        init_resp = client.recv_response_for_id(1, timeout_s=args.step_timeout_s)
        t1 = time.monotonic()
        _validate_initialize_response(init_resp, args.protocol_version)
        steps.append(StepResult("initialize", True, (t1 - t0) * 1000.0))

        # Step 2: initialized notification
        t0 = time.monotonic()
        client.send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        t1 = time.monotonic()
        steps.append(StepResult("notifications/initialized", True, (t1 - t0) * 1000.0))

        # Step 3: tools/list
        t0 = time.monotonic()
        client.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools_resp = client.recv_response_for_id(2, timeout_s=args.step_timeout_s)
        t1 = time.monotonic()
        tool_count = _validate_tools_list(tools_resp, args.expected_tool)
        steps.append(
            StepResult(
                "tools/list",
                True,
                (t1 - t0) * 1000.0,
                details=f"tools={tool_count}",
            )
        )

        # Step 4: resources/list
        t0 = time.monotonic()
        client.send({"jsonrpc": "2.0", "id": 3, "method": "resources/list", "params": {}})
        resources_resp = client.recv_response_for_id(3, timeout_s=args.step_timeout_s)
        t1 = time.monotonic()
        resource_count = _validate_resources_list(resources_resp)
        steps.append(
            StepResult(
                "resources/list",
                True,
                (t1 - t0) * 1000.0,
                details=f"resources={resource_count}",
            )
        )

        # SLA checks
        first_ok = next((s for s in steps if s.name == "initialize"), None)
        if first_ok and first_ok.latency_ms > args.max_initialize_ms:
            raise SmokeTestError(
                f"initialize latency too high: {first_ok.latency_ms:.1f}ms > {args.max_initialize_ms}ms"
            )

        # soft check for discovery steps
        for s in steps:
            if s.name in ("tools/list", "resources/list") and s.latency_ms > args.max_discovery_ms:
                raise SmokeTestError(
                    f"{s.name} latency too high: {s.latency_ms:.1f}ms > {args.max_discovery_ms}ms"
                )

        return steps, stderr_lines

    finally:
        client.close()
        _terminate_process(proc)
        try:
            stderr_thread.join(timeout=0.5)
        except Exception:
            pass


def parse_args() -> argparse.Namespace:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))

    parser = argparse.ArgumentParser(
        description="MCP STDIO smoke test for Graphonomous pre-deploy validation."
    )
    parser.add_argument(
        "--cwd",
        default=project_root,
        help="Working directory used to launch server command (default: project root).",
    )
    parser.add_argument(
        "--command",
        default='mix run --no-compile -e "Graphonomous.CLI.main([\\"--db\\",\\"{db_path}\\",\\"--embedder-backend\\",\\"{embedder_backend}\\"])"',
        help=(
            "Server command template. Supports placeholders: {db_path}, {embedder_backend}. "
            "Default runs the MCP entrypoint via mix run --no-compile."
        ),
    )
    parser.add_argument(
        "--db-path",
        default="~/.graphonomous/mcp-smoke-test.db",
        help="SQLite DB path used for smoke test.",
    )
    parser.add_argument(
        "--embedder-backend",
        default="fallback",
        choices=["fallback", "auto", "bumblebee"],
        help="Embedder backend argument injected into command template.",
    )
    parser.add_argument(
        "--protocol-version",
        default=DEFAULT_PROTOCOL_VERSION,
        help="MCP protocolVersion sent in initialize.",
    )
    parser.add_argument(
        "--client-name",
        default="mcp-smoke-test",
        help="clientInfo.name sent in initialize.",
    )
    parser.add_argument(
        "--client-version",
        default="1.0",
        help="clientInfo.version sent in initialize.",
    )
    parser.add_argument(
        "--expected-tool",
        default=DEFAULT_EXPECTED_TOOL,
        help="Require this tool name to appear in tools/list (set empty string to disable).",
    )
    parser.add_argument(
        "--io-timeout-s",
        type=float,
        default=10.0,
        help="Low-level IO frame wait timeout.",
    )
    parser.add_argument(
        "--step-timeout-s",
        type=float,
        default=15.0,
        help="Per request timeout for initialize/tools/list/resources/list.",
    )
    parser.add_argument(
        "--max-initialize-ms",
        type=float,
        default=4000.0,
        help="Fail if initialize latency exceeds this threshold.",
    )
    parser.add_argument(
        "--max-discovery-ms",
        type=float,
        default=4000.0,
        help="Fail if tools/list or resources/list latency exceeds this threshold.",
    )
    parser.add_argument(
        "--tee-stderr",
        action="store_true",
        help="Mirror server stderr to this process stderr while running.",
    )
    parser.add_argument(
        "--json-output",
        action="store_true",
        help="Emit machine-readable JSON summary.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    # Allow disabling expected tool check via empty string
    if args.expected_tool is not None and args.expected_tool.strip() == "":
        args.expected_tool = None

    start = time.monotonic()
    try:
        steps, stderr_lines = run_smoke(args)
        elapsed_ms = (time.monotonic() - start) * 1000.0

        if args.json_output:
            print(
                json.dumps(
                    {
                        "ok": True,
                        "elapsed_ms": elapsed_ms,
                        "steps": [
                            {
                                "name": s.name,
                                "ok": s.ok,
                                "latency_ms": s.latency_ms,
                                "details": s.details,
                            }
                            for s in steps
                        ],
                    },
                    indent=2,
                )
            )
        else:
            print("✅ MCP smoke test PASSED")
            for s in steps:
                suffix = f" ({s.details})" if s.details else ""
                print(f"  - {s.name}: {s.latency_ms:.1f} ms{suffix}")
            print(f"  total: {elapsed_ms:.1f} ms")
        return 0

    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        return 130
    except SmokeTestError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000.0
        print("❌ MCP smoke test FAILED", file=sys.stderr)
        print(f"reason: {exc}", file=sys.stderr)
        print(f"elapsed: {elapsed_ms:.1f} ms", file=sys.stderr)

        # Best-effort stderr context
        if "stderr_lines" in locals() and stderr_lines:
            tail = "".join(stderr_lines[-80:])
            print("\n--- server stderr (tail) ---", file=sys.stderr)
            print(tail, file=sys.stderr, end="" if tail.endswith("\n") else "\n")
            print("--- end stderr tail ---", file=sys.stderr)
        return 1


if __name__ == "__main__":
    # Make SIGPIPE explicit for shell piping usage
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main())
