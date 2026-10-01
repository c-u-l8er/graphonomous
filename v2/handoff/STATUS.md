# STATUS — Graphonomous G0/G1

Vocabulary (from the brief, used exactly): `DESIGNED` · `IMPLEMENTED` · `TESTED` · `FROZEN` · `BLOCKED` · `PROPOSED`.
Nothing is called TESTED because code exists. Every count below is copied from a command output named beside it
(`npm run test:full-tree`, `node bin/g0.mjs verify|eval|verify-eval|world|certify|check-cert|closure|consistency`,
`python3 test/canon_twin.py --selftest`, `node tools/g05_build.mjs`, WRL `node test/conformance.mjs`, TRVM
`make governance`).

**2026-10-01 — D-079's push precondition is met; graphonomous is pushed as-is, history preserved.**
- **Travis's word, in chat:** "done". He deleted every OpenRouter key and made one new key, stored with `~/.config/alphapiler/store-openrouter-key.sh` (mode 0600; checked in memory: changed, and not equal to any leaked key). He also cleaned the old key's line out of `~/Documents/README.txt`; Claude never opened that file.
- **Found on the way, counted and never printed:** two OLDER OpenRouter keys were already public on GitHub. One was in `fleetprompt.com`'s history (2026-01-08). The other was in this repository's tracked `.env.rescore`, from `27a59b9b` (2026-04-08). Revoking them made both inert. `78098273` stops tracking `.env.rescore` and adds `.env` to `.gitignore`. The file stays on disk, mode 600, for `run_rescore*.sh`.
- **Pre-push scan of the 22 unpublished commits:** 38,433 added lines and no secret-shaped string (Anthropic, OpenAI, OpenRouter, GitHub, AWS, Slack, Google or Stripe keys, private-key blocks, bearer tokens).
- PUBLIC-PROJECTION-1 stays OPEN and inspect-only, as D-079 says.

**2026-09-28, later — D-079: the source boundary. The v3 closure is settled; next is v2 implementation.**
- **SB-1…SB-4 now hold for every family:**
  - read authority is not publication authority, so private derivations go in `~/.graphonomous/v2/`;
  - authority is per record;
  - a proposal is not a fact;
  - `REFUSE_SECRET` at intake.
- **Source order:** WRL → ruling register → memory folder.
- **PUBLIC-PROJECTION-1** is OPEN (ROADMAP §3). It asks whether what `origin/main` already publishes, from
  `computedriven`, `invariant-r10` and the factory ledger, had publication authority. It is inspect-only, and
  it blocks nothing.
- **Push:** authorized as-is, history preserved, once the plaintext credential is moved out and rotated.
  - The memory note's copy was moved out the same day.
  - Rotation and the notebook are Travis's to do, so the push waits for his word.
  - The root repository stays held.

**2026-09-28 — D-078: there is no Graphonomous v3. v2 grows instead.**
- **The ruling.** Both V3-1 benches were negative for the new machinery. Travis ruled that the v3 proposal is
  closed as tested and not justified (`docs/spec/v3/README.md` is now a closed record, §C). The surviving
  requirements are **`handoff/ROADMAP.md`**, all `PROPOSED`, nothing built:
  - the ruling register and the memory folder as source families;
  - authored relations only;
  - abstention or review;
  - BM25 outside the core.
- **Nothing in this directory's code changed.**
- **The three older unpushed v2 commits were inspected before any publication, 2026-09-28** (`32bad457`,
  `ef86374c`, `61adec2d`; `origin/main` = `824b9688`, their direct parent):
  - `32bad457` is 12,784 files, +37 MB of tree. 12,656 of those files are `projections/tri`. It holds
    the committed-as-found state of D-072…D-077.
  - A pattern scan of every added line found **no secret-shaped string**. The 33 hits on "secret"/"password"
    are TRVM law names such as `proof.reveal-gates-secret-execution`.
  - The `/home/travis/…` paths it adds are the same kind `origin/main` already carries.
  - The only source it adds to what `multi` already published is TRVM governance: 66 files at `8816e59`, in
    the PUBLIC `c-u-l8er/TRVM`, on its public branch `merge/governance-plane`.
  - **Re-checked read-only**, under a 1.5 GB memory cap because the machine had 3.1 GB free:
    - `g0 verify --dir projections/tri` → `root-ad27b735…`, 11,204 entries, **0 problems**.
    - `g0 check-cert --dir projections/tri` → exit 0, **0 writes**.
    - `world/identities.json` gives `graphonomous.semantic.v2`, 3,928 objects, 2,494 relations, which is what
      `ef86374c` says.
  - `61adec2d` is docs only: R17, and a STATUS edit.
  - **Not re-run:** `npm run test:full-tree`. The 182 / 1 / 0 result is `32bad457`'s own record, from
    2026-09-08.
  - **Nothing was pushed.** Publication waits on Travis's word.
  - **One older exposure is recorded in ROADMAP §3,** because it is the same question as the private new
    sources. It was not introduced by these commits.

**Stage (2026-09-08, read from the artifacts, not from this file's history): the `tri` projection is SEALED under
`graphonomous.semantic.v2`** at WRL `6a8304c` (WRL-P1, `STACK_FIX_RECEIPTS/WRL-P1.md`, D-077) — `objects 3,928 ·
relations 2,494` (the 2,469 of the v1 seal plus the 25 law→law `SUPERSEDES` propositions TRVM states at `8816e59`),
projection root `root-ad27b735…`, `sem-3a80601c…`, certificates `vclaim-332109b0…` (v0) / `vclaim-c8801a54…` (v1),
state string still "SEALED by WRL (WRL-P0); FROZEN only when GPT accepts this round" by the rule in
`WRL_SCHEMA_OR_PROFILE/FROZEN.md`. The table below still shows `tri` as the v1 seal (`sem-b50742ea…`, 2,469): that
was true when the table was written and is kept; the v2 numbers above are measured from
`projections/tri/world/identities.json`. Committed as found on 2026-09-08 (`32bad457`) after `npm run test:full-tree`
→ GREEN 182 / 1 skipped / 0 failing; the sessions that built it ended 2026-09-06 without committing. **WRL as the fourth source family: the read-only INVENTORY is done (2026-09-08, `handoff/research/R17_WRL_SOURCE_INVENTORY.md`,
measured at WRL `32160fe`)** — four admitted profile rows, 24 relation codes, the spine's 6 roles / 2 kinds / 22 codes, 924/0
conformance, 5 + 38 projection vectors; the family SPLITS: its world-level objects (profiles, registries, vectors) fit v2,
its VOCABULARY (roles, kinds, endpoint pairs, codes, policy ids) does not, so the inventory returns the minimal
`graphonomous.semantic.v3` obligation (one role `VOCABULARY_ITEM`, two kinds `ADMITS` and `REFUSES_WITH`) for adjudication
rather than widening v2 (D-077). No adapter, no snapshot, no projection yet. Not started: a write surface,
`graphonomous.evidence.v0`, the TRVM primitive-basis round.

**Stage (2026-09-03, after GPT Adjudication v6 — D-065…D-074): `GRAPHONOMOUS-PROJECTION-v1` → G1 cross-registry
consistency → TRVM governance as the third source family is reached and stops here for review.** v6 recorded
(D-065…D-071) → **G0.5-R1/R2** clean-checkout reproducibility closed → **`GRAPHONOMOUS-PROJECTION-v1`** with a
verifier-derived required schema closure → **`adapters/trvm.mjs`** and the `tri` projection over **three source
families** → **`graphonomous.consistency.rules.v0`**, six accepted rules and three reduced to zero → a read-only
**CONSISTENCY** tab. Nothing pushed. Not started: a write surface, `graphonomous.evidence.v0`, the TRVM
primitive-basis round.

## Verdict

- **G0.5-R1/R2 `TESTED` and closable.** `node --test test/g05.test.mjs` in a tree with `ui/data` **moved out** now
  reports **11 tests · 10 pass · 0 fail · 1 skipped** — the skip being the developer staleness check, which says the
  build command instead of failing. The payload is built into a temp directory shaped as a complete `ui/` fixture, and
  the server test serves that fixture. `npm run test:repro` is the documented clean-bundle target and
  `npm run test:full-tree` additionally asserts the pinned registries are reachable so a skip cannot hide a
  regression. Receipt: `handoff/receipts/G05-R1-R2.md`.
- **`GRAPHONOMOUS-PROJECTION-v1` `TESTED`.** The required schema closure narrows **12 indexed → 9 required**, keyed on
  each schema's `$id` rather than its basename, derived by the verifier from the projection's own `adapter_run`
  records through `contracts/projection.v1.json`. Ten of the eleven acceptance laws hold as written; **law 5 is
  sharpened** (activation always moves `projection_contract_id`, and moves `schema_closure_id` iff it introduces a new
  schema) and **law 4 splits**, with 4b measured as an open residue — see below. Research: `R16`. **No TRVM change was
  required and the stop condition was checked, not assumed** (R15 §7).
- **TRVM governance is the third source family, and `graphonomous.semantic.v1` ADMITTED it.** 66 pinned files, 257
  nodes, 462 relations, **zero new faults**. The one thing v1 could not represent — TRVM's 24 law→law supersessions —
  is **deferred with both coordinates preserved and no edge**, and the `graphonomous.semantic.v2` obligation is
  exactly one line: admit `SUPERSEDES [LAW, LAW]`.
- **G1 finds 15 real cross-registry findings**, the sharpest being that one snapshot reads
  `TRVM/governance/invariant-grid.json` at **two different blobs**. Three of GPT's seven candidate rules **reduced to
  zero against the data and are not implemented**, each with its measurement and a re-open condition, both in the
  rulepack and on the page.
- **The law-4b residue happened for real in this milestone.** Registering the fourth adapter needed one row in
  `lib/project.mjs`, which is inside `codeId(PROJECTOR_MODULES)`. Measured on all eight receipts: **exactly one
  coordinate moved — `chain_ids.projector` — and nothing else did.** `projections/pre-trvm/` preserves the four v0
  goldens GPT froze byte-for-byte; the live checker refuses each on exactly `gproj-chain-id-mismatch` +
  `gproj-certificate-stale` while reporting the unchanged projection root.

`npm run test:full-tree`: **183 tests, 182 pass, 0 fail, 1 skipped by design** (was 151/150/0/1). WRL **901/901**.
TRVM `make governance` 32/32 at `8816e59` — **not re-run this round, because running it writes to the TRVM tree**
(R15 §8.2). `python3 test/canon_twin.py --selftest`: ok.

## The five projections

| | baseline | historical | multi (v0) | multi-v1 | **tri (NEW)** |
|---|---|---|---|---|---|
| profile | `…semantic.v0` | v0 | v0 | `…semantic.v1` | **v1** |
| adapters | crosswalk | crosswalk | + factory | + factory_mosaic | **+ trvm** |
| source families | 1 | 1 | 2 | 2 | **3** |
| nodes · relations · faults | 289 · 588 · 64 | 278 · 566 · 64 | 778 · 1,574 · 86 | 932 · 2,007 · 86 | **1,189 · 2,469 · 86** |
| projection root | `root-da4f3d7a…` | `root-c7f9c759…` | `root-48ac3e32…` | `root-44659ae7…` | `root-2f50a00d…` |
| evaluation root | `root-c5d650b0…` | `root-edcd9f6f…` | `root-472a5d32…` | `root-57405697…` | `root-2032e47f…` |
| WRL `sem-` | `sem-0f952f03…` FROZEN | `sem-3ae051cf…` FROZEN | `sem-b8d82827…` FROZEN | `sem-e186186e…` FROZEN | **`sem-b50742ea…`** |
| v0 certificate | `vclaim-70627f53…` | `vclaim-008e0be5…` | `vclaim-691c70db…` | `vclaim-a4e912d8…` | `vclaim-48b19fab…` |
| **v1 certificate** | `vclaim-d5a10210…` | `vclaim-c86f2f03…` | `vclaim-58bbe816…` | `vclaim-6c688e70…` | `vclaim-47e59e34…` |
| `schema_closure_id` | `gschema-25c33684…` | same | same | same | same |
| `projection_contract_id` | `gpcon-8a31a4b9…` | same as baseline | `gpcon-45fa731a…` | `gpcon-497da936…` | `gpcon-db5b75e8…` |
| consistency root | `root-b8601e01…` | `root-1e0798bb…` | `root-d1e62eb1…` | `root-c06e8ed1…` | `root-10d593a5…` |
| findings | 5 stale | 5 stale | 4 stale | 2 stale | **1 drift · 1 drift · 13 unresolved** |

The v0 `vclaim-` values in this table are the **re-mint** (D-073). The four GPT froze in v6 §0 —
`vclaim-67038bf9… · vclaim-e148f86d… · vclaim-7bbcc6d2… · vclaim-1a029671…` — are preserved byte-for-byte in
`projections/pre-trvm/` and remain reproducible under their pinned coordinates.

Pins: TRVM **`8816e59055322fc608c9bc7dae9723c02d8402b7`** (governance source, 66 files) and **`fd0df4c…`** (the
crosswalk's evidence view, 3 files — the two are deliberately distinct, and G1 says so) · WRL
**`53e5e8995913995189f7017d2a94351ff69d5b31`** · factory `d217ee29a3322c68db0d43be47491f0e9d4fbc64` · r10 `ba4e625`.

## The required schema closure (D-072)

`contracts/projection.v1.json` states, per adapter, which record kinds it emits — **measured** by running each adapter
alone (`handoff/research/probes/c1/probe_adapter_emits.out`); all four currently emit the same six, so the closure does
not discriminate by adapter *today* and will the moment one emits a new kind. Required: `node relation assertion
source_location fault adapter_run manifest snapshot rules`. Excluded, each with a stated reason: `common` (a generator
input; nothing loads it at runtime), `derived_fact` and `evaluation` (the G0-E lane, a separate root the certificate
checker never reads).

**What v1 does not solve, stated rather than papered over** (D-072): def granularity, because
`schemas/build_schemas.mjs` inlines `common.$defs` into all twelve documents; a read-only verifier cannot observe what
the producer actually *loaded*; and there is no cryptographic trust boundary, only the guarantee that the closure
cannot change without moving a pinned code identity.

## Items

| Item | State | Evidence / note |
|---|---|---|
| `DECISION_LOG.md` | IMPLEMENTED (document) | D-001…D-079 (was D-001…D-074 when this table was written) |
| `handoff/ROADMAP.md` | PROPOSED (document) | D-078's survivors under D-079's source boundary: WRL → register → memory folder, `~/.graphonomous/v2/`, SB-1…SB-4, the review path, the BM25 boundary, PUBLIC-PROJECTION-1 |
| `handoff/receipts/G05-R1-R2.md` | IMPLEMENTED | the clean-checkout closure, before/after |
| `handoff/research/R15_TRVM_SOURCE_INVENTORY.md` | IMPLEMENTED (measurement) | every count re-verified by this session against the git object store |
| `handoff/research/R16_SCHEMA_CLOSURE_PRIOR_ART.md` | IMPLEMENTED (research) | 5 mechanisms classified ADOPT/ADAPT/REJECT; 3 measurements of this tree decided the design |
| `contracts/projection.v1.json` · `lib/closure.mjs` · `test/projection_v1.test.mjs` | TESTED | 15 tests over the eleven laws |
| `adapters/trvm.mjs` · `snapshots/tri.json` · `projections/tri/` | TESTED | seal under frozen v1, 0 new faults, the deferral measured |
| `lib/consistency.mjs` · `test/consistency.test.mjs` | TESTED | 16 tests; positive fixtures on real data, negative fixtures for every accepted rule |
| `ui/` CONSISTENCY tab, five worlds | TESTED | `test/g05.test.mjs` 11/11; screenshots in `ui/screenshots/g1-*` |
| `projections/pre-trvm/` | IMPLEMENTED (receipts) | the GPT-frozen goldens, and the one coordinate the registration moved |
| `graphonomous.semantic.v2` | PROPOSED (obligation) | one line: admit `SUPERSEDES [LAW, LAW]` |
| write surface · `evidence.v0` · TRVM primitive basis | not started | by ruling (D-070, D-071) |

## Open — for the adjudicator

1. **Law 4b.** Closing it means moving the `ADAPTERS` registry (and `lib/lid.mjs`'s vocabulary enums) out of projector
   code into versioned data — a one-time move that **re-mints every v0 certificate again**. The measurement is handed
   up rather than the change being taken: this lane does not move a frozen thing to close a law on its own authority.
2. **`graphonomous.semantic.v2`**, minimal: admit `SUPERSEDES [LAW, LAW]` so TRVM's 24 law supersessions become edges.
   Everything else about the third source fitted v1.
3. **The two rule names not on GPT's list** — `SOURCE_PIN_DIVERGENCE` and `CROSS_REGISTRY_COREFERENCE_UNLINKED` — and
   the three candidates reduced to zero, each with its re-open condition.
4. **The 13 unlinked co-references.** Linking them needs a decision about who owns a cross-family identity edge; the
   finding deliberately proposes nothing.
5. Whether `REFERENCE_TARGET_DRIFT` on `invariant-grid.json` should be **repaired at the source** (re-pin the
   crosswalk's TRVM view) or left as a standing, visible finding.
