#!/usr/bin/env bash
# Download BEAM benchmark datasets from HuggingFace
# Usage: cd graphonomous/priv/beam && bash download.sh [--tier 128k|500k|1m|10m|all]
#
# BEAM: Beyond a Million Tokens (ICLR 2026)
# Paper: https://arxiv.org/abs/2510.27246
# Repo: https://github.com/mohammadtavakoli78/BEAM
# Dataset: https://huggingface.co/datasets/Mohammadta/BEAM (128K/500K/1M)
#          https://huggingface.co/datasets/Mohammadta/BEAM-10M (10M)

set -euo pipefail

TIER="${1:-all}"

# HuggingFace dataset URLs
BEAM_REPO="https://huggingface.co/datasets/Mohammadta/BEAM/resolve/main"
BEAM_10M_REPO="https://huggingface.co/datasets/Mohammadta/BEAM-10M/resolve/main"

download_tier() {
  local tier="$1"
  local dir="chats_${tier}"

  if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "  ${dir}/ already exists with data, skipping."
    return
  fi

  mkdir -p "$dir"
  echo "  Downloading ${tier} tier..."

  if [ "$tier" = "10m" ]; then
    # 10M tier is in a separate repo
    # Try downloading the dataset files
    if command -v huggingface-cli &>/dev/null; then
      huggingface-cli download Mohammadta/BEAM-10M --local-dir "$dir" --repo-type dataset 2>/dev/null || {
        echo "  huggingface-cli failed, trying wget..."
        wget -q "${BEAM_10M_REPO}/data.zip" -O "${dir}/data.zip" 2>/dev/null && {
          cd "$dir" && unzip -q data.zip && rm -f data.zip && cd ..
        } || echo "  Could not download 10M tier. Try: pip install huggingface_hub && huggingface-cli download Mohammadta/BEAM-10M"
      }
    else
      echo "  Install huggingface-cli for 10M tier: pip install huggingface_hub"
      echo "  Then: huggingface-cli download Mohammadta/BEAM-10M --local-dir ${dir} --repo-type dataset"
    fi
  else
    # 128K, 500K, 1M tiers are in the main BEAM repo
    if command -v huggingface-cli &>/dev/null; then
      huggingface-cli download Mohammadta/BEAM --local-dir "_beam_full" --repo-type dataset 2>/dev/null || {
        echo "  huggingface-cli failed for ${tier}. Trying git clone..."
        if [ ! -d "_beam_repo" ]; then
          git clone --depth 1 https://github.com/mohammadtavakoli78/BEAM.git _beam_repo 2>/dev/null || {
            echo "  git clone failed. Please download manually from:"
            echo "    https://huggingface.co/datasets/Mohammadta/BEAM"
            return
          }
        fi
      }
    else
      # Fallback: clone the GitHub repo which has the chat data
      if [ ! -d "_beam_repo" ]; then
        echo "  Cloning BEAM repository..."
        git clone --depth 1 https://github.com/mohammadtavakoli78/BEAM.git _beam_repo 2>/dev/null || {
          echo "  git clone failed. Install huggingface-cli or download manually."
          return
        }
      fi
    fi

    # Copy tier-specific data from repo clone
    if [ -d "_beam_repo/chats/${tier}" ]; then
      cp -r "_beam_repo/chats/${tier}/." "$dir/"
      echo "  Copied ${tier} data from repo clone."
    elif [ -d "_beam_full" ]; then
      # HuggingFace download structure
      if [ -d "_beam_full/chats/${tier}" ]; then
        cp -r "_beam_full/chats/${tier}/." "$dir/"
        echo "  Copied ${tier} data from HF download."
      else
        echo "  Warning: Could not find ${tier} data in downloaded files."
      fi
    fi
  fi

  # Count files
  local count
  count=$(find "$dir" -name "*.json" 2>/dev/null | wc -l)
  echo "  ${tier}: ${count} JSON files downloaded."
}

echo "BEAM Benchmark Dataset Downloader"
echo "================================="
echo ""

case "$TIER" in
  128k|128K)
    download_tier "128k"
    ;;
  500k|500K)
    download_tier "500k"
    ;;
  1m|1M)
    download_tier "1m"
    ;;
  10m|10M)
    download_tier "10m"
    ;;
  all)
    echo "Downloading all tiers (128K first for smoke testing)..."
    download_tier "128k"
    download_tier "500k"
    download_tier "1m"
    download_tier "10m"
    ;;
  *)
    echo "Unknown tier: $TIER"
    echo "Usage: bash download.sh [128k|500k|1m|10m|all]"
    exit 1
    ;;
esac

# Clean up repo clone if we used it
if [ -d "_beam_repo" ]; then
  echo ""
  echo "Cleaning up repo clone..."
  rm -rf _beam_repo
fi

if [ -d "_beam_full" ]; then
  echo ""
  echo "Cleaning up HF download cache..."
  rm -rf _beam_full
fi

echo ""
echo "Download complete. Contents:"
for d in chats_*; do
  if [ -d "$d" ]; then
    count=$(find "$d" -name "*.json" 2>/dev/null | wc -l)
    echo "  ${d}: ${count} files"
  fi
done
