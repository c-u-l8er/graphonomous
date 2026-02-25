#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${GRAPHONOMOUS_LOG_DIR:-$HOME/.graphonomous/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/zed-mcp-$(date +%Y%m%d-%H%M%S).log"

DB_PATH="${GRAPHONOMOUS_DB_PATH:-$HOME/.graphonomous/knowledge.db}"
EMBEDDER_BACKEND="${GRAPHONOMOUS_EMBEDDER_BACKEND:-fallback}"
REQUEST_TIMEOUT="${GRAPHONOMOUS_REQUEST_TIMEOUT:-180000}"
LOG_LEVEL="${GRAPHONOMOUS_LOG_LEVEL:-error}"

# Keep stdout clean for MCP protocol frames.
# Route diagnostics to file + stderr only.
{
  echo "[wrapper] start $(date -Is)"
  echo "[wrapper] whoami=$(whoami)"
  echo "[wrapper] pwd=$(pwd)"
  echo "[wrapper] project_dir=$PROJECT_DIR"
  echo "[wrapper] PATH=$PATH"
  echo "[wrapper] db_path=$DB_PATH"
  echo "[wrapper] embedder_backend=$EMBEDDER_BACKEND"
  echo "[wrapper] request_timeout=$REQUEST_TIMEOUT"
  echo "[wrapper] log_level=$LOG_LEVEL"
} >> "$LOG_FILE"

cd "$PROJECT_DIR"

exec 2> >(tee -a "$LOG_FILE" >&2)

mix run --no-start --no-compile -e "Graphonomous.CLI.main([\"--db\",\"$DB_PATH\",\"--embedder-backend\",\"$EMBEDDER_BACKEND\",\"--request-timeout\",\"$REQUEST_TIMEOUT\",\"--log-level\",\"$LOG_LEVEL\"])" -- "$@"
