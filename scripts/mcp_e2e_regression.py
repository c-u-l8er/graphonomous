#!/usr/bin/env python3
"""
MCP end-to-end regression test for Graphonomous.

Flow covered:
1) initialize + notifications/initialized
2) tools/list contains required tools
3) query_graph(list_nodes)
4) store_node
5) learn_from_outcome
6) manage_goal(create_goal + link_nodes)
7) review_goal
8) query_graph(list_nodes) final check

This script is intentionally strict and exits non-zero on failures.
"""

from __future__ import annotations

import argparse
import json
import os
import selectors
import subprocess
import sys
import threading
import time
import shlex
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_PROTOCOL_VERSION = "2025-03-26"
DEFAULT_DB_PATH = "~/.graphonomous/knowledge-e2e.db"
DEFAULT_REQUEST_TIMEOUT_MS = 180_000
DEFAULT_IO_TIMEOUT_S = 30.0

MIX_COMMAND_TEMPLATE = (
    'mix run --no-compile -e '
    '"Graphonomous.CLI.main([\\"--db\\",\\"{db_path}\\",'
    '\\"--embedder-backend\\",\\"{embedder_backend}\\",'
    '\\"--request-timeout\\",\\"{request_timeout_ms}\\",'
    '\\"--log-level\\",\\"{log_level}\\"])"'
)

DEFAULT_COMMAND = MIX_COMMAND_TEMPLATE

LAST_STDERR_LINES: List[str] = []


class E2EError(RuntimeError):
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
            raise E2EError(f"Server exited before send (code={self.proc.returncode})")

        payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
        frame = f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii") + payload

        assert self.proc.stdin is not None
        try:
            self.proc.stdin.write(frame)
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            raise E2EError("Broken pipe writing to MCP server stdin") from exc

    def recv_message(self, timeout_s: Optional[float] = None) -> Dict[str, Any]:
        timeout_s = self.io_timeout_s if timeout_s is None else timeout_s
        deadline = time.monotonic() + timeout_s

        while True:
            parsed = self._try_parse_one()
            if parsed is not None:
                return parsed

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise E2EError("Timed out waiting for MCP response frame")

            events = self._selector.select(remaining)
            if not events:
                raise E2EError("Timed out waiting for MCP server stdout readability")

            for key, _mask in events:
                try:
                    chunk = os.read(key.fd, 4096)
                except BlockingIOError:
                    continue

                if chunk == b"":
                    code = self.proc.poll()
                    raise E2EError(f"MCP stdout closed (server code={code})")

                self._buffer.extend(chunk)

    def recv_response_for_id(self, request_id: int, timeout_s: Optional[float] = None) -> Dict[str, Any]:
        timeout_s = self.io_timeout_s if timeout_s is None else timeout_s
        deadline = time.monotonic() + timeout_s

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise E2EError(f"Timed out waiting for response id={request_id}")

            msg = self.recv_message(timeout_s=remaining)
            if isinstance(msg, dict) and msg.get("id") == request_id:
                return msg
            # ignore notifications and unrelated responses

    def request(self, request_id: int, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        req: Dict[str, Any] = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            req["params"] = params
        self.send(req)
        return self.recv_response_for_id(request_id)

    def _try_parse_one(self) -> Optional[Dict[str, Any]]:
        if not self._buffer:
            return None

        header_end = self._find_header_end(self._buffer)
        if header_end is None:
            return None

        header_bytes = bytes(self._buffer[:header_end])
        body_start = header_end + (4 if self._buffer[header_end : header_end + 4] == b"\r\n\r\n" else 2)
        content_length = self._parse_content_length(header_bytes)
        if content_length is None:
            raise E2EError(f"Invalid MCP frame header (missing Content-Length): {header_bytes!r}")

        if len(self._buffer) < body_start + content_length:
            return None

        body = bytes(self._buffer[body_start : body_start + content_length])
        del self._buffer[: body_start + content_length]

        try:
            msg = json.loads(body.decode("utf-8"))
        except Exception as exc:
            raise E2EError(f"Failed to decode JSON response: {body!r}") from exc

        if not isinstance(msg, dict):
            raise E2EError(f"MCP response is not a JSON object: {msg!r}")
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


def _extract_tool_payload(tool_call_resp: Dict[str, Any]) -> Dict[str, Any]:
    if "error" in tool_call_resp:
        raise E2EError(f"tools/call returned error: {tool_call_resp['error']}")

    result = tool_call_resp.get("result")
    if not isinstance(result, dict):
        raise E2EError(f"tools/call result missing/invalid: {tool_call_resp}")

    structured = result.get("structuredContent")
    if isinstance(structured, dict):
        return structured

    content = result.get("content")
    if not isinstance(content, list) or not content:
        # allow empty tool responses, but normalize
        return {}

    for item in content:
        if not isinstance(item, dict):
            continue

        # Standard MCP text payload
        text = item.get("text")
        if isinstance(text, str) and text.strip():
            try:
                decoded = json.loads(text)
                if isinstance(decoded, dict):
                    return decoded
            except Exception:
                pass

        # Structured payload variants
        for key in ("json", "structured", "data"):
            value = item.get(key)
            if isinstance(value, dict):
                return value

    raise E2EError(f"tools/call payload unsupported shape: {tool_call_resp}")


def _tool_call(client: MCPStdioClient, req_id: int, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    resp = client.request(
        req_id,
        "tools/call",
        {"name": name, "arguments": arguments},
    )
    return _extract_tool_payload(resp)


def run_e2e(args: argparse.Namespace) -> Tuple[List[StepResult], List[str]]:
    db_path = os.path.expanduser(args.db_path)
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    command = args.command.format(
        db_path=db_path,
        embedder_backend=args.embedder_backend,
        request_timeout_ms=args.request_timeout_ms,
        log_level=args.log_level,
    )

    popen_cmd: Any
    popen_shell = bool(args.shell)

    if popen_shell:
        popen_cmd = command
    else:
        command_argv = shlex.split(command)
        if not command_argv:
            raise E2EError(f"Server command resolved to empty argv: {command!r}")
        popen_cmd = command_argv

    stderr_lines: List[str] = []
    proc = subprocess.Popen(
        popen_cmd,
        shell=popen_shell,
        cwd=args.cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
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
    rid = 1

    def step(name: str, fn):
        t0 = time.monotonic()
        try:
            details = fn()
            steps.append(StepResult(name=name, ok=True, latency_ms=(time.monotonic() - t0) * 1000.0, details=details or ""))
        except Exception as exc:
            steps.append(StepResult(name=name, ok=False, latency_ms=(time.monotonic() - t0) * 1000.0, details=str(exc)))
            raise

    try:
        def s_initialize() -> str:
            nonlocal rid
            resp = client.request(
                rid,
                "initialize",
                {
                    "protocolVersion": DEFAULT_PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {"name": "graphonomous-e2e-regression", "version": "0.1.0"},
                },
            )
            rid += 1

            if "error" in resp:
                raise E2EError(f"initialize error: {resp['error']}")
            result = resp.get("result")
            if not isinstance(result, dict):
                raise E2EError(f"initialize result invalid: {resp}")
            pv = result.get("protocolVersion")
            if pv != DEFAULT_PROTOCOL_VERSION:
                raise E2EError(f"protocol version mismatch: got={pv!r} expected={DEFAULT_PROTOCOL_VERSION!r}")
            return f"server={result.get('serverInfo', {}).get('name', 'unknown')}"

        step("initialize", s_initialize)

        def s_initialized() -> str:
            client.send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
            return "sent"

        step("notifications/initialized", s_initialized)

        def s_tools_list() -> str:
            nonlocal rid
            resp = client.request(rid, "tools/list", {})
            rid += 1
            if "error" in resp:
                raise E2EError(f"tools/list error: {resp['error']}")
            tools = resp.get("result", {}).get("tools", [])
            if not isinstance(tools, list):
                raise E2EError(f"tools/list invalid payload: {resp}")
            names = {t.get("name") for t in tools if isinstance(t, dict)}
            required = {"query_graph", "store_node", "learn_from_outcome", "manage_goal", "review_goal"}
            missing = sorted(required - names)
            if missing:
                raise E2EError(f"required tools missing: {missing}")
            return f"tools={len(tools)}"

        step("tools/list", s_tools_list)

        e2e_token = f"mcp-e2e-token-{int(time.time())}-{os.getpid()}"
        node_content = f"MCP e2e regression node [{e2e_token}]"

        def s_query_pre() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "query_graph",
                {"operation": "similarity_search", "query": e2e_token},
            )
            rid += 1
            status = payload.get("status")
            if status != "ok":
                raise E2EError(f"query_graph pre similarity_search failed: {payload}")

            result = payload.get("result", {})
            count = result.get("count", 0)
            if not isinstance(count, int):
                raise E2EError(f"query_graph pre count invalid: {payload}")

            matches = result.get("matches", [])
            if not isinstance(matches, list):
                raise E2EError(f"query_graph pre matches invalid: {payload}")

            saw_token = any(
                isinstance(m, dict) and e2e_token in str(m.get("content", ""))
                for m in matches
            )
            if saw_token:
                raise E2EError(
                    f"query_graph pre unexpectedly contained token {e2e_token!r} in matches: {matches}"
                )

            return f"pre_matches={count}"

        step("query_graph pre similarity_search", s_query_pre)

        node_id: Dict[str, str] = {}

        def s_store_node() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "store_node",
                {
                    "content": node_content,
                    "node_type": "semantic",
                    "source": "mcp_e2e_regression",
                },
            )
            rid += 1
            if payload.get("status") != "stored":
                raise E2EError(f"store_node failed: {payload}")
            nid = payload.get("node_id")
            if not isinstance(nid, str) or not nid:
                raise E2EError(f"store_node missing node_id: {payload}")
            node_id["value"] = nid
            return nid

        step("store_node", s_store_node)

        def s_learn() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "learn_from_outcome",
                {
                    "action_id": f"e2e-regression-{int(time.time())}",
                    "status": "success",
                    "confidence": 0.9,
                    "causal_node_ids": json.dumps([node_id["value"]]),
                    "evidence": json.dumps({"runner": "mcp_e2e_regression"}),
                },
            )
            rid += 1

            # learn payload shape differs from status convention; validate by fields
            if payload.get("action_id") is None:
                raise E2EError(f"learn_from_outcome unexpected payload: {payload}")
            if payload.get("updated", 0) < 1:
                raise E2EError(f"learn_from_outcome did not update node: {payload}")
            return f"updated={payload.get('updated')}"

        step("learn_from_outcome", s_learn)

        goal_id: Dict[str, str] = {}

        def s_create_goal() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "manage_goal",
                {
                    "operation": "create_goal",
                    "payload": json.dumps({"title": f"MCP e2e regression goal {int(time.time())}", "priority": "high"}),
                },
            )
            rid += 1
            if payload.get("status") != "ok":
                raise E2EError(f"create_goal failed: {payload}")
            result = payload.get("result", {})
            gid = result.get("id")
            if not isinstance(gid, str) or not gid:
                raise E2EError(f"create_goal missing id: {payload}")
            goal_id["value"] = gid
            return gid

        step("manage_goal create_goal", s_create_goal)

        def s_link_nodes() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "manage_goal",
                {
                    "operation": "link_nodes",
                    "goal_id": goal_id["value"],
                    "node_ids": json.dumps([node_id["value"]]),
                },
            )
            rid += 1
            if payload.get("status") != "ok":
                raise E2EError(f"link_nodes failed: {payload}")
            return "linked=1"

        step("manage_goal link_nodes", s_link_nodes)

        def s_review_goal() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "review_goal",
                {
                    "goal_id": goal_id["value"],
                    "signal": json.dumps(
                        {
                            "retrieved_nodes": [{"id": node_id["value"]}],
                            "outcomes": [{"status": "success", "confidence": 0.9}],
                            "contradictions": 0,
                        }
                    ),
                    "apply_decision": "false",
                    "options": "{}",
                    "transition_metadata": "{}",
                },
            )
            rid += 1
            if payload.get("status") != "ok":
                raise E2EError(f"review_goal failed: {payload}")
            return f"decision={payload.get('decision', 'unknown')}"

        step("review_goal", s_review_goal)

        def s_query_post() -> str:
            nonlocal rid
            payload = _tool_call(
                client,
                rid,
                "query_graph",
                {"operation": "similarity_search", "query": e2e_token},
            )
            rid += 1
            if payload.get("status") != "ok":
                raise E2EError(f"query_graph post similarity_search failed: {payload}")

            result = payload.get("result", {})
            count = result.get("count", 0)
            if not isinstance(count, int):
                raise E2EError(f"query_graph post count invalid: {payload}")
            if count < 1:
                raise E2EError(f"query_graph post expected at least 1 match for token {e2e_token!r}")

            matches = result.get("matches", [])
            saw_token = (
                isinstance(matches, list)
                and any(
                    isinstance(m, dict) and e2e_token in str(m.get("content", ""))
                    for m in matches
                )
            )
            if not saw_token:
                raise E2EError(f"query_graph post did not include token {e2e_token!r} in matches: {matches}")

            return f"post_matches={count}"

        step("query_graph post similarity_search", s_query_post)

    finally:
        global LAST_STDERR_LINES
        LAST_STDERR_LINES = list(stderr_lines)

        client.close()
        _terminate_process(proc)

    return steps, stderr_lines


def build_parser() -> argparse.ArgumentParser:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))

    p = argparse.ArgumentParser(description="Graphonomous MCP E2E regression script")
    p.add_argument("--cwd", default=project_root, help="Working directory where server command runs")
    p.add_argument(
        "--command",
        default=DEFAULT_COMMAND,
        help=(
            "Server command template. Default uses local wrapper script. "
            "You can pass scripts via argv mode (default) or raw shell command with --shell. "
            "Supported placeholders: {db_path}, {embedder_backend}, {request_timeout_ms}, {log_level}."
        ),
    )
    p.add_argument("--shell", action="store_true", help="Run command through shell=True")
    p.add_argument("--db-path", default=DEFAULT_DB_PATH, help="Path to SQLite DB file")
    p.add_argument("--embedder-backend", default="fallback", choices=["auto", "fallback"])
    p.add_argument("--request-timeout-ms", type=int, default=DEFAULT_REQUEST_TIMEOUT_MS)
    p.add_argument("--log-level", default="error", choices=["debug", "info", "warning", "error"])
    p.add_argument("--io-timeout-s", type=float, default=DEFAULT_IO_TIMEOUT_S)
    p.add_argument("--tee-stderr", action="store_true", help="Mirror server stderr to this process stderr")
    return p


def main() -> int:
    args = build_parser().parse_args()
    t0 = time.monotonic()

    try:
        steps, stderr_lines = run_e2e(args)
    except Exception as exc:
        elapsed_ms = (time.monotonic() - t0) * 1000.0
        print("❌ MCP e2e regression FAILED")
        print(f"  total: {elapsed_ms:.1f} ms")
        print(f"  error: {exc}")

        if LAST_STDERR_LINES:
            print("  --- stderr tail (last 40 lines) ---")
            tail = LAST_STDERR_LINES[-40:]
            for line in tail:
                print(f"  {line.rstrip()}")
            print("  --- end stderr tail ---")

        return 1

    elapsed_ms = (time.monotonic() - t0) * 1000.0
    print("✅ MCP e2e regression PASSED")
    for s in steps:
        status = "ok" if s.ok else "fail"
        detail = f" ({s.details})" if s.details else ""
        print(f"  - {s.name}: {s.latency_ms:.1f} ms [{status}]{detail}")
    print(f"  total: {elapsed_ms:.1f} ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
