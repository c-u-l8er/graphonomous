#!/usr/bin/env bash
# Download LongMemEval benchmark datasets from HuggingFace
# Usage: cd graphonomous/priv/longmemeval && bash download.sh

set -euo pipefail

BASE_URL="https://huggingface.co/datasets/xiaowu0162/longmemeval-cleaned/resolve/main"

echo "Downloading LongMemEval datasets..."

# Oracle split (smallest — only evidence sessions per question, fast iteration)
if [ ! -f longmemeval_oracle.json ]; then
  echo "  Downloading longmemeval_oracle.json..."
  wget -q "${BASE_URL}/longmemeval_oracle.json" -O longmemeval_oracle.json
  echo "  Done."
else
  echo "  longmemeval_oracle.json already exists, skipping."
fi

# Small split (~115K tokens, ~40 sessions — main competitive benchmark)
if [ ! -f longmemeval_s_cleaned.json ]; then
  echo "  Downloading longmemeval_s_cleaned.json..."
  wget -q "${BASE_URL}/longmemeval_s_cleaned.json" -O longmemeval_s_cleaned.json
  echo "  Done."
else
  echo "  longmemeval_s_cleaned.json already exists, skipping."
fi

echo "Download complete. Files:"
ls -lh *.json 2>/dev/null || echo "  No JSON files found."
