#!/usr/bin/env python3
"""
Automated regression tests for mcp_deployed_smoke.py.

Validates, against a mock HTTP server, that the deployed smoke driver:
  - Performs initialize with correct protocol negotiation
  - Preserves the mcp-session-id from initialize through all later requests
  - Executes all five loop phases in order: retrieve → route → act → learn → consolidate
  - Carries verifiable evidence from each phase to the next
  - Produces correct execution certificates with valid rungs, claims, and gaps
  - Handles failure modes: unreachable, timeout, auth failure, malformed
    response, missing session ID, JSON-RPC error, unobserved outcome,
    evidence chain break
  - Never emits live_deployed for a failed or unattempted phase
  - Records failed phases as named GAPs
  - Includes the retraction of the input_schema/0 implication
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
    """Configurable mock Streamable HTTP MCP server for the five-phase loop."""

    # Class-level config — set before starting server
    session_id: str = "test-session-abc123"
    behavior: str = "happy"
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
            "params": message.get("params"),
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

        if tool_name == "retrieve":
            self._handle_retrieve(msg_id, arguments)
        elif tool_name == "route":
            self._handle_route(msg_id, arguments)
        elif tool_name == "act":
            self._handle_act(msg_id, arguments)
        elif tool_name == "learn":
            self._handle_learn(msg_id, arguments)
        elif tool_name == "consolidate":
            self._handle_consolidate(msg_id, arguments)
        else:
            self._send_tool_result(msg_id, {})

    def _handle_retrieve(self, msg_id, arguments):
        if self.__class__.behavior == "retrieve_miss":
            # Return empty results — evidence chain break on consolidation verify
            self._send_tool_result(msg_id, {
                "nodes": [],
                "topology": {"routing": "fast"},
            })
        elif self.__class__.behavior == "evidence_break":
            # First retrieve works, second (consolidation verify) returns empty
            calls = [r for r in self.__class__.request_log
                     if r.get("params", {}).get("name") == "retrieve"]
            if len(calls) > 1:
                self._send_tool_result(msg_id, {"nodes": [], "topology": {}})
            else:
                self._send_tool_result(msg_id, {
                    "nodes": [],
                    "topology": {"routing": "fast"},
                })
        else:
            # Return nodes that include the pass token for verification
            query = arguments.get("query", "")
            self._send_tool_result(msg_id, {
                "nodes": [
                    {
                        "id": self.__class__.stored_node_id,
                        "content": f"Five-phase closed pass [{query}]",
                    },
                ],
                "topology": {"routing": "fast", "kappa": 0},
            })

    def _handle_route(self, msg_id, arguments):
        if self.__class__.behavior == "route_fail":
            self._send_jsonrpc_response(msg_id, error={
                "code": -32600,
                "message": "route failed",
            })
        else:
            self._send_tool_result(msg_id, {
                "routing": "fast",
                "kappa": 0,
                "components": 1,
            })

    def _handle_act(self, msg_id, arguments):
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

    def _handle_learn(self, msg_id, arguments):
        if self.__class__.behavior == "learn_fail":
            self._send_tool_result(msg_id, {"status": "error"})
        else:
            self._send_tool_result(msg_id, {
                "action_id": arguments.get("action_id", "test"),
                "updated": 1,
            })

    def _handle_consolidate(self, msg_id, arguments):
        if self.__class__.behavior == "consolidate_fail":
            self._send_jsonrpc_response(msg_id, error={
                "code": -32600,
                "message": "consolidation failed",
            })
        else:
            self._send_tool_result(msg_id, {"status": "completed"})

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
    """Verify the full five-phase closed pass: initialize → retrieve → route → act → learn → consolidate."""

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

    def test_full_pass_all_five_phases(self):
        cert = self._run()
        self.assertTrue(cert.overall_ok)
        self.assertIsNone(cert.failure_reason)
        # 6 steps: initialize + 5 loop phases
        self.assertEqual(len(cert.phases), 6)

        phase_names = [s["name"] for s in cert.phases]
        self.assertEqual(phase_names,
                         ["initialize", "retrieve", "route", "act", "learn", "consolidate"])

        for s in cert.phases:
            self.assertTrue(s["ok"])
            self.assertEqual(s["rung"], "live_deployed")
            self.assertIn(s["rung"], VALID_RUNGS)

    def test_certificate_fields(self):
        cert = self._run()
        d = cert.to_dict()
        self.assertEqual(d["claim"], smoke.CLAIM_NAME)
        self.assertEqual(d["prior_rung"], "in_tree")
        self.assertEqual(d["awarded_rung"], "live_deployed")
        self.assertTrue(d["pass_id"].startswith("pass-"))
        self.assertEqual(d["exit_status"], 0)
        self.assertIn("retraction", d)
        self.assertIn("RETRACTED", d["retraction"])
        self.assertIn("input_schema", d["retraction"])
        self.assertEqual(d["gaps"], [])

    def test_session_id_preserved(self):
        cert = self._run()
        self.assertEqual(cert.session_id, "test-session-abc123")

        # All requests after initialize should include the session header
        logs = MockMCPHandler.request_log
        # First request (initialize) has no session header
        self.assertIsNone(logs[0]["session_header"])
        # All subsequent requests should have it
        for log in logs[1:]:
            self.assertEqual(log["session_header"], "test-session-abc123")

    def test_evidence_chain_flows_between_phases(self):
        cert = self._run()
        phases = cert.phases

        # Phase 1 (retrieve) produces routing evidence
        self.assertIsNotNone(phases[1]["evidence_produced"])
        self.assertIn("routing=", phases[1]["evidence_produced"])

        # Phase 2 (route) consumes retrieve's routing, produces decision
        self.assertIsNotNone(phases[2]["evidence_consumed"])
        self.assertIn("retrieve_routing=", phases[2]["evidence_consumed"])
        self.assertIsNotNone(phases[2]["evidence_produced"])
        self.assertIn("decision=", phases[2]["evidence_produced"])

        # Phase 3 (act) consumes route's decision, produces node_id
        self.assertIsNotNone(phases[3]["evidence_consumed"])
        self.assertIn("route_decision=", phases[3]["evidence_consumed"])
        self.assertIsNotNone(phases[3]["evidence_produced"])
        self.assertIn("node_id=", phases[3]["evidence_produced"])

        # Phase 4 (learn) consumes act's node_id, produces action_id
        self.assertIsNotNone(phases[4]["evidence_consumed"])
        self.assertIn("act_node_id=", phases[4]["evidence_consumed"])
        self.assertIsNotNone(phases[4]["evidence_produced"])
        self.assertIn("action_id=", phases[4]["evidence_produced"])

        # Phase 5 (consolidate) consumes act's node_id and learn's action_id
        self.assertIsNotNone(phases[5]["evidence_consumed"])
        self.assertIn("act_node_id=", phases[5]["evidence_consumed"])
        self.assertIn("learn_action_id=", phases[5]["evidence_consumed"])

    def test_evidence_bundle_written(self):
        cert = self._run()
        smoke.write_evidence(cert, self.output)

        with open(self.output) as f:
            data = json.load(f)

        self.assertIn("claim", data)
        self.assertIn("prior_rung", data)
        self.assertIn("awarded_rung", data)
        self.assertIn("pass_id", data)
        self.assertIn("substrate", data)
        self.assertIn("settling_command", data)
        self.assertIn("exit_status", data)
        self.assertIn("phases", data)
        self.assertIn("gaps", data)
        self.assertIn("retraction", data)

        # No secrets in the bundle
        raw = json.dumps(data)
        self.assertNotIn("Bearer", raw)
        self.assertNotIn("GRAPHONOMOUS_MCP_TOKEN", raw)

        # Rungs are valid
        for s in data["phases"]:
            self.assertIn(s["rung"], VALID_RUNGS)

    def test_phase_order_is_canonical_loop(self):
        cert = self._run()
        phase_names = [s["name"] for s in cert.phases]
        # After initialize, the loop phases must be in canonical order
        self.assertEqual(phase_names[1:],
                         ["retrieve", "route", "act", "learn", "consolidate"])

    def test_unique_pass_id(self):
        cert = self._run()
        self.assertTrue(cert.pass_id.startswith("pass-"))
        self.assertGreater(len(cert.pass_id), 10)

    def test_timestamps_present(self):
        cert = self._run()
        self.assertTrue(cert.run_start)
        self.assertTrue(cert.run_end)
        for s in cert.phases:
            self.assertTrue(s["timestamp"])

    def test_no_gaps_on_success(self):
        cert = self._run()
        for s in cert.phases:
            self.assertFalse(s["gap"])
        self.assertEqual(cert.gaps, [])


class TestRouteFailure(unittest.TestCase):
    """Route phase failure → GAP, no live_deployed for route or later phases."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("route_fail")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_route_fail_gaps_remaining(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.awarded_rung, "in_tree")

        # initialize and retrieve should pass
        self.assertTrue(cert.phases[0]["ok"])
        self.assertTrue(cert.phases[1]["ok"])
        self.assertEqual(cert.phases[0]["rung"], "live_deployed")
        self.assertEqual(cert.phases[1]["rung"], "live_deployed")

        # route should fail, and act/learn/consolidate should be GAPs
        for s in cert.phases[2:]:
            self.assertFalse(s["ok"])
            self.assertNotEqual(s["rung"], "live_deployed")
            self.assertTrue(s["gap"])

        # GAPs should be recorded in certificate
        gap_names = [g["phase"] for g in cert.gaps]
        self.assertIn("route", gap_names)
        self.assertIn("act", gap_names)
        self.assertIn("learn", gap_names)
        self.assertIn("consolidate", gap_names)


class TestEvidenceChainBreak(unittest.TestCase):
    """Consolidation pre-check fails → evidence chain break."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("evidence_break")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_evidence_break_on_consolidation_verify(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_EVIDENCE_BREAK)
        self.assertEqual(cert.awarded_rung, "in_tree")

        # Phases up to learn should pass
        for s in cert.phases[:5]:  # initialize, retrieve, route, act, learn
            self.assertTrue(s["ok"])

        # Consolidate should be a GAP
        self.assertFalse(cert.phases[5]["ok"])
        self.assertTrue(cert.phases[5]["gap"])


class TestUnreachable(unittest.TestCase):
    """Endpoint unreachable → non-zero exit, named reason, no live_deployed."""

    def test_unreachable(self):
        args = smoke.parse_args([
            "--endpoint", "http://127.0.0.1:1/mcp",  # nothing listening
            "--output", "/dev/null",
            "--timeout-s", "2",
        ])
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertIn(cert.failure_reason, (
            smoke.FAILURE_UNREACHABLE,
            smoke.FAILURE_TIMEOUT,
        ))
        self.assertEqual(cert.awarded_rung, "in_tree")
        for s in cert.phases:
            self.assertNotEqual(s["rung"], "live_deployed")
            self.assertFalse(s["ok"])
        # All phases should be GAPs
        self.assertGreater(len(cert.gaps), 0)


class TestTimeout(unittest.TestCase):
    """Request timeout → non-zero exit, named reason, no live_deployed."""

    def setUp(self):
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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertIn(cert.failure_reason, (
            smoke.FAILURE_TIMEOUT,
            smoke.FAILURE_UNREACHABLE,
        ))
        self.assertEqual(cert.awarded_rung, "in_tree")
        for s in cert.phases:
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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_AUTH)
        self.assertEqual(cert.awarded_rung, "in_tree")
        for s in cert.phases:
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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_MALFORMED_RESPONSE)
        self.assertEqual(cert.awarded_rung, "in_tree")
        for s in cert.phases:
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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_MISSING_SESSION)
        self.assertEqual(cert.awarded_rung, "in_tree")
        for s in cert.phases:
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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_JSONRPC_ERROR)
        self.assertEqual(cert.awarded_rung, "in_tree")
        # Initialize should pass, retrieve (first tools/call) should fail
        init_step = cert.phases[0]
        self.assertTrue(init_step["ok"])
        self.assertEqual(init_step["rung"], "live_deployed")
        # Retrieve and remaining should not be live_deployed
        for s in cert.phases[1:]:
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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_UNOBSERVED_OUTCOME)
        self.assertEqual(cert.awarded_rung, "in_tree")
        # Initialize, retrieve, route should pass; act should fail
        self.assertTrue(cert.phases[0]["ok"])  # initialize
        self.assertTrue(cert.phases[1]["ok"])  # retrieve
        self.assertTrue(cert.phases[2]["ok"])  # route
        self.assertFalse(cert.phases[3]["ok"])  # act
        for s in cert.phases[3:]:
            self.assertFalse(s["ok"])
            self.assertNotEqual(s["rung"], "live_deployed")

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
        cert = smoke.run_deployed_smoke(args)
        self.assertFalse(cert.overall_ok)
        self.assertEqual(cert.failure_reason, smoke.FAILURE_UNOBSERVED_OUTCOME)
        # init, retrieve, route, act pass; learn fails
        for s in cert.phases[:4]:
            self.assertTrue(s["ok"])
        self.assertFalse(cert.phases[4]["ok"])  # learn


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
        cert = smoke.run_deployed_smoke(args)
        self.assertTrue(cert.overall_ok)

        # All requests should have the Authorization header
        for log in MockMCPHandler.request_log:
            self.assertEqual(log["authorization"], "Bearer secret-test-token")

        # Token must not appear in certificate
        cert_json = json.dumps(cert.to_dict())
        self.assertNotIn("secret-test-token", cert_json)


class TestNoSecretsInBundle(unittest.TestCase):
    """Execution certificate must not contain authorization secrets."""

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
        cert = smoke.run_deployed_smoke(args)
        cert_json = json.dumps(cert.to_dict())
        self.assertNotIn("query-secret", cert_json)


class TestRetraction(unittest.TestCase):
    """Certificate includes the explicit retraction of input_schema/0 claim."""

    def setUp(self):
        self.server, self.port, self.thread = _start_mock_server("happy")
        self.endpoint = f"http://127.0.0.1:{self.port}/mcp"

    def tearDown(self):
        self.server.shutdown()

    def test_retraction_in_certificate(self):
        args = smoke.parse_args([
            "--endpoint", self.endpoint,
            "--output", "/dev/null",
            "--timeout-s", "5",
        ])
        cert = smoke.run_deployed_smoke(args)
        self.assertIn("RETRACTED", cert.retraction)
        self.assertIn("input_schema", cert.retraction)
        self.assertIn("in_tree", cert.retraction)

    def test_retraction_in_module(self):
        """The retraction text exists in the module docstring."""
        self.assertIn("RETRACTION", smoke.__doc__)
        self.assertIn("input_schema", smoke.__doc__)


if __name__ == "__main__":
    unittest.main()
