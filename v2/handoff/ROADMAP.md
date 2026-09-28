# ROADMAP — Graphonomous v2 after D-078 and D-079

**Written 2026-09-28, the day of D-078 (there is no Graphonomous v3, and v2 grows instead) and D-079 (the
source boundary).**
- This file holds the requirements that survived the closed v3 investigation (`docs/spec/v3/README.md`), each
  placed under the part of the stack that actually owns it.
- Every item here is `PROPOSED` in STATUS's vocabulary. Nothing is built, and nothing skips the lane's order:
  inventory → ingestion contract → profile obligation → adjudication → build.
- `STATUS.md` stays the only place that says what is built or tested.
- **The v3 closure is settled.** What follows is v2 implementation work.

**The standing invariant, carried from V3-1 (b): prefer missing a relation over asserting a wrong one.**

**The source boundary (D-079).** These rules hold for every family, the old ones and the new:

| Rule | What it says |
|---|---|
| **SB-1** | **Read authority is not publication authority.** Anything derived from a source whose publication is not established lives in `~/.graphonomous/v2/`, never in this public repository |
| **SB-2** | **Authority belongs to the record** (its provenance and its status), never to the family or the ingestion order. There is no global precedence between families |
| **SB-3** | **A proposal is not a source fact, and a source fact is not yet an accepted relation.** A reviewer's or model's output is a candidate until an authorized source records it |
| **SB-4** | **`REFUSE_SECRET` at intake**, before projection, candidates, benchmarks, model context, or public receipts. Detecting secret-shaped text is enough; a secret never has to be confirmed |

## 0. Queued before D-078, unchanged by it

- **WRL as the fourth source family** (D-077, authorized next). The R17 inventory is done; the minimal
  `graphonomous.semantic.v3` *profile* obligation awaits adjudication. That id is a profile version and has
  nothing to do with the closed product v3.
- **Linkage** (D-076), then `graphonomous.consistency.rules.v1`, frozen only after re-measurement.
- **Law 4b** (STATUS "Open" 1).

**Order — ruled (D-079): WRL → ruling register → memory folder.** Ingestion order implies no authority order
(SB-2).

## 1. Source family — the ruling register

| | |
|---|---|
| Source | `REVISION_REGISTER.md` in `c-u-l8er/ProjectAmp2` |
| Pin | a commit. The file is tracked, so `adapters/git.mjs` (pinned, read-only, never the working tree) works unchanged |
| Visibility | **PRIVATE** (`gh repo view c-u-l8er/ProjectAmp2 --json visibility`) — see §3 |
| Gate | a read-only inventory in the R15/R17 pattern, before any adapter |

**Measured 2026-09-28 at root `c739879`:**
- **100 rows** (`grep -cE '^\| R[0-9]' REVISION_REGISTER.md`).
- **A row's authority varies by row.** It is recorded in the last column: Travis 24 · "Claude, outside review" 20 ·
  measured 16 · "measured, outside review" 14 · re-derived 7 · open 3 · other 2. Two rows are marked
  `UNRULED`. **The inventory has to classify authority per row**, because an unruled or measured row is not
  a ruling. The register as a whole outranks nothing (SB-2).
- **Authored relations to other rows are rare.** About 13 rows use an explicit verb before an R-id:
  "superseded" 7 · "supersedes" 2 · extends · completes · closes · amends, 1 each. 45 rows mention
  another R-id somewhere in their prose.

**What may become a relation:**
- A **mention** is deterministic: the row's text contains `R96`. It may become a reference relation of the
  `CITES` kind.
- A **transition** (`SUPERSEDES`, and anything like refines, amends or retracts) becomes a relation **only**
  from an explicit authored form with a deterministic grammar. The inventory says which forms qualify.
- Prose that merely implies a transition is not parsed into one.

## 2. Source family — the memory folder

| | |
|---|---|
| Source | `~/.claude/projects/-home-travis-ProjectAmp2/memory/*.md`, indexed by `MEMORY.md` |
| Pin | **none exists yet.** The folder is in no repository, so `adapters/git.mjs` cannot pin it. It needs a content-addressed directory snapshot: a sha256 per file plus a manifest hash. V3-1 (a)'s `bench.py` already built one (`corpus_manifest.json`). Whether a new pin kind fits the FROZEN `GRAPHONOMOUS-PROJECTION-v1` (D-075) or needs a new projection contract is **for the inventory to answer, not to assume** |
| Visibility | **PRIVATE** — see §3 |
| Authority class | not settled. The notes are written by sessions, and some are Travis's words relayed. Treat it as an inventory question, never as "authoritative" by default |
| Churn | many parallel sessions edit it continuously, so every projection names its snapshot and every answer is `as_of` it |

**Measured 2026-09-28:**
- **150 notes.** 121 carry a frontmatter `name:`.
- **315 `[[link]]` occurrences, over 130 distinct targets.** 105 of those targets resolve to a note name or
  filename.
- **One note carried a live credential**, found by pattern. The value was not printed. The key was moved out
  the same day (D-079), and the folder now has 0 secret-shaped strings. A byte copy remains in V3-1 (a)'s
  frozen corpus under `~/.graphonomous/v3-bench/`, and rotating the key makes it inert.
- Transition words, counted as occurrences, not pairs: WRONG 74 · SUPERSEDED 14 · RETRACTED 13 ·
  CORRECTED 10.

**Before anything is ingested — SB-4, required by D-079:**
- The adapter's first step is **`REFUSE_SECRET`**. A note with secret-shaped text is refused or quarantined
  whole, **before** its bytes reach any of these:
  - the snapshot the projection reads;
  - a relation candidate;
  - a benchmark corpus;
  - model context;
  - a receipt.
- **Redacting after projection is not allowed.** V3-1 (a)'s corpus copier is the counter-example: it copied
  notes byte for byte, secret included.
- The refusal records **`secret-shaped text detected`**: the file, the pattern class and the offset, never the
  value. No state claims `confirmed secret`.
- **The pattern set is part of the adapter's code identity.** Widening it moves the adapter's pin.

**What may become a relation:**
- **A resolving `[[link]]`** is a deterministic reference relation.
- **A dangling link is not an edge.** It becomes an unresolved finding, like `LAW_REFERENCE_UNRESOLVED`.
- **Transition words are prose, not grammar.** V3-1 (b) needed Claude's transcription to turn them into pairs,
  so they are not deterministic and are **not emitted**. At most they are candidates for review (§5).
- A candidate consistency rule for later, from v3's F-3/F-4 as narrowed by SB-2: **a note that contradicts a
  record whose own status makes it a current ruling is a FINDING** (D-071: a finding is not a fault).
  - It is a finding, never a relation that outranks that record.
  - A register row that is measured, open or unruled is not a ruling. Nothing outranks a note merely because it
    sits in the register.

## 3. Private sources in a public repository — ruled (D-079, SB-1)

- `c-u-l8er/graphonomous` is **PUBLIC**. Until now v2 has committed its projections into the repository
  (`projections/*`).
- **Where private derivations live: `~/.graphonomous/v2/`** (mode 0700). That covers projections, local indexes,
  local evidence and review candidates for any source whose publication authority is not established. **Both
  new families are in this class.**
- **The public repository may carry only:**
  - implementation;
  - schemas;
  - aggregate or count metadata, when safe;
  - content hashes and receipts, when safe;
  - verification results.
- **Not in the repository:**
  - a UI payload built from these families;
  - site content built from them;
  - any receipt that quotes them.
- **Not yet built:** a private companion repository, or replication across machines. Either comes only when it
  is needed, as a private content-addressed store or a private repository.
- **The consequence for code.** A projection's output directory for a private family must resolve under
  `~/.graphonomous/v2/`. A test in the repository can check that, using a synthetic private fixture (the
  pattern of `test/helpers/fake_repo.mjs`), without ever reading the real source.

### PUBLIC-PROJECTION-1 — an audit of what is already published (OPEN; blocks nothing)

- **Question (D-079):** does any currently published projection reveal source content or metadata that would
  not independently have been authorized for publication?
- **What it is not about.** It is not about whether a repository has a remote. A source can be private while
  facts derived from it are intentionally public.
- **Scope, measured 2026-09-28.** Every snapshot on `origin/main` (`baseline`, `historical`, `multi`,
  `multi-v1`) reads three sources that have no public origin of their own:

  | Source | Visibility | Files read |
  |---|---|---|
  | `computedriven` at `efa8881` | a PRIVATE repository | 6 |
  | `invariant-r10` at `ba4e625` / `699fbc2` | no remote | 22–23 |
  | the factory ledger at `d217ee2` | no remote | 3, or 66 in `multi` / `multi-v1` |

  - Their projections, and the `pre-*` receipts, are on `origin/main`.
  - `adapters/factory.mjs` keeps prose **verbatim** as attributes, so source text crossed the boundary. It is
    more than ids and counts.
- **Method.**
  1. Inventory, per source, which record fields carry verbatim text and which carry only structure.
  2. For each, find whether an independent publication already exists, such as a public site generated from
     the same file.
  3. Classify each field as **authorized** (independently public, or published on purpose), **unauthorized**,
     or **undetermined** (a question for Travis).
- **Inspect first. Remove nothing merely because its source was private.** Any removal is a later, separate
  decision, and rewriting published history is not assumed.

## 4. Relation governance — what already exists, and what is retained

These are v2 mechanics, unchanged by D-078:
- endpoint-pair refusal at emission and at projection (`lib/lid.mjs`, D-037);
- frozen profiles, where a change goes to a new profile version (D-050);
- linkage refuses an ambiguous target instead of guessing (D-076);
- a FINDING is not a FAULT (D-071).

Emission classes for the new families:

| Class | Example | Rule |
|---|---|---|
| reference | a resolving `[[link]]`; a row mentioning `R96` | emitted: syntax alone establishes it |
| authored transition | a register row's explicit `Supersedes R9` | emitted **only** under a grammar the inventory fixes, with the quote and location as provenance |
| anything else | "this note refines that one", from reading | **not emitted.** Abstain, and at most queue it for review |

**No model is placed in the emission path.** V3-1 (b) is why:
- Governed Jev made 6 false `supersedes`, at confidence up to 0.86, above its correct answers' median of 0.78.
- No threshold separates those errors from its right answers.
- The Claude judge was inconsistent across slices.

## 5. Review and abstention path

- **Abstain is the default.**
- **The review queue is a list of candidate pairs with provenance.** It lives beside the projection, is never
  part of its relations, and is never certified as fact.
- **Ruled (D-079, SB-3): a proposal is not a source fact, and a source fact is not yet an accepted relation.**

  ```
  model / reviewer says "A supersedes B"
      → candidate / review artifact       (in ~/.graphonomous/v2/; NOT graph truth)
      → an authorized source records it   (the note, or the register row, as authored text)
      → the source is re-pinned and re-projected
      → Graphonomous may derive the accepted relation
  ```

  - Graphonomous may hold candidates, ephemeral and private. It never stores a verdict as its own truth. That
    keeps D-071 (no write surface) and the definition (*sources it does not own*) intact.
  - A Claude, Jev or reviewer output gains no authority because Graphonomous observed it.
  - The cost is that a review needs an edit in the source. That edit is exactly the authored statement §4
    asks for.

## 6. Boundary — BM25 recall stays outside

- **The tool is `scripts/memory-search.py`** in the root repository (`31fda46`). It is V3-1 (a)'s S3 byte for byte;
  `--check-bench` re-proves it. Its own docstring says it is not part of Graphonomous.
- **Graphonomous does not import it, call it, or store its scores.** A rank is never a relation and never
  evidence (`v2/README.md`: deterministic, content-addressed, replayable transforms only).
- **Both read the same folder, independently.**
- **The only permitted crossing is in §7's research lane**, where a search hit may nominate a candidate pair
  for human review.
- **Re-test recall** (v3 F1's own re-open condition) if the folder grows well past 147 notes, or if questions
  become sentences rather than keyword bags.

## 7. Research lane — non-authoritative, not scheduled

`candidate relation → model suggestion → human review`
- It is **not** in the trusted transition path, and it does not justify a v3.
- If it is tested, the measure is **review-load reduction** against §5's unassisted queue, under a **new**
  predeclaration. It does not reopen V3-1 (b), and it does not tune on that bench's frozen test split.
- Ollaya, or any other decider, enters only through a new predeclared experiment. Ollaya is still not
  installed.
- It needs §5 to exist first, because there is nothing to reduce until there is a queue.

## Not on this roadmap, by D-078 and D-079

- a Graphonomous-owned memory store;
- a recall daemon;
- a journal justified by the v3 proposal;
- model-mediated recall;
- automatic relation proposals by Jev or any decider;
- renumbering v2 as v3;
- a global precedence between source families (SB-2);
- a private companion repository or replication machinery, until needed (SB-1).

The v3 journal's law J-1 (fold equals rebuild) is not rejected on its merits. It lost its reason. If an
append path is ever needed, it arrives with its own justification.
