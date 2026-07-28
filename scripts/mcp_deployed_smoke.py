#!/usr/bin/env python3
"""
Deployed MCP smoke test for Graphonomous.

Drives store → retrieve → learn → consolidate against a DEPLOYED Streamable HTTP
MCP endpoint (e.g. Fly.io) over the real network surface.  Never starts or
targets a local server.

Each step is validated against the observed server response and assigned a rung
on the evidence ladder:

    spec | in_tree | live_local | live_deployed | external

The script emits a machine-readable JSON evidence bundle and exits non-zero on
any failure, recording the failed or unattempted steps as `in_tree`.

WARNING: this command mutates deployed memory (it stores a smoke-test node).

Usage:
    python3 scripts/mcp_deployed_smoke.py \\
        --endpoint https://graphonomous-mcp.fly.dev/mcp \\
        --output tmp/mcp-deployed-smoke-evidence.json

Environment:
    GRAPHONOMOUS_MCP_ENDPOINT   — default endpoint URL
    GRAPHONOMOUS_MCP_TOKEN      — optional Bearer token
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_ENDPOINT = "https://graphonomous-mcp.fly.dev/mcp"
DEFAULT_PROTOCOL_VERSION = "2025-03-26"
CLIENT_NAME = "mcp-deployed-smoke"
CLIENT_VERSION = "1.0.0"

VALID_RUNGS = ("spec", "in_tree", "live_local", "live_deployed", "external")

# Named failure reasons (stable strings for machine consumption)
FAILURE_UNREACHABLE = "endpoint_unreachable"
FAILURE_TIMEOUT = "request_timeout"
FAILURE_AUTH = "authentication_failed"
FAILURE_MALFORMED_RESPONSE = "malformed_protocol_response"
FAILURE_MISSING_SESSION = "missing_session_id"
FAILURE_JSONRPC_ERROR = "jsonrpc_error"
FAILURE_UNOBSERVED_OUTCOME = "unobserved_tool_outcome"
FAILURE_PROTOCOL_HANDSHAKE = "protocol_handshake_failed"


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------


@dataclass
class StepRecord:
    """One step in the smoke-test flow."""
    name: str
    rung: str  # one of VALID_RUNGS
    ok: bool
    latency_ms: float = 0.0
    details: str = ""
    failure_reason: Optional[str] = None
    timestamp: str = field(default_factory=lambda: _now_iso())

    def __post_init__(self):
        assert self.rung in VALID_RUNGS, f"invalid rung: {self.rung}"


@dataclass
class EvidenceBundle:
    """Machine-readable evidence bundle for the entire run."""
    endpoint: str
    run_id: str
    run_start: str
    run_end: str = ""
    overall_ok: bool = False
    failure_reason: Optional[str] = None
    protocol_version: str = DEFAULT_PROTOCOL_VERSION
    session_id: Optional[str] = None
    steps: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "endpoint": self.endpoint,
            "run_id": self.run_id,
            "run_start": self.run_start,
            "run_end": self.run_end,
            "overall_ok": self.overall_ok,
            "failure_reason": self.failure_reason,
            "protocol_version": self.protocol_version,
            "session_id": self.session_id,
            "steps": self.steps,
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _redact_endpoint(endpoint: str) -> str:
    """Strip query-string tokens if any (the path is not secret)."""
    from urllib.parse import urlparse, urlunparse
    p = urlparse(endpoint)
    return urlunparse((p.scheme, p.netloc, p.path, "", "", ""))


class DeployedSmokeError(RuntimeError):
    """Raised on any protocol/validation failure."""
    def __init__(self, message: str, reason: str):
        super().__init__(message)
        self.reason = reason


# ---------------------------------------------------------------------------
# HTTP + JSON-RPC transport
# ---------------------------------------------------------------------------

class StreamableHTTPClient:
    """Minimal Streamable HTTP MCP client using only stdlib urllib."""

    def __init__(self, endpoint: str, timeout_s: float,
                 bearer_token: Optional[str] = None):
        self.endpoint = endpoint
        self.timeout_s = timeout_s
        self.bearer_token = bearer_token
        self.session_id: Optional[str] = None
        self._next_id = 1

    def _headers(self, *, include_session: bool = True) -> Dict[str, str]:
        h: Dict[str, str] = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        if include_session and self.session_id:
            h["mcp-session-id"] = self.session_id
        if self.bearer_token:
            h["Authorization"] = f"Bearer {self.bearer_token}"
        return h

    def _post(self, body: Dict[str, Any], *,
              include_session: bool = True) -> tuple:
        """POST JSON-RPC to the endpoint.  Returns (parsed_json, response_headers)."""
        data = json.dumps(body, separators=(",", ":")).encode("utf-8")
        headers = self._headers(include_session=include_session)
        req = Request(self.endpoint, data=data, headers=headers, method="POST")

        try:
            with urlopen(req, timeout=self.timeout_s) as resp:
                raw = resp.read()
                resp_headers = {k.lower(): v for k, v in resp.getheaders()}
                status = resp.status
        except HTTPError as exc:
            status = exc.code
            if status == 401 or status == 403:
                raise DeployedSmokeError(
                    f"Authentication failed (HTTP {status})",
                    FAILURE_AUTH,
                ) from exc
            # Read error body if available
            try:
                raw = exc.read()
            except Exception:
                raw = b""
            try:
                parsed = json.loads(raw) if raw else {}
            except Exception:
                parsed = {}
            raise DeployedSmokeError(
                f"HTTP {status}: {parsed}",
                FAILURE_MALFORMED_RESPONSE,
            ) from exc
        except URLError as exc:
            reason_str = str(exc.reason) if hasattr(exc, "reason") else str(exc)
            if "timed out" in reason_str.lower() or "timeout" in reason_str.lower():
                raise DeployedSmokeError(
                    f"Request timed out: {reason_str}",
                    FAILURE_TIMEOUT,
                ) from exc
            raise DeployedSmokeError(
                f"Endpoint unreachable: {reason_str}",
                FAILURE_UNREACHABLE,
            ) from exc
        except OSError as exc:
            raise DeployedSmokeError(
                f"Connection error: {exc}",
                FAILURE_UNREACHABLE,
            ) from exc

        if not raw:
            if status == 202:
                return {}, resp_headers
            raise DeployedSmokeError(
                f"Empty response body (HTTP {status})",
                FAILURE_MALFORMED_RESPONSE,
            )

        try:
            parsed = json.loads(raw.decode("utf-8"))
        except Exception as exc2:
            raise DeployedSmokeError(
                f"Response is not valid JSON: {raw[:200]!r}",
                FAILURE_MALFORMED_RESPONSE,
            ) from exc2

        if not isinstance(parsed, dict):
            raise DeployedSmokeError(
                f"Response is not a JSON object: {type(parsed).__name__}",
                FAILURE_MALFORMED_RESPONSE,
            )

        return parsed, resp_headers

    def request(self, method: str, params: Optional[Dict[str, Any]] = None,
                *, include_session: bool = True) -> Dict[str, Any]:
        """Send a JSON-RPC request and return the parsed response."""
        rid = self._next_id
        self._next_id += 1
        body: Dict[str, Any] = {
            "jsonrpc": "2.0",
            "id": rid,
            "method": method,
        }
        if params is not None:
            body["params"] = params

        parsed, resp_headers = self._post(body, include_session=include_session)

        # Capture session ID from response headers
        sid = resp_headers.get("mcp-session-id")
        if sid:
            self.session_id = sid

        # Check for JSON-RPC error
        if "error" in parsed:
            raise DeployedSmokeError(
                f"JSON-RPC error on {method}: {parsed['error']}",
                FAILURE_JSONRPC_ERROR,
            )

        return parsed

    def notify(self, method: str, params: Optional[Dict[str, Any]] = None) -> None:
        """Send a JSON-RPC notification (no id, no response expected)."""
        body: Dict[str, Any] = {
            "jsonrpc": "2.0",
            "method": method,
        }
        if params is not None:
            body["params"] = params

        self._post(body, include_session=True)

    def tool_call(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Call tools/call and extract the payload from the response."""
        resp = self.request("tools/call", {"name": name, "arguments": arguments})
        return _extract_tool_payload(resp)


def _extract_tool_payload(tool_call_resp: Dict[str, Any]) -> Dict[str, Any]:
    """Extract structured payload from a tools/call response."""
    result = tool_call_resp.get("result")
    if not isinstance(result, dict):
        raise DeployedSmokeError(
            f"tools/call result missing/invalid: {tool_call_resp}",
            FAILURE_MALFORMED_RESPONSE,
        )

    # Prefer structuredContent
    structured = result.get("structuredContent")
    if isinstance(structured, dict):
        return structured

    content = result.get("content")
    if not isinstance(content, list) or not content:
        return {}

    for item in content:
        if not isinstance(item, dict):
            continue
        text = item.get("text")
        if isinstance(text, str) and text.strip():
            try:
                decoded = json.loads(text)
                if isinstance(decoded, dict):
                    return decoded
            except Exception:
                pass
        for key in ("json", "structured", "data"):
            value = item.get(key)
            if isinstance(value, dict):
                return value

    raise DeployedSmokeError(
        f"tools/call payload unsupported shape: {tool_call_resp}",
        FAILURE_MALFORMED_RESPONSE,
    )


# ---------------------------------------------------------------------------
# Smoke-test flow
# ---------------------------------------------------------------------------

def run_deployed_smoke(args: argparse.Namespace) -> EvidenceBundle:
    """Execute the full deployed smoke test and return the evidence bundle."""
    run_id = f"deployed-smoke-{uuid.uuid4().hex[:12]}"
    run_token = f"smoke-{run_id}"
    bundle = EvidenceBundle(
        endpoint=_redact_endpoint(args.endpoint),
        run_id=run_id,
        run_start=_now_iso(),
        protocol_version=args.protocol_version,
    )

    client = StreamableHTTPClient(
        endpoint=args.endpoint,
        timeout_s=args.timeout_s,
        bearer_token=args.token,
    )

    # Ordered steps: initialize, store, retrieve, learn, consolidate
    step_names = ["initialize", "store", "retrieve", "learn", "consolidate"]
    completed_steps: List[StepRecord] = []

    def fail_remaining(from_idx: int, reason: str) -> None:
        """Mark all remaining steps as in_tree (unobserved)."""
        for i in range(from_idx, len(step_names)):
            completed_steps.append(StepRecord(
                name=step_names[i],
                rung="in_tree",
                ok=False,
                failure_reason=reason,
            ))

    try:
        # --- Step 0: initialize ---
        t0 = time.monotonic()
        try:
            init_resp = client.request(
                "initialize",
                {
                    "protocolVersion": args.protocol_version,
                    "capabilities": {},
                    "clientInfo": {"name": CLIENT_NAME, "version": CLIENT_VERSION},
                },
                include_session=False,
            )
        except DeployedSmokeError:
            raise
        except Exception as exc:
            raise DeployedSmokeError(str(exc), FAILURE_PROTOCOL_HANDSHAKE) from exc
        lat = (time.monotonic() - t0) * 1000.0

        # Validate initialize response
        result = init_resp.get("result")
        if not isinstance(result, dict):
            raise DeployedSmokeError(
                f"initialize result missing: {init_resp}",
                FAILURE_MALFORMED_RESPONSE,
            )
        pv = result.get("protocolVersion")
        if pv != args.protocol_version:
            raise DeployedSmokeError(
                f"protocolVersion mismatch: got={pv!r} expected={args.protocol_version!r}",
                FAILURE_MALFORMED_RESPONSE,
            )
        if not client.session_id:
            raise DeployedSmokeError(
                "Server did not return mcp-session-id header on initialize",
                FAILURE_MISSING_SESSION,
            )

        bundle.session_id = client.session_id

        # Send notifications/initialized
        client.notify("notifications/initialized", {})

        completed_steps.append(StepRecord(
            name="initialize",
            rung="live_deployed",
            ok=True,
            latency_ms=lat,
            details=f"server={result.get('serverInfo', {}).get('name', '?')}, "
                    f"session={client.session_id[:16]}...",
        ))

        # --- Step 1: store ---
        node_content = f"Deployed smoke test node [{run_token}]"
        t0 = time.monotonic()
        store_payload = client.tool_call("store_node", {
            "content": node_content,
            "node_type": "episodic",
            "source": "mcp_deployed_smoke",
        })
        lat = (time.monotonic() - t0) * 1000.0

        if store_payload.get("status") != "stored":
            raise DeployedSmokeError(
                f"store_node did not return status=stored: {store_payload}",
                FAILURE_UNOBSERVED_OUTCOME,
            )
        node_id = store_payload.get("node_id")
        if not isinstance(node_id, str) or not node_id:
            raise DeployedSmokeError(
                f"store_node missing node_id: {store_payload}",
                FAILURE_UNOBSERVED_OUTCOME,
            )

        completed_steps.append(StepRecord(
            name="store",
            rung="live_deployed",
            ok=True,
            latency_ms=lat,
            details=f"node_id={node_id}",
        ))

        # --- Step 2: retrieve ---
        t0 = time.monotonic()
        retrieve_payload = client.tool_call("retrieve_context", {
            "query": run_token,
            "max_results": 10,
        })
        lat = (time.monotonic() - t0) * 1000.0

        # Validate that the stored node appears in retrieval
        nodes = retrieve_payload.get("nodes", retrieve_payload.get("results", []))
        if not isinstance(nodes, list):
            raise DeployedSmokeError(
                f"retrieve_context did not return a nodes/results list: {retrieve_payload}",
                FAILURE_UNOBSERVED_OUTCOME,
            )

        found = any(
            isinstance(n, dict) and (
                run_token in str(n.get("content", ""))
                or n.get("id") == node_id
            )
            for n in nodes
        )
        if not found:
            raise DeployedSmokeError(
                f"retrieve_context did not return the stored node "
                f"(token={run_token!r}, node_id={node_id!r}): "
                f"got {len(nodes)} results",
                FAILURE_UNOBSERVED_OUTCOME,
            )

        completed_steps.append(StepRecord(
            name="retrieve",
            rung="live_deployed",
            ok=True,
            latency_ms=lat,
            details=f"found=true, results={len(nodes)}",
        ))

        # --- Step 3: learn ---
        t0 = time.monotonic()
        learn_payload = client.tool_call("learn_from_outcome", {
            "action_id": f"deployed-smoke-{run_id}",
            "status": "success",
            "confidence": 0.85,
            "causal_node_ids": json.dumps([node_id]),
            "evidence": json.dumps({"runner": "mcp_deployed_smoke", "run_id": run_id}),
        })
        lat = (time.monotonic() - t0) * 1000.0

        if learn_payload.get("action_id") is None:
            raise DeployedSmokeError(
                f"learn_from_outcome missing action_id: {learn_payload}",
                FAILURE_UNOBSERVED_OUTCOME,
            )

        completed_steps.append(StepRecord(
            name="learn",
            rung="live_deployed",
            ok=True,
            latency_ms=lat,
            details=f"updated={learn_payload.get('updated', '?')}",
        ))

        # --- Step 4: consolidate ---
        t0 = time.monotonic()
        consolidate_payload = client.tool_call("run_consolidation", {})
        lat = (time.monotonic() - t0) * 1000.0

        # Consolidation is best-effort; we just need a non-error response
        completed_steps.append(StepRecord(
            name="consolidate",
            rung="live_deployed",
            ok=True,
            latency_ms=lat,
            details=f"status={consolidate_payload.get('status', '?')}",
        ))

        bundle.overall_ok = True

    except DeployedSmokeError as exc:
        # Record the failing step
        current_idx = len(completed_steps)
        if current_idx < len(step_names):
            completed_steps.append(StepRecord(
                name=step_names[current_idx],
                rung="in_tree",
                ok=False,
                failure_reason=exc.reason,
                details=str(exc),
            ))
            fail_remaining(current_idx + 1, exc.reason)
        bundle.failure_reason = exc.reason
        bundle.overall_ok = False

    except Exception as exc:
        current_idx = len(completed_steps)
        reason = FAILURE_UNREACHABLE
        if current_idx < len(step_names):
            completed_steps.append(StepRecord(
                name=step_names[current_idx],
                rung="in_tree",
                ok=False,
                failure_reason=reason,
                details=str(exc),
            ))
            fail_remaining(current_idx + 1, reason)
        bundle.failure_reason = reason
        bundle.overall_ok = False

    bundle.run_end = _now_iso()
    bundle.steps = [asdict(s) for s in completed_steps]

    return bundle


# ---------------------------------------------------------------------------
# Evidence output
# ---------------------------------------------------------------------------

def write_evidence(bundle: EvidenceBundle, output_path: str) -> None:
    """Atomically write the evidence bundle to disk."""
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    tmp_path = output_path + ".tmp"
    try:
        with open(tmp_path, "w") as f:
            json.dump(bundle.to_dict(), f, indent=2)
            f.write("\n")
        os.replace(tmp_path, output_path)
    except Exception:
        # Clean up tmp on failure
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Deployed MCP smoke test for Graphonomous.  Drives "
            "store → retrieve → learn → consolidate against a DEPLOYED "
            "Streamable HTTP MCP endpoint and emits an evidence bundle."
        ),
        epilog=(
            "WARNING: this command mutates deployed memory.  "
            "Set GRAPHONOMOUS_MCP_ENDPOINT and GRAPHONOMOUS_MCP_TOKEN "
            "in the environment or pass --endpoint / --token."
        ),
    )
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("GRAPHONOMOUS_MCP_ENDPOINT", DEFAULT_ENDPOINT),
        help="Streamable HTTP MCP endpoint URL (default: $GRAPHONOMOUS_MCP_ENDPOINT or %(default)s).",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GRAPHONOMOUS_MCP_TOKEN"),
        help="Optional Bearer token for authentication (default: $GRAPHONOMOUS_MCP_TOKEN).",
    )
    parser.add_argument(
        "--timeout-s",
        type=float,
        default=30.0,
        help="Per-request HTTP timeout in seconds (default: %(default)s).",
    )
    parser.add_argument(
        "--protocol-version",
        default=DEFAULT_PROTOCOL_VERSION,
        help="MCP protocolVersion to negotiate (default: %(default)s).",
    )
    parser.add_argument(
        "--output", "-o",
        default="tmp/mcp-deployed-smoke-evidence.json",
        help="Path for the JSON evidence bundle (default: %(default)s).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print evidence bundle to stdout as JSON instead of human-readable summary.",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    bundle = run_deployed_smoke(args)
    write_evidence(bundle, args.output)

    if args.json:
        print(json.dumps(bundle.to_dict(), indent=2))
    else:
        status_icon = "PASS" if bundle.overall_ok else "FAIL"
        print(f"{'✅' if bundle.overall_ok else '❌'} Deployed MCP smoke test {status_icon}")
        print(f"  endpoint: {bundle.endpoint}")
        print(f"  run_id:   {bundle.run_id}")
        if bundle.session_id:
            print(f"  session:  {bundle.session_id[:24]}...")
        for s in bundle.steps:
            ok_str = "ok" if s["ok"] else "FAIL"
            reason_str = f" ({s['failure_reason']})" if s.get("failure_reason") else ""
            detail_str = f" [{s['details']}]" if s.get("details") and s["ok"] else ""
            print(f"  - {s['name']:14s} {s['rung']:14s} {ok_str}{reason_str}{detail_str}")
        if bundle.failure_reason:
            print(f"  failure: {bundle.failure_reason}")
        print(f"  evidence: {args.output}")

    return 0 if bundle.overall_ok else 1


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main())
