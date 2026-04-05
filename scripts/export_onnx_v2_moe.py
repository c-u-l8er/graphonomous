#!/usr/bin/env python3
"""
Export nomic-ai/nomic-embed-text-v2-moe to ONNX for Graphonomous.

Uses a dense-forward approach: replaces sparse MoE routing (which produces
data-dependent tensor shapes incompatible with ONNX) with dense computation
that runs ALL experts on ALL tokens with router-weighted blending. This
produces identical embeddings (cosine sim 1.0 vs original) with static
ONNX shapes that work in Ortex/ORT.

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


class DenseNomicExperts(nn.Module):
    """Dense replacement for NomicExperts that computes ALL experts for ALL tokens.

    The original NomicExperts uses sparse routing (torch.where on expert_mask)
    which produces variable-length token lists per expert — data-dependent shapes
    that ONNX cannot represent. This replacement computes every expert for every
    token and blends using the router's top-k weights, giving identical outputs
    with fully static tensor shapes.

    Trade-off: ~4x more FLOPs (8 experts vs top-2), but for embedding inference
    this is negligible (~50ms overhead on CPU for seq_len=64).
    """

    def __init__(self, orig_experts):
        super().__init__()
        self.mlp = orig_experts.mlp
        self.bias = orig_experts.bias
        self.moe_num_experts = orig_experts.moe_num_experts

    def forward(self, x, weights, top_weights, top_experts):
        bsz, q_len, hidden_size = x.shape
        x_flat = x.view(-1, hidden_size)  # [N, H]
        N = x_flat.shape[0]

        # Build full weight matrix: zero everything except top-k experts
        full_weights = torch.zeros(N, self.moe_num_experts, device=x.device, dtype=x.dtype)
        full_weights.scatter_(1, top_experts, top_weights)

        # Compute all experts densely and blend by router weights
        out = torch.zeros_like(x_flat)
        for expert_idx in range(self.moe_num_experts):
            expert_out = self.mlp(x_flat, expert_idx)  # [N, H]
            expert_weight = full_weights[:, expert_idx : expert_idx + 1]  # [N, 1]
            out = out + expert_out * expert_weight

        out = out.reshape(bsz, q_len, hidden_size)
        return out + self.bias


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

    # Replace sparse MoE experts with dense equivalents for ONNX-compatible shapes
    moe_layer_indices = []
    for idx, layer in enumerate(model.encoder.layers):
        if hasattr(layer.mlp, "experts") and hasattr(layer.mlp, "router"):
            layer.mlp.experts = DenseNomicExperts(layer.mlp.experts)
            moe_layer_indices.append(idx)
    print(f"Replaced {len(moe_layer_indices)} MoE layers with dense equivalents: {moe_layer_indices}")

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

    # Verify dense model matches original
    print("Verifying dense vs original equivalence...")
    model_orig = AutoModel.from_pretrained(MODEL_ID, trust_remote_code=True)
    model_orig.eval()
    text = "search_query: The quick brown fox jumps over the lazy dog"
    enc = tokenizer(text, padding="max_length", truncation=True, max_length=seq, return_tensors="pt")
    with torch.no_grad():
        out_dense = wrapper(enc["input_ids"], enc.get("token_type_ids", torch.zeros_like(enc["input_ids"])), enc["attention_mask"])
        out_orig = model_orig(**{k: v for k, v in enc.items()}).last_hidden_state
    mask = enc["attention_mask"].unsqueeze(-1).float()
    mean_dense = (out_dense * mask).sum(1) / mask.sum(1)
    mean_orig = (out_orig * mask).sum(1) / mask.sum(1)
    cosine = torch.nn.functional.cosine_similarity(mean_dense, mean_orig).item()
    max_diff = (mean_dense - mean_orig).abs().max().item()
    print(f"  Cosine similarity: {cosine:.6f}")
    print(f"  Max absolute diff: {max_diff:.6f}")
    if cosine < 0.999:
        print("  WARNING: Cosine similarity below 0.999 — check dense replacement correctness")
    del model_orig  # free memory

    print(f"Exporting to ONNX (opset {args.opset}, dense MoE, legacy tracer)...")
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
        dynamo=False,
    )

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"Exported: {output_path} ({size_mb:.1f} MB)")

    # Quick validation with onnxruntime
    try:
        import numpy as np
        import onnxruntime as ort

        sess = ort.InferenceSession(str(output_path))
        enc_np = tokenizer(text, padding="max_length", truncation=True, max_length=seq, return_tensors="np")
        inputs = {
            "input_ids": enc_np["input_ids"].astype(np.int64),
            "token_type_ids": np.zeros_like(enc_np["input_ids"], dtype=np.int64),
            "attention_mask": enc_np["attention_mask"].astype(np.int64),
        }
        ort_out = sess.run(None, inputs)
        print(f"  ONNX Runtime validation OK — output shape: {ort_out[0].shape}")

        # Compare with PyTorch output
        with torch.no_grad():
            pt_out = wrapper(
                torch.tensor(inputs["input_ids"]),
                torch.tensor(inputs["token_type_ids"]),
                torch.tensor(inputs["attention_mask"]),
            )
        max_diff = abs(pt_out.numpy() - ort_out[0]).max()
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
