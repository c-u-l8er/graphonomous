#!/bin/bash
cd /home/travis/ProjectAmp2/graphonomous
source .envrc 2>/dev/null
source .env.rescore

LIMIT="${1:-500}"
LOG="/tmp/rescore_full.log"

echo "Starting rescore at $(date) with limit=$LIMIT" > "$LOG"
mix benchmark.longmemeval_rescore \
  --input longmemeval_20260405_234227_ppr0.18_L500.json \
  --limit "$LIMIT" \
  --concurrency 4 \
  >> "$LOG" 2>&1

echo "Finished at $(date)" >> "$LOG"
