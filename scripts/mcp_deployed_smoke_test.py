#!/usr/bin/env python3
"""
Automated regression tests for mcp_deployed_smoke.py.

Validates, against a mock HTTP server, that the deployed smoke driver:
  - Performs initialize with correct protocol negotiation
  - Preserves the mcp-session-id from initialize through all later requests
  - Observes store → retrieve → learn → consolidate in order
  - Produces correct evidence bundles with valid rungs
  - Handles failure modes: unreachable, timeout, auth failure, malformed
    response, missing session ID, JSON-RPC error, unobserved outcome
  - Never emits live_deployed for a failed or unattempted step
"""

from __future__ import annotations

import http.server
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from typing import Any, Callable, Dict, List, Optional, Tuple

# Import the module under test
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcp_deployed_smoke as smoke

VALID_RUNGS = smoke.VALID_RUNGS

# ---------------------------------------------------------------------------
# Mock MCP server
# ---------------------------------------------------------------------------

class MockMCPHandler(http.server.BaseHTTPRequestHandler):
    """Configurable mock Streamable HTTP MCP server."""

    # Class-level config — set before starting server
    session_id: str = "test-session-abc123"
    behavior: str = "happy"  # happy | no_session | auth_fail | bad_json | jsonrpc_error | store_fail | retrieve_miss | learn_fail | consolidate_fail
    request_log: List[Dict[str, Any]] = []
    stored_node_id: str = "node-test-001"
    mcp_protocol_version: str = smoke.DEFAULT_PROTOCOL_VERSION

    def log_message(self, format, *args):
        pass  # Suppress stderr logging

    protocol_version = "HTTP/1.0"  # close after each response so urlopen doesn't hang

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # Auth check
        if self.__class__.behavior == "auth_fail":
            err_body = b'{"error":"unauthorized"}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
            return

        # Bad JSON response
        if self.__class__.behavior == "bad_json":
            bad = b'not json at all {{{'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(bad)))
            self.end_headers()
            self.wfile.write(bad)
            return

        try:
            message = json.loads(body)
        except Exception:
            self.send_response(400)
            self.end_headers()
            return

        self.__class__.request_log.append({
            "method": message.get("method"),
            "id": message.get("id"),
            "session_header": self.headers.get("mcp-session-id"),
            "authorization": self.headers.get("Authorization"),
        })

        method = message.get("method")
        msg_id = message.get("id")

        # Notifications (no id) → 202
        if msg_id is None:
            resp_body = b'{}'
            self.send_response(202)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(resp_body)))
            if self.__class__.session_id:
                self.send_header("mcp-session-id", self.__class__.session_id)
            self.end_headers()
            self.wfile.write(resp_body)
            return

        # JSON-RPC error behavior (after initialize)
        if self.__class__.behavior == "jsonrpc_error" and method == "tools/call":
            self._send_jsonrpc_response(msg_id, error={
                "code": -32600,
                "message": "Injected error",
            })
            return

        if method == "initialize":
            self._handle_initialize(msg_id, message)
        elif method == "tools/call":
            self._handle_tools_call(msg_id, message)
        else:
            self._send_jsonrpc_response(msg_id, result={})

    def _handle_initialize(self, msg_id, message):
        pv = self.__class__.mcp_protocol_version

        if self.__class__.behavior == "no_session":
            # Return valid response but without session header
            resp = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "protocolVersion": pv,
                    "serverInfo": {"name": "mock-graphonomous", "version": "0.0.1"},
                    "capabilities": {},
                },
            }
            body = json.dumps(resp).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            # Deliberately omit mcp-session-id
            self.end_headers()
            self.wfile.write(body)
            return

        self._send_jsonrpc_response(msg_id, result={
            "protocolVersion": pv,
            "serverInfo": {"name": "mock-graphonomous", "version": "0.0.1"},
            "capabilities": {},
        })

    def _handle_tools_call(self, msg_id, message):
        params = message.get("params", {})
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})

        # v2 machine surface: act, retrieve, learn, consolidate
        if tool_name == "act":
            action = arguments.get("action", "")
            if action == "store_node":
                if self.__class__.behavior == "store_fail":
                    self._send_tool_result(msg_id, {"status": "error", "message": "disk full"})
                else:
                    self._send_tool_result(msg_id, {
                        "status": "stored",
                        "node_id": self.__class__.stored_node_id,
                    })
            else:
                self._send_tool_result(msg_id, {})
        elif tool_name == "retrieve":
            if self.__class__.behavior == "retrieve_miss":
                self._send_tool_result(msg_id, {"nodes": []})
            else:
                self._send_tool_result(msg_id, {
                    "nodes": [
                        {"id": self.__class__.stored_node_id, "content": "Deployed smoke test node [smoke-deployed-smoke-test123]"},
                    ],
                })
        elif tool_name == "learn":
            if self.__class__.behavior == "learn_fail":
                self._send_tool_result(msg_id, {"status": "error"})
            else:
                self._send_tool_result(msg_id, {
                    "action_id": arguments.get("action_id", "test"),
                    "updated": 1,
                })
        elif tool_name == "consolidate":
            if self.__class__.behavior == "consolidate_fail":
                self._send_jsonrpc_response(msg_id, error={
                    "code": -32600,
                    "message": "consolidation failed",
                })
            else:
                self._send_tool_result(msg_id, {"status": "completed"})
        else:
            self._send_tool_result(msg_id, {})

    def _send_jsonrpc_response(self, msg_id, *, result=None, error=None):
        resp: Dict[str, Any] = {"jsonrpc": "2.0", "id": msg_id}
        if error is not None:
            resp["error"] = error
        else:
            resp["result"] = result

        body = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if self.__class__.session_id:
            self.send_header("mcp-session-id", self.__class__.session_id)
        self.end_headers()
        self.wfile.write(body)

    def _send_tool_result(self, msg_id, payload: Dict[str, Any]):
        result = {
            "content": [
                {"type": "text", "text": json.dumps(payload)},
            ],
        }
        self._send_jsonrpc_response(msg_id, result=result)


def _start_mock_server(behavior: str = "happy",
                       session_id: str = "test-session-abc123",
                       ) -> Tuple[http.server.HTTPServer, int, threading.Thread]:
    """Start a mock MCP server on a random port."""
    MockMCPHandler.behavior = behavior
    MockMCPHandler.session_id = session_id
    MockMCPHandler.request_log = []

    server = http.server.HTTPServer(("127.0.0.1", 0), MockMCPHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, port, thread


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

class TestHappyPath(unittest.TestCase):
    """Verify the full initialize → store → retrieve → learn → consolidate path."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("happy")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"
        self.tmpdir = tempfile.mkdtemp()
        self.output = os.path.join(self.tmpdir, "evidence.json")

    def tearDown(self):
        self.server.shutdown()

    def _run(self, **kwargs):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", self.output,
            "--timeout-s", "5",
        ] + [item for k, v in kwargs.items() for item in [f"--{k}", str(v)]])
        return smoke.run_deployed_smoke(args)

    def test_full_pass(self):
        bundle = self._run()
        self.assertTrue(bundle.overall_ok)
        self.assertIsNone(bundle.failure_reason)
        self.assertEqual(len(bundle.steps), 5)

        step_names = [s.name for s in [smoke.StepRecord(**s) for s in bundle.steps]]
        self.assertEqual(step_names, ["initialize", "store", "retrieve", "learn", "consolidate"])

        for s in bundle.steps:
            self.assertTrue(s["ok"])
            self.assertEqual(s["rung"], "live_deployed")
            self.assertIn(s["rung"], VALID_RUNGS)

    def test_session_id_preserved(self):
        bundle = self._run()
        self.assertEqual(bundle.session_id, "test-session-abc123")

        # All requests after initialize should include the session header
        logs = MockMCPHandler.request_log
        # First request (initialize) has no session header
        self.assertIsNone(logs[0]["session_header"])
        # All subsequent requests should have it
        for log in logs[1:]:
            if log["method"] != "notifications/initialized":
                # notifications/initialized is fire-and-forget
                pass
            self.assertEqual(log["session_header"], "test-session-abc123")

    def test_evidence_bundle_written(self):
        bundle = self._run()
        smoke.write_evidence(bundle, self.output)

        with open(self.output) as f:
            data = json.load(f)

        self.assertIn("endpoint", data)
        self.assertIn("run_id", data)
        self.assertIn("run_start", data)
        self.assertIn("run_end", data)
        self.assertIn("overall_ok", data)
        self.assertIn("steps", data)
        self.assertIn("protocol_version", data)
        self.assertIn("session_id", data)

        # No secrets in the bundle
        raw = json.dumps(data)
        self.assertNotIn("Bearer", raw)
        self.assertNotIn("GRAPHONOMOUS_MCP_TOKEN", raw)

        # Rungs are valid
        for s in data["steps"]:
            self.assertIn(s["rung"], VALID_RUNGS)

    def test_step_order_is_store_retrieve_learn_consolidate(self):
        bundle = self._run()
        step_names = [s["name"] for s in bundle.steps]
        # After initialize, the loop steps must be in this exact order
        self.assertEqual(step_names[1:], ["store", "retrieve", "learn", "consolidate"])

    def test_unique_run_token_in_store(self):
        bundle = self._run()
        self.assertIn("run_id", bundle.to_dict())
        self.assertTrue(bundle.run_id.startswith("deployed-smoke-"))

    def test_timestamps_present(self):
        bundle = self._run()
        self.assertTrue(bundle.run_start)
        self.assertTrue(bundle.run_end)
        for s in bundle.steps:
            self.assertTrue(s["timestamp"])


class TestUnreachable(unittest.TestCase):
    """Endpoint unreachable → non-zero exit, named reason, no live_deployed."""

    def test_unreachable(self):
        args = smoke.parse_args([
            "--endpoint", "http://127.0.0.1:1/mcp",  # nothing listening
            "--output", "/dev/null",
            "--timeout-s", "2",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertIn(bundle.failure_reason, (
            smoke.FAILURE_UNREACHABLE,
            smoke.FAILURE_TIMEOUT,
        ))
        for s in bundle.steps:
            self.assertNotEqual(s["rung"], "live_deployed")
            self.assertFalse(s["ok"])


class TestTimeout(unittest.TestCase):
    """Request timeout → non-zero exit, named reason, no live_deployed."""

    def setUp(self):
        # Start a server that never responds
        import socketserver
        class SilentHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                time.sleep(60)  # hang
            def log_message(self, *a):
                pass
        self.server = http.server.HTTPServer(("127.0.0.1", 0), SilentHandler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()

    def test_timeout(self):
        args = smoke.parse_args([
            "--endpoint", f"http://127.0.0.1:{self.port}/mcp",
            "--output", "/dev/null",
            "--timeout-s", "1",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertIn(bundle.failure_reason, (
            smoke.FAILURE_TIMEOUT,
            smoke.FAILURE_UNREACHABLE,
        ))
        for s in bundle.steps:
            self.assertNotEqual(s["rung"], "live_deployed")


class TestAuthFailure(unittest.TestCase):
    """HTTP 401 → named auth failure reason."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("auth_fail")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_auth_fail(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_AUTH)
        for s in bundle.steps:
            self.assertNotEqual(s["rung"], "live_deployed")


class TestMalformedResponse(unittest.TestCase):
    """Non-JSON response → named malformed reason."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("bad_json")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_malformed(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_MALFORMED_RESPONSE)
        for s in bundle.steps:
            self.assertNotEqual(s["rung"], "live_deployed")


class TestMissingSession(unittest.TestCase):
    """Server omits mcp-session-id → named missing_session_id failure."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server(
            "no_session", session_id=""
        )
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_missing_session(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_MISSING_SESSION)
        for s in bundle.steps:
            self.assertNotEqual(s["rung"], "live_deployed")


class TestJsonRpcError(unittest.TestCase):
    """JSON-RPC error on tools/call → named jsonrpc_error failure."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("jsonrpc_error")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_jsonrpc_error(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_JSONRPC_ERROR)
        # Initialize should pass, store should fail
        init_step = bundle.steps[0]
        self.assertTrue(init_step["ok"])
        self.assertEqual(init_step["rung"], "live_deployed")
        # The store step and remaining should not be live_deployed
        for s in bundle.steps[1:]:
            self.assertNotEqual(s["rung"], "live_deployed")
            self.assertFalse(s["ok"])


class TestUnobservedOutcome(unittest.TestCase):
    """Store returns unexpected status → named unobserved_tool_outcome."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("store_fail")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_store_fail(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_UNOBSERVED_OUTCOME)
        # Initialize ok, store fails, rest unattempted
        self.assertTrue(bundle.steps[0]["ok"])
        self.assertEqual(bundle.steps[0]["rung"], "live_deployed")
        for s in bundle.steps[1:]:
            self.assertFalse(s["ok"])
            self.assertNotEqual(s["rung"], "live_deployed")

    def test_retrieve_miss(self):
        """Retrieve doesn't find the stored node → unobserved outcome."""
        self.server.shutdown()
        self.server, self.port, self.thread = _start_mock_server("retrieve_miss")
        endpoint = f"http://127.0.0.1:{self.port}/mcp"
        args = smoke.parse_args([
            "--endpoint", endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_UNOBSERVED_OUTCOME)
        # init and store pass, retrieve fails
        self.assertTrue(bundle.steps[0]["ok"])
        self.assertTrue(bundle.steps[1]["ok"])
        self.assertFalse(bundle.steps[2]["ok"])

    def test_learn_fail(self):
        """Learn returns no action_id → unobserved outcome."""
        self.server.shutdown()
        self.server, self.port, self.thread = _start_mock_server("learn_fail")
        endpoint = f"http://127.0.0.1:{self.port}/mcp"
        args = smoke.parse_args([
            "--endpoint", endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertFalse(bundle.overall_ok)
        self.assertEqual(bundle.failure_reason, smoke.FAILURE_UNOBSERVED_OUTCOME)
        # init, store, retrieve pass; learn fails
        for s in bundle.steps[:3]:
            self.assertTrue(s["ok"])
        self.assertFalse(bundle.steps[3]["ok"])


class TestExitCode(unittest.TestCase):
    """main() returns 0 on success, non-zero on failure."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("happy")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"
        self.tmpdir = tempfile.mkdtemp()

    def tearDown(self):
        self.server.shutdown()

    def test_exit_zero_on_success(self):
        output = os.path.join(self.tmpdir, "evidence.json")
        code = smoke.main([
            "--endpoint", self.endpoint,
            "--output", output,
            "--timeout-s", "5",
        ])
        self.assertEqual(code, 0)

    def test_exit_nonzero_on_failure(self):
        code = smoke.main([
            "--endpoint", "http://127.0.0.1:1/mcp",
            "--output", os.path.join(self.tmpdir, "fail.json"),
            "--timeout-s", "1",
        ])
        self.assertNotEqual(code, 0)


class TestBearerToken(unittest.TestCase):
    """Bearer token is sent in Authorization header when provided."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("happy")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_token_sent(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
            "--token", "secret-test-token",
        ])
        bundle = smoke.run_deployed_smoke(args)
        self.assertTrue(bundle.overall_ok)

        # All requests should have the Authorization header
        for log in MockMCPHandler.request_log:
            self.assertEqual(log["authorization"], "Bearer secret-test-token")

        # Token must not appear in evidence bundle
        bundle_json = json.dumps(bundle.to_dict())
        self.assertNotIn("secret-test-token", bundle_json)


class TestNoSecretsInBundle(unittest.TestCase):
    """Evidence bundle must not contain authorization secrets."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("happy")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp?token=query-secret"
        self.tmpdir = tempfile.mkdtemp()

    def tearDown(self):
        self.server.shutdown()

    def test_no_query_params_in_endpoint(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", os.path.join(self.tmpdir, "evidence.json"),
            "--timeout-s", "5",
        ])
        bundle = smoke.run_deployed_smoke(args)
        bundle_json = json.dumps(bundle.to_dict())
        self.assertNotIn("query-secret", bundle_json)


if __name__ == "__main__":
    unittest.main()
