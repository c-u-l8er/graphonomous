# Benchmark Expansion Prompt — Graphonomous v0.3.3+

Use this prompt to build benchmark harnesses for Graphonomous one-by-one across chat sessions. Each session tackles one benchmark. The order below is the recommended build sequence (highest ROI first).

---

## Context

Graphonomous already has two benchmark harnesses:
- `lib/mix/tasks/benchmark/longmemeval.ex` — LongMemEval (ICLR 2025), 500 questions, 92.6% QA proxy
- `lib/mix/tasks/benchmark/graphmembench.ex` — GraphMemBench, 120 scenarios, 100% pass

Shared infrastructure:
- `lib/mix/tasks/benchmark/helpers.ex` — corpus loading, timing, metrics, JSON output
- `lib/mix/tasks/benchmark/llm_judge.ex` — LLM-free evaluation helpers
- `lib/mix/tasks/benchmark/run.ex` — full suite orchestrator
- Benchmark data lives in `priv/<benchmark_name>/`
- Results are written as JSON to `priv/<benchmark_name>/` with timestamps

Pattern for each new harness:
1. Create `priv/<name>/download.sh` to fetch dataset
2. Create `lib/mix/tasks/benchmark/<name>.ex` as a Mix task
3. Add the phase to `run.ex` orchestrator
4. Run, measure, record results
5. Update `opensentience.org/docs/spec/OS-E001-EMPIRICAL-EVALUATION.md` with findings
6. Store results in Graphonomous via `learn_from_outcome`

---

## Session Instructions

At the start of each session, paste this prompt and say:

> **"Build the benchmark harness for [BENCHMARK_NAME]."**

The agent should:

1. **Bootstrap Graphonomous** — retrieve context for the benchmark goal and any prior benchmark work
2. **Transition the goal** from `proposed` → `active`
3. **Research the benchmark** — read the paper/repo, understand dataset format, evaluation metrics, and scoring methodology
4. **Download/prepare data** — create `priv/<name>/download.sh` and fetch the dataset
5. **Build the harness** — create `lib/mix/tasks/benchmark/<name>.ex` following the longmemeval.ex pattern:
   - `use Mix.Task` with `@shortdoc`
   - Parse CLI options (`--limit`, `--purge`, `--neural`, `--skip-ingest`)
   - Ingest benchmark data into a fresh Graphonomous graph
   - Run queries through `retrieve_context` (and other MCP tools as needed)
   - Score results using the benchmark's official metrics
   - Output competitive comparison table
   - Write results JSON to `priv/<name>/`
6. **Wire into run.ex** — add the new phase to the orchestrator
7. **Run the benchmark** — execute with `--limit 50` first for a smoke test, then full run
8. **Record results** — update OS-E001 evaluation doc, store in Graphonomous
9. **Update goal progress** — set to 1.0 and transition to `done` if passing

---

## Benchmark Build Order

### Session 1: BEAM (Beyond a Million Tokens)
- **Goal ID**: `goal_5e547ffb6d10787cae8d9a57a9f217f8`
- **Paper**: https://arxiv.org/abs/2510.27246
- **Repo**: https://github.com/mohammadtavakoli78/BEAM
- **Dataset**: 100 conversations, 2,000 questions at 128K/500K/1M/10M token scales
- **Metrics**: QA accuracy across 10 memory abilities, per-scale breakdown
- **SOTA**: Hindsight 64.1% (10M), 73.9% (1M)
- **Key challenge**: Multi-scale evaluation. Start with 128K tier (fits in single graph). 10M tier will stress SQLite and retrieval latency.
- **Harness name**: `mix benchmark.beam`
- **CLI**: `mix benchmark.beam --tier 128k --limit 50`
- **Why first**: This is the new industry standard. Every competitor reports BEAM scores. Scaling behavior is where graph memory should differentiate from flat vector stores.

### Session 2: MemoryAgentBench
- **Goal ID**: `goal_8889e094cb2b904d65f6a29cd7861f1c`
- **Paper**: https://arxiv.org/abs/2507.05257
- **Repo**: https://github.com/HUST-AI-HYZ/MemoryAgentBench
- **Dataset**: Multi-turn incremental format, includes EventQA and FactConsolidation
- **Metrics**: 4 competency scores — accurate retrieval, test-time learning, long-range understanding, selective forgetting
- **Key challenge**: Multi-turn format requires simulating incremental store→query cycles, not batch ingest. Map "selective forgetting" to `forget_by_policy` / `forget_node`.
- **Harness name**: `mix benchmark.memoryagentbench`
- **CLI**: `mix benchmark.memoryagentbench --limit 50`
- **Why second**: Directly tests Graphonomous's differentiating features (forgetting, learning loop). ICLR 2026 paper — high credibility.

### Session 3: LMEB (Long-horizon Memory Embedding Benchmark)
- **Goal ID**: `goal_81c0f91f92b9b4a52e0a38b44c49a492`
- **Paper**: https://arxiv.org/abs/2603.12572
- **Repo**: https://github.com/KaLM-Embedding/LMEB
- **HuggingFace**: https://huggingface.co/datasets/KaLM-Embedding/LMEB
- **Dataset**: 22 datasets, 193 zero-shot retrieval tasks across 4 memory types (episodic, dialogue, semantic, procedural)
- **Metrics**: Retrieval accuracy per memory type, aggregate score
- **Key challenge**: This benchmarks the *embedding model*, not the full system. Run nomic-embed-text-v2-moe through the LMEB eval harness (likely Python). May need a thin Python wrapper or direct Elixir port of the eval logic.
- **Harness name**: `mix benchmark.lmeb`
- **CLI**: `mix benchmark.lmeb --model nomic-embed-text-v2-moe`
- **Why third**: Cheapest to run (embedding-only, no LLM judge needed). Validates the foundational layer. If nomic scores poorly on memory-specific retrieval, that's a critical finding.

### Session 4: MemoryBench (Continual Learning from Feedback)
- **Goal ID**: `goal_8ef86ae124eb2f03375289107dcac5ae`
- **Paper**: https://arxiv.org/abs/2510.17281
- **Dataset**: User feedback simulation across multiple domains and languages
- **Metrics**: Continual learning accuracy, feedback utilization rate, cross-domain transfer
- **Key challenge**: Requires simulating the feedback loop — `learn_from_feedback` with explicit/action-based/implicit feedback types, then re-querying to measure improvement. Multi-domain and multilingual means varied corpus.
- **Harness name**: `mix benchmark.memorybench`
- **CLI**: `mix benchmark.memorybench --domain all --limit 100`
- **Why fourth**: Directly tests the learning loop. Published finding that no system beats RAG baseline — if Graphonomous does, that's a headline result.

### Session 5: LifeBench (Non-Declarative Memory)
- **Goal ID**: `goal_824059ff9230ff0953646ea7ac2e7d6a`
- **Paper**: https://arxiv.org/abs/2603.03781
- **Dataset**: Long-horizon event simulations with real-world priors (surveys, maps, calendars)
- **Metrics**: Accuracy on habitual/procedural memory inference, declarative vs non-declarative breakdown
- **SOTA**: 55.2% (top system)
- **Key challenge**: Tests *inferred* knowledge, not explicitly stored facts. Graphonomous procedural nodes + edge patterns may capture habitual patterns that flat stores miss. May need to extend `retrieve_procedural` or add inference logic.
- **Harness name**: `mix benchmark.lifebench`
- **CLI**: `mix benchmark.lifebench --limit 50`
- **Why fifth**: Hardest benchmark (SOTA is 55%). Low expectations, high signal. If graph structure helps even marginally on non-declarative memory, that validates the architecture thesis.

### Session 6: AMemGym (On-Policy Interactive)
- **Goal ID**: `goal_b7ccffd9e67df8e7b42366ff24a9be82`
- **Paper**: https://arxiv.org/abs/2603.01966
- **HuggingFace**: https://huggingface.co/datasets/AGI-Eval/AMemGym
- **Dataset**: Interactive on-policy benchmark — agent generates its own conversation
- **Metrics**: Structured state consistency, memory utilization, persona tracking
- **Key challenge**: This is fundamentally different from other benchmarks. The agent must *participate* in the conversation, not just answer post-hoc questions. Requires wiring Graphonomous MCP into a simulated conversation loop with an LLM-simulated user. Most complex harness to build.
- **Harness name**: `mix benchmark.amemgym`
- **CLI**: `mix benchmark.amemgym --scenarios 10`
- **Why last**: Most complex integration. Requires LLM-in-the-loop (simulated user). But the most realistic test of how Graphonomous actually performs in production. Save for last when all other harnesses are proven.

---

## Post-Completion

After all 6 harnesses are built and run:

1. Update `OS-E001-EMPIRICAL-EVALUATION.md` with a unified results table
2. Update `graphonomous.com/benchmarks/` pages with new benchmark results
3. Update `AmpersandBoxDesign/site/portfolio-review.html` competitive landscape
4. Store a comprehensive episodic node in Graphonomous summarizing the full evaluation
5. Consider adding top-line scores to `graphonomous/README.md`

---

## Anti-Patterns to Avoid

- Do NOT modify `retrieve_context` or the retrieval pipeline to game a specific benchmark
- Do NOT add benchmark-specific code paths to the core engine
- Do NOT skip the smoke test (`--limit 50`) before full runs
- Do NOT fabricate competitive baselines — only cite published numbers with sources
- Do NOT skip storing results in Graphonomous — the learning loop is the point
