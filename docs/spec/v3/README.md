# Graphonomous v3 — the carried memory

**Direction spec · draft · `spec` rung · written 2026-09-27 · nothing below is ruled. Do not build from
this yet.** Every `[T#]` is an open ruling for Travis (§9). A number marked *measured* was taken on this
machine on 2026-09-27 with the command or file named beside it. A number marked *reported* comes from a
web research pass the same day (§10) and was not reproduced here. The two are never blended.

> **Name trap — read before quoting this document.** "v3" is already used twice in this repository:
> `graphonomous.semantic.v3` is a *profile id* proposed by v2's R17 (the WRL vocabulary), and v2's stage
> roadmap numbers its stages G0–G5 (G3 = reduction). This document is about **neither**. Write
> **Graphonomous v3** in full — never "v3" or "G3" alone — until [T1] settles the name.

## 0. In one paragraph

Graphonomous **v1** (v0.4.3, Elixir, `graphonomous/lib/`) tried to be an agent's memory, and it deletes what
it stores. Graphonomous **v2** (`graphonomous/v2/`, Node ESM) is a certified evidence graph over pinned
registries and has, deliberately, no write surface. **Super**, the MVP (R97), holds an unbuilt slot for "the
memory each agent carries". **Graphonomous v3** is the proposal to fill that slot: *the memory substrate of
an active locus*, built on v2's projection and certificate machinery, fed by rulings, Super's receipts and
proposed observations, and **judged — never authored — by a calibrated typed decider** (TypeSafe's Jev, or
Ollaya, its free local counterpart). v2 is not modified: Graphonomous v3 adds a journal, profiles and adapters
beside it. v1 becomes legacy (§6).

## 1. Why now

### 1.1 v1 deletes itself — *measured*

| Fact | Value | How |
|---|---|---|
| nodes in `~/.graphonomous/knowledge.db` | **0** | `sqlite3 -readonly … 'select count(*) from nodes'` |
| edges / goals / outcomes surviving | 620 (dangling) / 173 / 124 | same; `pragma quick_check` = `ok` |
| last write to the database | 2026-09-22 23:49 | `ls -l` on `knowledge.db*` |
| consolidator cadence | every 300,000 ms | `config/config.exs` `consolidator_interval_ms` |
| decay per run / hard-delete below | 0.02 / 0.1 | `lib/graphonomous/consolidator.ex` `@default_decay_rate`, `@default_prune_threshold` |
| lifetime of a node stored at confidence 0.5 | ≈ 80 runs ≈ **6.7 h** | 0.5 × 0.98ⁿ < 0.1 ⇒ n ≥ 80 |
| per-session servers running before §6 | **29** BEAMs, ≈ 1.6 GB RSS | `ps`; the plugin spawns `scripts/graphonomous_mcp_wrapper.sh` over stdio, one per open session |

Each of those servers loaded the graph into memory once at start (`warm_cache_from_db`, `store.ex`), so a
session never saw another session's writes, and each ran its own consolidator against the same file.
"`stored` but `retrieve` returns 0" was not a crash: it was a forgetting curve tuned for benchmark churn,
running as 29 independent copies of itself.

### 1.2 v2 is a different product — *read from the tree*

- Its definition: *"the persistent semantic/evidence graph that makes what a system understands queryable,
  falsifiable, provenance-linked, and reducible"*, and *"a derived semantic projection over authoritative
  registries … not another authoritative registry"* (`v2/README.md`).
- *"No LLM output is evidence. Deterministic, content-addressed, replayable transforms only."*
  (`v2/README.md:38`).
- D-071 (2026-09-03): *"The next step is NOT a write surface."*
- Projections are rebuilt whole from a pinned snapshot; `lib/project.mjs` deletes the output directory
  first. There is no append path.
- The query surface is six structural functions (`lib/query.mjs`: node · neighbors · path · facts ·
  explain · as_of); *"Nothing here computes a fact the projection and its evaluation do not already hold."*
  There is no relevance retrieval, no embedding, no MCP server.
- Latest decision D-077; last commit `61adec2d` (2026-09-08); full tree 182 pass / 0 fail / 1 skip.

So "move the MCP onto v2" is a category error as v2 stands: v1 answered *what do we remember?*, v2 answers
*what does the stack's evidence establish?*

### 1.3 Super has the slot, and refuses ambient MCP — *read from the tree* (super-live)

- `cockpit/src/claude_connection.rs:511,614` starts Claude with `--strict-mcp-config` and
  `{"mcpServers":{}}`; `cockpit/src/codex_connection.rs` disables Codex's `memories`. On purpose.
- `site/AGENT_SUPER_APP_BLUEPRINT.md:274`: *"MCP is adapter/transport (tools become* requested *typed
  capabilities …); neither implicitly grants authority."* Phase C4 is "MCP + Agent Skills adapters".
- `site/index.html:729`: Super is *"the slot each agent's memory lives in … the loop where Super admits what
  an agent did as receipts and Graphonomous re-imports it is designed"*.
- `FOUNDATION_LANE.md` (≈ line 1839): Graphonomous's designed stages *"have no executor, and the executor
  must be a Super Worker under Carrier confinement whose only writable surface is a proposal"*.
- ampd already has a capability registry (`ampd/lib/ampd/capability_registry.ex`: postgres, worktree,
  trvm, github packs), a receipt ledger (`receipts.ex`: *"feeds Evidence; never a second audit system"*),
  and — on the `t23-bounded-attempts` / `authority-log*` branches — an append-only, gapless `AuthorityLog`.

### 1.4 What actually carries continuity today — *measured*

The file memory at `~/.claude/projects/-home-travis-ProjectAmp2/memory/`: **148 files, 34,886 lines**,
indexed by `MEMORY.md`. Not in git, not certified, not shared with Codex or Super — and it works. Any
Graphonomous v3 has to beat it at its own job, or not be built (§8 F1).

### 1.5 The new thing — calibrated typed deciders — *reported*

Jev (TypeSafe AI, announced 2026-09-15) and Ollaya (Apache-2.0, released ≈ 2026-09-24, wire-compatible with
Jev on `POST /v1/systemone`) answer **typed questions about a state** — `noul` (P(true)), `choice` (2–255
labels, a probability each), `score` (2–10 levels) — with calibrated probabilities and **no text and no
embeddings**. They judge candidates; they cannot find them. Those are exactly the judgments v1 made with
hard-coded constants — and a hard-coded constant (§1.1) is what emptied it. Details and sources: §10.

## 2. Two jobs, named

| | **J1 — carried memory** | **J2 — evidence self-model** |
|---|---|---|
| Answers | what has this locus learned, been told, been corrected on? | what does the stack's evidence establish? |
| Authority | proposals, rulings, receipts | authoritative registries only |
| Carried today by | the file memory (§1.4) | Graphonomous v2 |
| Write surface | yes — proposals | no (D-071) |
| Graphonomous v3 | **is J1**, built on J2's machinery | unchanged; v3 links to it |

## 3. Principles

- **P1 — No model output is evidence** (inherits `v2/README.md:38`). A decider's answer is a `DECISION`
  record carrying its certificate: a ranking or a proposal, never a fact.
- **P2 — Floor, then gradient** (box-and-box, `feasible ▸ permitted ▸ best`). Deterministic rules refuse
  (§4.5); the decider only orders what the floor admitted. A decider never sits in `permitted`.
- **P3 — No second ledger.** Facts about Super's world enter from Super's receipts. Graphonomous v3 reads
  downstream and never writes into ampd's stores.
- **P4 — Nothing is forgotten by a constant.** Retirement is a decision with a trigger and a record; it
  archives. Erasure is a separate, explicit, audited command. (v1's lesson.)
- **P5 — One process owns the store.** Every client is an adapter; no per-session engines. (v1's lesson.)
- **P6 — Rulings outrank observations.** A `REVISION_REGISTER.md` row is authoritative; an observation
  that contradicts a current ruling is admitted only as a flagged conflict.
- **P7 — Measured or cited.** Every number has a command or a source; *measured* and *reported* stay apart.
- **P8 — Local and free first.** Zero budget. Hosted Jev is a metered reference and fallback, not a
  dependency.
- **P9 — Memory is per locus.** `AGENCY.md`: *"memory is a substrate; lineage is a relation."* A Bot or
  Worker recalls through its projection, not the world.

## 4. Architecture

```
 sources ──► journal ──► projection ──► recall ──► floor ──► judge ──► access
 RULINGS      append-     v2 machinery   lexical +   deterministic  calibrated   MCP daemon (outside Super)
 RECEIPTS     only,       (lids, canon,  structural  refusals       decider      capability pack (inside Super)
 EVIDENCE     gapless     certificates,  (+ embed?)  (§4.5)         (§4.6)       CLI
 OBSERVATIONS jseq        WRL seal)      ≤255 cands                 DECISION
 FILE MEMORY                                                        certificates
```

### 4.1 Source families

| Family | What | Authority | Status |
|---|---|---|---|
| `RULINGS` | `REVISION_REGISTER.md` rows (99 rows matching `^\| R[0-9]`, *measured*), pinned by commit — tracked in the ProjectAmp2 repo | authoritative | new adapter |
| `RECEIPTS` | Super receipts, `AuthorityLog`, witness JSONL (`effects/witness.ex`) | authoritative for Super's world | waits on Super stage 0 |
| `EVIDENCE` | v2's existing families (crosswalk, factory, factory_mosaic, trvm) | authoritative | exists; linked, not changed |
| `OBSERVATIONS` | a locus's "remember this": text, author locus, session, cites | proposal | new; enters only through `propose` |
| `FILE MEMORY` | the §1.4 directory, imported as `OBSERVATIONS` authored by `claude-code-sessions` | proposal | new adapter; not in git, so pinned by a content hash of the directory |

### 4.2 The journal — the one missing primitive

v2 can only rebuild. A memory has to append. Proposal: an append-only, framed, gapless-sequenced journal
(the shape of Super's `AuthorityLog`: one record per admitted transition, `jseq` without holes).
Projections become folds over journal ranges.

**Law J-1: `fold(journal[0..n])` is byte-identical to `rebuild(snapshot at n)`.** The full rebuild stays the
verifier; the incremental fold is only the fast path. The journal is the only thing ever written; everything
else is derived.

### 4.3 Record kinds — a new profile, never an edit to a frozen one

`OBSERVATION` · `RULING` · `DECISION` (one decider call: model id + weights digest, calibration version,
question id@version, state hash, probabilities, confidence, latency, host) · `RETIREMENT` (what was
archived, its trigger, and the rule or `DECISION` that caused it).
Relations: `SUPERSEDES` (ruling→ruling, observation→observation), `CONTRADICTS` (a flag, never a verdict),
`CITES`, `CORROBORATED_BY` (observation → receipt | evidence | ruling).
Whether this is a `graphonomous.semantic.vN` profile or a separate `graphonomous.memory.v0` family is [T6].

### 4.4 Recall — finding candidates

A decider cannot find anything; it only judges what it is shown. Recall is lexical (full-text over
`OBSERVATION` and `RULING` text), plus structural (v2's `neighbors` / `path`), plus embeddings if [T7] says
so. v1's fallback hash embedder is not semantic recall and is not carried over. Recall returns at most 255
candidates, the decider's `choice` bound.

### 4.5 Floor — deterministic refusals the decider cannot weaken

- **F-1** An `OBSERVATION` without an author locus and a session is refused.
- **F-2** Secret-shaped text (API keys, passwords, tokens) is refused at intake. Travis's notebook
  `~/Documents/README.txt` holds plaintext credentials, and no import may carry them.
- **F-3** A `RULING` is superseded only by a later `RULING`, never by an observation.
- **F-4** An observation that contradicts a current ruling is admitted flagged `CONTRADICTS`, never as
  current.
- **F-5** Nothing is deleted by the engine. Retirement archives; erasure is its own audited command.
- **F-6** A `DECISION` with an incomplete certificate is refused: absent ⇒ `0̲`, fail closed (`AGENCY.md`,
  *certificate*).
- **F-7** Proposals are metered per locus. Alphapiler measured it (Piles of Dust, PASS 9): when refusals
  cost nothing, a blind picker asking often beats an informed one asking rarely.

### 4.6 Judge — the question catalogue

| Id | Type | Question | Answer goes to | Replaces in v1 |
|---|---|---|---|---|
| Q-KEEP | noul | Is this a durable fact worth carrying beyond this session? | review order at intake | store-everything |
| Q-ASSERT | noul | Is it stated as settled (vs a plan, guess, question)? | a tag | — |
| Q-SAME | score ×3 | different / review / same, for a candidate pair | merge proposal | `consolidator_merge_similarity` 0.95 |
| Q-CONTRA | noul | Do these two contradict? | `CONTRADICTS` candidate | — (v2 reduced its two conflict rules to zero, D-074, restated in D-076) |
| Q-SUPERSEDE | choice | a supersedes b / b supersedes a / both stand / review | `SUPERSEDES` proposal | — |
| Q-RANK | choice | which of these ≤255 candidates answers the query? | recall order | similarity score |
| Q-ENOUGH | noul | Is this enough to act? | act / learn / escalate **hint** — second opinion to κ routing, never an override | coverage heuristic |
| Q-RETIRE | choice | keep / archive / review — asked only on a trigger (superseded, contradicted, source moved), **never on a timer** | `RETIREMENT` proposal | decay 0.02 / prune 0.1 |

Probabilities are stored, not thresholded at write time; the threshold that acts is part of the question's
version. The middle band goes to a review queue (Travis, or a stronger model), never to an automatic merge.
Calibration is refitted per question type on our own labels: *reported*, calibration drifts in a different
direction per question type out of distribution (§10).

### 4.7 Where the decider runs — [T2]

- **Option A — inside the Graphonomous v3 daemon** (plain HTTP to a local Ollaya). Latency is *reported* at
  89–520 ms on an RTX 4090. That answers the first reason behind the standing rule "MCP servers make no LLM
  calls" (calls of 60–130 s timed out). Every call is a `DECISION` record, which answers the second
  (visibility). It still contradicts the rule as worded.
- **Option B — agent-asked.** The daemon returns typed questions; the agent asks the decider and submits the
  answers. The rule stays intact, but the daemon cannot establish that an answer came from the named model:
  a submitted certificate is only a claim.
- **Option C — a Super capability.** Inside Super the decider is a capability pack, and each call is an
  effect through `Gateway` whose receipt is the certificate. The most Super-native option; waits on Super.

**Recommendation:** C inside Super; A outside it if [T2] permits; B only as the interim.

### 4.8 Access

- **A1 — one MCP daemon for Claude Code and Codex sessions outside Super.** A systemd user unit, like
  `super-desktop`, serving HTTP on 127.0.0.1. The plugin points at its URL: no stdio
  spawn per session (P5). Tools: `recall`, `explain`, `status`, then `propose`; read-only first. *Reported:*
  the MCP spec of 2026-07-28 made the protocol core stateless (no session id), so a continuation is an
  explicit handle returned by a tool.
- **A2 — a `memory` capability pack inside Super.** Reads through the agent and bot projections
  (`ampd/lib/ampd/projection.ex`); proposals go through `Gateway.perform` and come back as receipts. Super's
  own Claude and Codex hosts stay `--strict-mcp-config`.
- **A3 — CLI.** `recall` / `explain` over the memory profiles, beside v2's `bin/g0.mjs query`.

### 4.9 Resource budget on this machine — *measured*

30 GB RAM under chronic pressure (the desktop app has been OOM-killed at 14–23 GB resident); an RTX 4060
Laptop GPU with 8,188 MiB; glibc 2.44 (Ollaya *reportedly* needs ≥ 2.38). v2 reads whole JSONL files into
memory (`lib/evaluation.mjs`), and its `projections/` hold 296 MB on disk. Before any promise: measure the
daemon's idle and peak RSS, and each candidate decider model's resident size. Candidates: decider:2b or
winnow:e4b; laya only for short pairs (*reported* 421M, 512-token context). [T3]

## 5. What carries over, what retires

| From | Keep | Retire |
|---|---|---|
| v1 | the five-phase loop vocabulary as a PULSE manifest (retrieve · route · act · learn · consolidate); κ topology as a floor-side signal; the goal concept; the surviving rows (173 goals, 124 outcomes, 419 entities, 620 edges) as an archived source | decay and prune constants; per-session stdio engines; the hash-fallback embedder as recall; the contract "`stored` ⇒ remembered" |
| v2 | everything, unchanged: lids, canonical bytes, certificates, WRL sealing, pins, G1 rulepacks, query surface | nothing; the journal, profiles and adapters are added beside it |

v2's own pending `graphonomous.semantic.v3` (R17, the WRL vocabulary, awaiting GPT's adjudication) is
independent of this document and is not blocked by it.

## 6. v1 → legacy

**Done 2026-09-27:**
- The plugin is disabled in both scopes: `graphonomous@ampersand-plugins: false` in `~/.claude/settings.json`
  and in `ProjectAmp2/.claude/settings.local.json`. This takes effect for new sessions and also removes the
  plugin's skills and its `PostToolUse` hook, which appended to `/tmp/graphonomous-changed-files.jsonl`.
- The 29 running per-session servers were stopped with SIGTERM, by PID. `free -m` available went from
  5.4 GB to 8.4 GB (other processes were not held still).
- No row changed: `quick_check` ok; nodes 0, edges 620, goals 173, outcomes 124. The file itself did
  change: as the servers shut down, SQLite checkpointed the write-ahead log into it (mtime 2026-09-27 20:21,
  WAL now 0 bytes).
- The retired policy was replaced, at Travis's ask: `graphonomous/CLAUDE.md` (Primary Directive and §1–12;
  the old text is `git show 61adec2d:CLAUDE.md`) and the root `CLAUDE.md` section "Graphonomous session
  policy". Both now say v1 is LEGACY, the loop is off, and point here.

**Done 2026-09-28:**
- **L-1 — archived at `~/.graphonomous/export-2026-09-28/`** (mode 0700): a `.backup` copy of
  `knowledge.db` (integrity ok, every table's count equal to the source), `knowledge.db.fts`, `schema.sql`,
  one JSONL per non-empty table (edges 620, entities 419, goals 173, outcomes 124, revisions 12,
  schema_migrations 9, each row count checked), and `MANIFEST.json` with the sha256 of every file. A
  secret-pattern scan of the JSONL found nothing. **It is outside the repository on purpose:**
  `c-u-l8er/graphonomous` is public, these rows are private session memory, and [T5] is unruled.
- **L-2 — the LEGACY banner is on `graphonomous/README.md`.** It gives the measured reason and the two
  flags that stop the pruning (`--consolidator-decay-rate 0.0 --consolidator-prune-threshold 0.0`, both
  accepted by `lib/graphonomous/cli.ex`). `graphonomous.com` needed nothing: its 2026-09-05 rebuild
  already retracts the v1 engine, and the old install command appears only inside that retraction.

**Not done — each needs [TRAVIS]:**
- **L-3** `npm deprecate graphonomous` — public, so it is Travis's to do.
- **L-4** The Fly app `graphonomous-mcp` stays until fleetprompt.com and PRISM stop calling it (R96: torn
  down last).
- **L-5** The PRISM plugin runs the same per-session pattern; not measured here and not touched.
- **L-6** The plugin's description in `ampersand-plugins` still says "v0.3.2 … 29 MCP tools"; the server
  exposes 5 and reports itself as 0.4.0 (hard-coded in `lib/graphonomous/mcp/machines/server.ex`).

## 7. Stages — after the Super MVP (R97), built WITH Super

- **V3-0** This spec, and the rulings T1–T8.
- **V3-1 Offline bench, with no infrastructure.**
  - (a) *Recall:* real questions taken from session transcripts (the first retrievals sessions actually
    made), each with its expected memory file or ruling id. The baseline is `MEMORY.md` plus `grep`.
  - (b) *Deciders:* labeled pairs for Q-SAME, Q-CONTRA and Q-SUPERSEDE. Candidate label sources, counted by
    `grep` over the memory directory on 2026-09-27: "WRONG" 74, "FALSIFIED" 19, "RETRACTED" 13,
    "SUPERSEDED" 13, "CORRECTED" 10 occurrences, plus the register's own supersessions. These are
    occurrences, not labeled pairs; building the pairs is the work.
  - Compare hosted Jev (fractions of a cent per run), the Ollaya models (after [T3]) and a deterministic
    baseline, and fit temperatures per question type. A question enters the catalogue only if its decider
    beats its baseline on held-out labels [T4].
- **V3-2** The journal and law J-1, in v2's test harness under its heap caps.
- **V3-3** The `RULINGS` and `FILE MEMORY` adapters; `recall` and `explain` from the CLI.
- **V3-4** The A1 daemon, read-only, and a new plugin version pointing at it. Only then may a `CLAUDE.md`
  tell sessions to use it again.
- **V3-5** `propose`, the floor and the judge, with `DECISION` certificates.
- **V3-6** The A2 Super capability and the `RECEIPTS` family: the loop `site/index.html:729` describes.
- **V3-7** v1's Fly app is torn down once its consumers have moved (R96).

## 8. Falsifiers — what stops or shrinks Graphonomous v3

- **F1** If V3-1(a) recall does not beat index + `grep` on real questions, J1 is not worth building: keep the
  file memory and stop at v2.
- **F2** If no decider beats its deterministic baseline on our labels, drop the judge. Graphonomous v3 keeps
  the floor and recall.
- **F3** If law J-1 fails on any range, the journal design is wrong, and rebuild stays the only path.
- **F4** If a `DECISION` cannot be replayed to the same answer on the same model digest (*reported*: fp16
  can flip near-ties), decisions are recorded as non-replayable and may not gate anything.
- **F5** If Super's receipt shape changes during stage 0, V3-6 waits. Nothing earlier depends on it.

## 9. Open rulings [TRAVIS]

- **T1 — Name.** "Graphonomous v3", or a distinct name that cannot collide with `semantic.v3` or G3.
- **T2 — Where the decider runs** (§4.7), and whether "MCP servers make no LLM calls" covers a local,
  recorded, sub-second decider.
- **T3 — Installing Ollaya.** The installer is `curl -fsSL https://ollaya.dev/install.sh | sh` from a
  project days old (*reported*: v0.3.1 → v0.7.3 between 2026-09-24 and 2026-09-27), or a pinned build from
  source. Which model, given 8 GB of VRAM.
- **T4 — Gates.** The quality and calibration thresholds a question must meet to enter the catalogue.
- **T5 — Confidentiality.** Does carried memory hold personal or secret content? This is the same question
  as studbook §10.2 (content addressing versus access control), and F-2 is only the floor of it.
- **T6 — Profile family.** `graphonomous.semantic.vN`, or a separate `graphonomous.memory.v0`.
- **T7 — Embeddings.** Which local model, or none (lexical plus structural recall only).
- **T8 — The file memory's role.** A source Graphonomous v3 imports, or the primary store with Graphonomous
  v3 as a certified index over it.

## 10. Research record — *reported*, fetched 2026-09-27 by a web research pass, not reproduced here

**Ollaya** — [github.com/ollaya-dev/ollaya](https://github.com/ollaya-dev/ollaya),
[ollaya.dev](https://ollaya.dev), [API](https://github.com/ollaya-dev/ollaya/blob/main/docs/api.md).
- Rust, Apache-2.0, "not affiliated with Ollama or TypeSafe". The creator is named elsewhere as Mert Cobanov.
- Default address 127.0.0.1:11435. `POST /v1/systemone` and `/v1/decisions`, an Ollama-style `/api/tags`,
  and a native `/api/decide`.
- Limits: 1–256 questions per request and 65,536 state tokens, with `STATE_TRUNCATED` rather than a silent
  drop.
- Models run on ONNX Runtime (CPU / CUDA / MLX), and GGUF models on llama.cpp (since v0.7.0).
- A decoder model answers by reading the final-layer scores for the option letters at `Answer: (` and
  softmaxing over the valid letters: one pass, no generation. Calibration is per-model temperature
  scaling.
- `ollaya mcp` shipped in v0.4.0. It has no embeddings and no fine-tuning inside Ollaya; the upstream
  decider model documents a LoRA recipe.
- Author-measured on an RTX 4090 against hosted Jev at 0.738 (which includes network time): winnow:e4b
  0.722 @ 89 ms, decider:4b 0.680 @ 520 ms, laya 0.361 @ ≈ 10 ms. JevBench v1.4.2.2
  ([benchmarkheaven.com/jev-models](https://benchmarkheaven.com/jev-models)): decider-4b v2 64.1, Jev 1.13.0
  63.3.

**Jev** — [TypeSafe blog](https://typesafe.ai/blog/introducing-system-one-models-and-jev),
[OpenRouter guide](https://openrouter.ai/docs/guides/community/typesafe-sdk).
- Proprietary, "System One": a non-autoregressive single pass. $0.042 per million input tokens; output is
  free. `typesafe/jev-1.13`.
- There is no official calibration figure. An out-of-distribution study
  ([scienthoon/jev-ood-calibration](https://github.com/scienthoon/jev-ood-calibration)) measured ECE 0.107,
  erring in a different direction per question type.
- Already used live in this tree by alphapiler (`~/Projects/Travelmonstr/alphapiler/src/jev.js`).

**Deciders in memory systems**
- [lyonwj.com](https://lyonwj.com/blog/typesafe-jev-knowledge-graph-extraction), knowledge-graph extraction:
  - a two-question `noul` assertion gate lifted precision 0.279 → 0.404 with no lost true edges;
  - a 3-level `score` for entity resolution lifted B³ F1 0.946 → 1.000;
  - a `noul` contradiction check separated planted contradictions where cosine similarity could not;
  - and *"a System One model can't find an edge."*
- [arXiv 2609.23986](https://arxiv.org/html/2609.23986v1) (Jev-Mem): Jev as the memory controller for typing,
  dedup/contradiction and retrieval routing; LoCoMo 0.777 against 0.700 for the best baseline.
- [Memworthy](https://github.com/AfnanHussain10/Memworthy): gated memory with eight actions and a replayable
  JSONL ledger.
- No integration was found in Graphiti/Zep, Letta, cognee, LangMem or the official MCP memory servers.

**MCP** — [2026-07-28 release](https://blog.modelcontextprotocol.io/posts/2026-07-28/): a stateless core (no
handshake, no `Mcp-Session-Id`), Tasks as an extension, and Roots / Sampling / Logging deprecated.

**Could not verify:** Ollaya's first-release date; the exact tool names `ollaya mcp` exposes; whether Ollaya
can refit temperatures from user labels; any Jev architecture detail; and latency on this machine's GPU. The
sources also disagree on Jev's calibration error (0.027 vs 0.246) and its accuracy (0.727 vs 0.738).

## 11. Sources in the tree

`graphonomous/config/config.exs` · `graphonomous/lib/graphonomous/consolidator.ex` ·
`graphonomous/scripts/graphonomous_mcp_wrapper.sh` · `graphonomous/v2/README.md` ·
`graphonomous/v2/handoff/{STATUS.md,DECISION_LOG.md}` · `graphonomous/v2/lib/{project,query,evaluation}.mjs` ·
super-live `cockpit/src/{claude,codex}_connection.rs`, `site/index.html`, `site/AGENT_SUPER_APP_BLUEPRINT.md`,
`ampd/lib/ampd/{capability_registry,receipts,projection}.ex` · `FOUNDATION_LANE.md` · `REVISION_REGISTER.md`
(R96, R97) · `AGENCY.md` · `AmpersandBoxDesign/box-and-box/README.md` (the bridge) · alphapiler PASS 9
(memory `project_cyberutensil_compiler`).
