#!/usr/bin/env python3
"""
Export nomic-ai/nomic-embed-text-v2-moe to ONNX for Graphonomous.

Produces a model.onnx that matches the input/output contract expected by
Graphonomous.Embedder's ONNX backend:

  Inputs (positional order):
    0: input_ids      — int64 {batch, seq}
    1: token_type_ids — int64 {batch, seq}
    2: attention_mask  — int64 {batch, seq}

  Outputs:
    0: last_hidden_state — float32 {batch, seq, 768}

Usage:
    pip install torch transformers einops onnx onnxruntime
    python scripts/export_onnx_v2_moe.py [--output PATH]

The default output path matches Graphonomous's ONNX cache layout:
    ~/.cache/graphonomous/onnx/nomic-ai--nomic-embed-text-v2-moe/model.onnx
"""

import argparse
import os
import sys
from pathlib import Path

import torch
import torch.nn as nn

MODEL_ID = "nomic-ai/nomic-embed-text-v2-moe"
DEFAULT_CACHE = Path.home() / ".cache" / "graphonomous" / "onnx" / "nomic-ai--nomic-embed-text-v2-moe"


class EmbeddingWrapper(nn.Module):
    """Wraps the model to output only last_hidden_state with correct input order."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, token_type_ids, attention_mask):
        outputs = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids,
        )
        # Return last_hidden_state — mean pooling happens in Elixir
        if hasattr(outputs, "last_hidden_state"):
            return outputs.last_hidden_state
        # Some models return a tuple
        return outputs[0]


def main():
    parser = argparse.ArgumentParser(description="Export nomic-embed-text-v2-moe to ONNX")
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help=f"Output path (default: {DEFAULT_CACHE / 'model.onnx'})",
    )
    parser.add_argument("--opset", type=int, default=17, help="ONNX opset version")
    parser.add_argument("--seq-len", type=int, default=64, help="Dummy sequence length for tracing")
    args = parser.parse_args()

    output_path = Path(args.output) if args.output else DEFAULT_CACHE / "model.onnx"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Loading {MODEL_ID} (trust_remote_code=True)...")
    from transformers import AutoModel, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
    model = AutoModel.from_pretrained(MODEL_ID, trust_remote_code=True)
    model.eval()

    wrapper = EmbeddingWrapper(model)

    # Dummy inputs for tracing
    batch = 1
    seq = args.seq_len
    dummy_input_ids = torch.ones(batch, seq, dtype=torch.long)
    dummy_token_type_ids = torch.zeros(batch, seq, dtype=torch.long)
    dummy_attention_mask = torch.ones(batch, seq, dtype=torch.long)

    print("Verifying forward pass...")
    with torch.no_grad():
        out = wrapper(dummy_input_ids, dummy_token_type_ids, dummy_attention_mask)
    print(f"  Output shape: {out.shape} (expect [1, {seq}, 768])")
    assert out.shape[-1] == 768, f"Expected hidden_dim=768, got {out.shape[-1]}"

    print(f"Exporting to ONNX (opset {args.opset}, legacy tracer)...")
    torch.onnx.export(
        wrapper,
        (dummy_input_ids, dummy_token_type_ids, dummy_attention_mask),
        str(output_path),
        opset_version=args.opset,
        input_names=["input_ids", "token_type_ids", "attention_mask"],
        output_names=["last_hidden_state"],
        dynamic_axes={
            "input_ids": {0: "batch", 1: "seq"},
            "token_type_ids": {0: "batch", 1: "seq"},
            "attention_mask": {0: "batch", 1: "seq"},
            "last_hidden_state": {0: "batch", 1: "seq"},
        },
        dynamo=False,  # Use legacy trace-based exporter — dynamo can't handle MoE routing
    )

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"Exported: {output_path} ({size_mb:.1f} MB)")

    # Quick validation with onnxruntime
    try:
        import onnxruntime as ort

        sess = ort.InferenceSession(str(output_path))
        inputs = {
            "input_ids": dummy_input_ids.numpy(),
            "token_type_ids": dummy_token_type_ids.numpy(),
            "attention_mask": dummy_attention_mask.numpy(),
        }
        ort_out = sess.run(None, inputs)
        print(f"  ONNX Runtime validation OK — output shape: {ort_out[0].shape}")

        # Compare with PyTorch output
        max_diff = abs(out.numpy() - ort_out[0]).max()
        print(f"  Max PyTorch vs ONNX diff: {max_diff:.6f}")
        if max_diff > 0.001:
            print("  WARNING: Large numerical difference — check export quality")
    except ImportError:
        print("  (onnxruntime not installed — skipping validation)")

    print("\nDone! To use in Graphonomous, either:")
    print(f"  1. It's already in the cache path — just update config to model_id '{MODEL_ID}'")
    print(f"  2. Or set GRAPHONOMOUS_ONNX_MODEL_PATH={output_path}")


if __name__ == "__main__":
    main()
