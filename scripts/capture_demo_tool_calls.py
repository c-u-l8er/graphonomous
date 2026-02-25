#!/usr/bin/env python3
"""
Capture real Graphonomous MCP tool-call payloads for the demo scenario.

This script runs a realistic training + query sequence and outputs
JSON payloads that can be embedded into the demo.html showcase page.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, asdict
from typing import Any, Dict, List, Optional

# Import from the regression script
import importlib.util
import sys

spec = importlib.util.spec_from_file_location(
    "mcp_e2e_regression",
    os.path.join(os.path.dirname(__file__), "mcp_e2e_regression.py"),
)
mcp_mod = importlib.util.module_from_spec(spec)
sys.modules["mcp_e2e_regression"] = mcp_mod
spec.loader.exec_module(mcp_mod)

DEFAULT_DB_PATH = "~/.graphonomous/knowledge-demo-capture.db"


@dataclass
class CapturedCall:
    tool: str
    arguments: Dict[str, Any]
    result: Dict[str, Any]
    latency_ms: float


def run_capture(args: argparse.Namespace) -> Dict[str, Any]:
    """Run the demo scenario and capture all payloads."""
    db_path = os.path.expanduser(args.db_path)
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    command = mcp_mod.DEFAULT_COMMAND.format(
        db_path=db_path,
        embedder_backend=args.embedder_backend,
        request_timeout_ms=args.request_timeout_ms,
        log_level=args.log_level,
    )

    command_argv = shlex.split(command)
    stderr_lines: List[str] = []

    proc = subprocess.Popen(
        command_argv,
        cwd=args.cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )

    stderr_thread = threading.Thread(
        target=mcp_mod._pump_stderr,
        args=(proc.stderr, stderr_lines, args.tee_stderr),
        daemon=True,
    )
    stderr_thread.start()

    client = mcp_mod.MCPStdioClient(proc=proc, io_timeout_s=args.io_timeout_s)
    rid = 1
    captured: List[CapturedCall] = []
    output: Dict[str, Any] = {
        "scenario": "codebase_skill_learning",
        "timestamp": time.time(),
        "calls": [],
        "summary": {},
    }

    def request(method: str, params: Dict[str, Any]) -> Dict[str, Any]:
        nonlocal rid
        resp = client.request(rid, method, params)
        rid += 1
        return resp

    def tool_call(name: str, arguments: Dict[str, Any]) -> CapturedCall:
        nonlocal rid
        t0 = time.monotonic()
        payload = mcp_mod._tool_call(client, rid, name, arguments)
        latency = (time.monotonic() - t0) * 1000.0
        rid += 1
        call = CapturedCall(
            tool=name,
            arguments=arguments,
            result=payload,
            latency_ms=latency,
        )
        captured.append(call)
        return call

    try:
        # Initialize
        init_resp = request(
            "initialize",
            {
                "protocolVersion": mcp_mod.DEFAULT_PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {
                    "name": "graphonomous-demo-capture",
                    "version": "0.1.0",
                },
            },
        )
        output["initialize"] = init_resp.get("result", {})

        client.send(
            {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}
        )

        # Tools list
        tools_resp = request("tools/list", {})
        tools = [
            t.get("name")
            for t in tools_resp.get("result", {}).get("tools", [])
            if isinstance(t, dict)
        ]
        output["tools_list"] = tools

        # Generate unique token for this run
        token = f"demo-skill-{int(time.time())}"
        output["token"] = token

        # Scenario A: Baseline query (no repo-specific skills)
        baseline_query = tool_call(
            "query_graph",
            {
                "operation": "similarity_search",
                "query": "trace request flow from route to persistence in unfamiliar codebase",
            },
        )
        output["scenario_a"] = {
            "query_graph": {
                "request": baseline_query.arguments,
                "response": baseline_query.result,
                "latency_ms": baseline_query.latency_ms,
            }
        }

        # Scenario B: Training - store procedural skills
        skill_1 = tool_call(
            "store_node",
            {
                "node_type": "procedural",
                "source": "graphonomous.com_demo",
                "content": f"Skill: Request Path Trace [{token}] - Identify route modules, map handlers, follow service calls, then persistence adapters in order.",
            },
        )

        skill_2 = tool_call(
            "store_node",
            {
                "node_type": "procedural",
                "source": "graphonomous.com_demo",
                "content": f"Skill: Flag Path Trace [{token}] - Find flag declaration, rollout gates, and fallback branches.",
            },
        )

        skill_3 = tool_call(
            "store_node",
            {
                "node_type": "procedural",
                "source": "graphonomous.com_demo",
                "content": f"Skill: Coverage Gap Scan [{token}] - Map critical path and identify missing integration assertions.",
            },
        )

        node_ids = [
            skill_1.result.get("node_id"),
            skill_2.result.get("node_id"),
            skill_3.result.get("node_id"),
        ]

        output["store_skills"] = {
            "skill_1": {
                "request": skill_1.arguments,
                "response": skill_1.result,
                "latency_ms": skill_1.latency_ms,
            },
            "skill_2": {
                "request": skill_2.arguments,
                "response": skill_2.result,
                "latency_ms": skill_2.latency_ms,
            },
            "skill_3": {
                "request": skill_3.arguments,
                "response": skill_3.result,
                "latency_ms": skill_3.latency_ms,
            },
            "node_ids": node_ids,
        }

        # Learn from outcome
        learn = tool_call(
            "learn_from_outcome",
            {
                "action_id": f"train-codebase-skills-{int(time.time())}",
                "status": "success",
                "confidence": 0.93,
                "causal_node_ids": json.dumps(node_ids),
                "evidence": json.dumps(
                    {
                        "runner": "graphonomous.com_demo",
                        "signal": "answer_quality_high",
                        "reviewer": "developer",
                    }
                ),
            },
        )

        output["learn_from_outcome"] = {
            "request": learn.arguments,
            "response": learn.result,
            "latency_ms": learn.latency_ms,
        }

        # Goal lifecycle
        create_goal = tool_call(
            "manage_goal",
            {
                "operation": "create_goal",
                "payload": json.dumps(
                    {
                        "title": f"Ship codebase onboarding assistant [{token}]",
                        "priority": "high",
                    }
                ),
            },
        )

        goal_id = create_goal.result.get("result", {}).get("id")

        link_nodes = tool_call(
            "manage_goal",
            {
                "operation": "link_nodes",
                "goal_id": goal_id,
                "node_ids": json.dumps(node_ids),
            },
        )

        review = tool_call(
            "review_goal",
            {
                "goal_id": goal_id,
                "signal": json.dumps(
                    {
                        "retrieved_nodes": [{"id": nid} for nid in node_ids if nid],
                        "outcomes": [{"status": "success", "confidence": 0.93}],
                        "contradictions": 0,
                    }
                ),
                "apply_decision": "true",
                "options": "{}",
                "transition_metadata": json.dumps({"source": "graphonomous.com_demo"}),
            },
        )

        output["goal_lifecycle"] = {
            "create_goal": {
                "request": create_goal.arguments,
                "response": create_goal.result,
                "latency_ms": create_goal.latency_ms,
            },
            "link_nodes": {
                "request": link_nodes.arguments,
                "response": link_nodes.result,
                "latency_ms": link_nodes.latency_ms,
            },
            "review_goal": {
                "request": review.arguments,
                "response": review.result,
                "latency_ms": review.latency_ms,
            },
            "goal_id": goal_id,
        }

        # Scenario B: Repeat query with learned skills
        repeat_query = tool_call(
            "query_graph",
            {
                "operation": "similarity_search",
                "query": token,
            },
        )

        output["scenario_b"] = {
            "query_graph": {
                "request": repeat_query.arguments,
                "response": repeat_query.result,
                "latency_ms": repeat_query.latency_ms,
            }
        }

        # Summary stats
        total_latency = sum(c.latency_ms for c in captured)
        output["summary"] = {
            "total_calls": len(captured),
            "total_latency_ms": round(total_latency, 1),
            "skills_created": 3,
            "goal_id": goal_id,
            "node_ids": node_ids,
        }

        # Convert captured calls to serializable format
        output["calls"] = [asdict(c) for c in captured]

    finally:
        client.close()
        mcp_mod._terminate_process(proc)

    return output


def build_parser() -> argparse.ArgumentParser:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))

    p = argparse.ArgumentParser(
        description="Capture Graphonomous MCP payloads for demo showcase"
    )
    p.add_argument(
        "--cwd",
        default=project_root,
        help="Working directory where server command runs",
    )
    p.add_argument(
        "--db-path",
        default=DEFAULT_DB_PATH,
        help="Path to SQLite DB file",
    )
    p.add_argument(
        "--embedder-backend",
        default="fallback",
        choices=["auto", "fallback"],
    )
    p.add_argument(
        "--request-timeout-ms",
        type=int,
        default=180_000,
    )
    p.add_argument(
        "--log-level",
        default="error",
        choices=["debug", "info", "warning", "error"],
    )
    p.add_argument(
        "--io-timeout-s",
        type=float,
        default=30.0,
    )
    p.add_argument(
        "--tee-stderr",
        action="store_true",
        help="Mirror server stderr to this process stderr",
    )
    p.add_argument(
        "-o",
        "--output",
        default="-",
        help="Output file path (default: stdout)",
    )
    return p


def main() -> int:
    args = build_parser().parse_args()

    try:
        result = run_capture(args)
    except Exception as exc:
        print(f"❌ Capture failed: {exc}", file=sys.stderr)
        return 1

    output_json = json.dumps(result, indent=2)

    if args.output == "-":
        print(output_json)
    else:
        with open(args.output, "w") as f:
            f.write(output_json)
        print(f"✅ Captured payloads written to {args.output}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
