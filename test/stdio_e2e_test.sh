#!/usr/bin/env bash
# End-to-end test of the Graphonomous MCP server over stdio.
#
# Starts the server via `mix run`, sends JSON-RPC 2.0 messages through
# a FIFO pipe, reads responses from an unbuffered output file, and
# validates every tool + resource in the MCP surface.
#
# Requirements: jq (downloaded to /tmp/jq if missing)
set -euo pipefail
cd "$(dirname "$0")/.."

# ── jq bootstrap ──
if ! command -v jq &>/dev/null; then
  if [ -x /tmp/jq ]; then
    export PATH="/tmp:$PATH"
  else
    echo "jq not found, downloading..."
    curl -sL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 -o /tmp/jq
    chmod +x /tmp/jq
    export PATH="/tmp:$PATH"
  fi
fi

# ── Temp files ──
DB=$(mktemp /tmp/graphonomous-e2e-XXXXXX.db)
FIFO=$(mktemp -u /tmp/graphonomous-fifo-XXXXXX)
OUT=$(mktemp /tmp/graphonomous-out-XXXXXX)
ERR=$(mktemp /tmp/graphonomous-err-XXXXXX)
mkfifo "$FIFO"

cleanup() {
  exec 3>&- 2>/dev/null || true
  [ -n "${SPID:-}" ] && kill "$SPID" 2>/dev/null || true
  wait "$SPID" 2>/dev/null || true
  rm -f "$DB" "$FIFO" "$OUT" "$ERR"
}
trap cleanup EXIT

# ── Start server ──
# --no-start prevents the OTP app from auto-starting before CLI.main
# can apply --embedder-backend fallback.
# stdbuf -oL forces line-buffered stdout so responses flush immediately.
stdbuf -oL mix run --no-start \
  -e "Graphonomous.CLI.main([\"--db\", \"$DB\", \"--embedder-backend\", \"fallback\"])" \
  < "$FIFO" > "$OUT" 2>"$ERR" &
SPID=$!

# Wait for server readiness (consolidator init message in stderr)
for i in $(seq 1 20); do
  sleep 0.5
  grep -q "Graphonomous.Embedder forced to fallback" "$ERR" 2>/dev/null && break
done

exec 3>"$FIFO"  # hold FIFO open for writing

# ── Helpers ──
PASS=0; FAIL=0; TOTAL=0; LN=0

# Wait for a specific line to appear in the output file.
_wait_line() {
  local target=$1 max=${2:-60} i=0
  while [ $i -lt $max ]; do
    local n
    n=$(wc -l < "$OUT"); n=${n// /}
    if [ "$n" -ge "$target" ]; then
      sed -n "${target}p" "$OUT"
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  echo "{\"error\":\"TIMEOUT waiting for line $target\"}"
  return 1
}

# Send a JSON-RPC message and wait for the next response line.
# IMPORTANT: LN must be incremented in the CALLER (parent shell),
# not here, because this runs inside $() which is a subshell.
send_recv() {
  echo "$1" >&3
  _wait_line "$LN" "${2:-60}"
}

# Send a notification (no response expected).
notify() { echo "$1" >&3; }

ok() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then
    echo "  ✓ $1"; PASS=$((PASS + 1))
  else
    echo "  ✗ $1 — expected '$3', got '$2'"; FAIL=$((FAIL + 1))
  fi
}

gte() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" -ge "$3" ] 2>/dev/null; then
    echo "  ✓ $1 ($2 ≥ $3)"; PASS=$((PASS + 1))
  else
    echo "  ✗ $1 — expected ≥ $3, got '$2'"; FAIL=$((FAIL + 1))
  fi
}

nn() {
  TOTAL=$((TOTAL + 1))
  if [ -n "$2" ] && [ "$2" != "null" ]; then
    echo "  ✓ $1"; PASS=$((PASS + 1))
  else
    echo "  ✗ $1 — got null/empty"; FAIL=$((FAIL + 1))
  fi
}

jv() { echo "$1" | jq -r "$2" 2>/dev/null; }
tv() { jv "$1" '.result.content[0].text' | jq -r "$2" 2>/dev/null; }

# ══════════════════════════════════════════════════════════════════
echo "=== Graphonomous MCP server — E2E stdio test ==="
echo ""

# ── 1. initialize ──
echo "1. initialize"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"e2e-test","version":"1.0.0"}}}')
ok "jsonrpc"  "$(jv "$R" .jsonrpc)" "2.0"
ok "id"       "$(jv "$R" .id)"      "1"
nn "server"   "$(jv "$R" .result.serverInfo.name)"
nn "proto"    "$(jv "$R" .result.protocolVersion)"

notify '{"jsonrpc":"2.0","method":"notifications/initialized"}'
sleep 0.3

# ── 2. tools/list ──
echo ""; echo "2. tools/list"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
ok "id" "$(jv "$R" .id)" "2"
gte "count" "$(jv "$R" '.result.tools|length')" 7
for t in store_node retrieve_context query_graph learn_from_outcome \
         manage_goal review_goal run_consolidation topology_analyze; do
  ok "$t" "$(jv "$R" ".result.tools[]|select(.name==\"$t\")|.name")" "$t"
done

# ── 3. resources/list ──
echo ""; echo "3. resources/list"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}')
ok "id" "$(jv "$R" .id)" "3"
gte "count" "$(jv "$R" '.result.resources|length')" 2

# ── 4. store_node × 3 ──
echo ""; echo "4. store_node × 3"

LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"store_node","arguments":{"content":"Elixir GenServer is a generic server behaviour in OTP","node_type":"semantic","confidence":0.9,"source":"e2e"}}}')
ok  "id"  "$(jv "$R" .id)" "10"
NID1=$(tv "$R" .node_id)
nn  "node1 ($NID1)" "$NID1"

LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"store_node","arguments":{"content":"OTP Supervisors restart crashed child processes automatically","node_type":"semantic","confidence":0.85,"source":"e2e"}}}')
NID2=$(tv "$R" .node_id)
nn  "node2 ($NID2)" "$NID2"

LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"store_node","arguments":{"content":"mix test runs ExUnit test suites in Elixir projects","node_type":"procedural","confidence":0.95,"source":"e2e"}}}')
NID3=$(tv "$R" .node_id)
nn  "node3 ($NID3)" "$NID3"

# ── 5. retrieve_context ──
echo ""; echo "5. retrieve_context"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"retrieve_context","arguments":{"query":"How does OTP handle process failures?","limit":5}}}')
ok  "id" "$(jv "$R" .id)" "20"
gte "results" "$(tv "$R" '.results|length')" 1

# ── 6. query_graph: list_nodes ──
echo ""; echo "6. query_graph (list_nodes)"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"query_graph","arguments":{"operation":"list_nodes","node_type":"semantic"}}}')
ok  "id" "$(jv "$R" .id)" "30"
gte "semantic nodes" "$(tv "$R" '.result.nodes|length')" 2

# ── 7. query_graph: get_node ──
echo ""; echo "7. query_graph (get_node)"
LN=$((LN + 1))
R=$(send_recv "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"tools/call\",\"params\":{\"name\":\"query_graph\",\"arguments\":{\"operation\":\"get_node\",\"node_id\":\"$NID1\"}}}")
ok  "id" "$(jv "$R" .id)" "31"
nn  "content" "$(tv "$R" '.result.node.content')"

# ── 8. learn_from_outcome ──
echo ""; echo "8. learn_from_outcome"
LN=$((LN + 1))
R=$(send_recv "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"tools/call\",\"params\":{\"name\":\"learn_from_outcome\",\"arguments\":{\"action_id\":\"e2e-action-1\",\"status\":\"success\",\"confidence\":0.95,\"causal_node_ids\":\"[\\\"$NID1\\\"]\"}}}")
ok  "id" "$(jv "$R" .id)" "40"
gte "processed" "$(tv "$R" .processed)" 1

# ── 9. manage_goal: create ──
echo ""; echo "9. manage_goal (create)"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":50,"method":"tools/call","params":{"name":"manage_goal","arguments":{"operation":"create_goal","payload":"{\"title\":\"E2E Test Goal\",\"description\":\"Full lifecycle\",\"priority\":\"high\"}"}}}')
ok  "id" "$(jv "$R" .id)" "50"
GID=$(tv "$R" '.result.id // .goal.id // .id')
nn  "goal ($GID)" "$GID"

# ── 10. manage_goal: list ──
echo ""; echo "10. manage_goal (list)"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":51,"method":"tools/call","params":{"name":"manage_goal","arguments":{"operation":"list_goals"}}}')
ok  "id" "$(jv "$R" .id)" "51"
gte "goals" "$(tv "$R" '.result | length')" 1

# ── 11. manage_goal: transition ──
echo ""; echo "11. manage_goal (transition → active)"
if [ -n "$GID" ] && [ "$GID" != "null" ]; then
  LN=$((LN + 1))
  R=$(send_recv "{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"tools/call\",\"params\":{\"name\":\"manage_goal\",\"arguments\":{\"operation\":\"transition_goal\",\"goal_id\":\"$GID\",\"status\":\"active\"}}}")
  ok "id"     "$(jv "$R" .id)" "52"
  ok "status" "$(tv "$R" '.result.status')" "active"
else
  echo "  ⊘ skipped (no goal id)"
fi

# ── 12. resources/read: health ──
echo ""; echo "12. resources/read (health)"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":60,"method":"resources/read","params":{"uri":"graphonomous://runtime/health"}}')
ok  "id" "$(jv "$R" .id)" "60"
H=$(jv "$R" '.result.contents[0].text')
nn  "health" "$(jv "$H" .health)"

# ── 13. resources/read: goals snapshot ──
echo ""; echo "13. resources/read (goals snapshot)"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":61,"method":"resources/read","params":{"uri":"graphonomous://goals/snapshot"}}')
ok  "id" "$(jv "$R" .id)" "61"
G=$(jv "$R" '.result.contents[0].text')
gte "total" "$(jv "$G" .total)" 1

# ── 14. run_consolidation ──
echo ""; echo "14. run_consolidation"
LN=$((LN + 1))
R=$(send_recv '{"jsonrpc":"2.0","id":70,"method":"tools/call","params":{"name":"run_consolidation","arguments":{"action":"run_and_status"}}}')
ok  "id" "$(jv "$R" .id)" "70"
nn  "action" "$(tv "$R" .action)"

# ── 15. topology_analyze ──
echo ""; echo "15. topology_analyze"
LN=$((LN + 1))
R=$(send_recv "{\"jsonrpc\":\"2.0\",\"id\":80,\"method\":\"tools/call\",\"params\":{\"name\":\"topology_analyze\",\"arguments\":{\"node_ids\":[\"$NID1\",\"$NID2\"]}}}")
ok  "id" "$(jv "$R" .id)" "80"
nn  "topology" "$(jv "$R" '.result.content[0].text')"

# ══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
printf "Results: %d/%d passed" "$PASS" "$TOTAL"
[ "$FAIL" -gt 0 ] && printf "  (%d FAILED)" "$FAIL"
echo ""
echo "════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "── stderr (last 20 lines) ──"
  grep -v "warning:" "$ERR" | tail -20
  exit 1
fi
