# SOURCE INVENTORY — Graphonomous G0 (G-PR0)

**Snapshot taken 2026-09-02.** Every row records what this lane actually read, at which revision, and what authority it
has. Revisions are `git rev-parse HEAD` in each sub-repository (ProjectAmp2 tracks none of them); loose files are sha256.
Authority classes: **AUTHORITATIVE** (the registry that owns its records) · **DERIVED** (computed from other registries;
rebuildable) · **HISTORICAL** (superseded versions kept for provenance) · **ADVISORY** (adjudication/briefing prose; binds
nothing by itself). Census detail (record counts, id schemes, vocabularies, dangling references) is in
`RESEARCH_REPORT.md` §Census and in `INGESTION_CONTRACTS/`.

## 1. The brief and its provenance

| Item | Location | Identity | Class | Note |
|---|---|---|---|---|
| Master prompt | `~/Downloads/GRAPHONOMOUS_FABLE51_MASTER_PROMPT_v1.md` | 21,230 bytes, 2026-09-02 15:35 | ADVISORY (the brief) | the only bundle file delivered |
| `02_RESEARCH_AGENDA.md` | — | — | **MISSING** | referenced by the brief; not in `~/Downloads`, the repo, or `files*.zip`. Reconstructed from brief §11 (D-004) |
| `03_STACK_REPAIR_PROTOCOL.md` | — | — | **MISSING** | reconstructed from brief §10 (D-004) |
| `sources/` (two verbatim notes) | — | — | **MISSING** | note #1 recovered verbatim from the invariant lane's transcript (session `c33dcf12`, user turn 2026-09-02T20:37:28Z); note #2 unknown |
| GPT note #1 (recovered) | this lane's research inputs (`PRIOR_LANE_GPT_NOTE.md`, 10,371 chars) | — | ADVISORY | "start Graphonomous in a deliberately subordinate mode" |

## 2. Repositories and their revisions at snapshot

| Repo / tree | Path | Revision (short) | Branch | Dirty | Class for G0 | Role |
|---|---|---|---|---|---|---|
| ProjectAmp2 (container) | `/home/travis/ProjectAmp2` | `90d254c013a6` | main | 15 untracked | — | container; tracks no sub-repo |
| graphonomous (this product) | `graphonomous/` | `5a9e00b23204` | main | 0 | — | v0.4 engine untouched; `v2/` is this lane |
| graphonomous.com | `graphonomous.com/` | `a6eb6165a89d` | main | 0 | — | marketing site; generated from `records/` |
| invariant-r10 | `invariant-r10/` | `699fbc2859ef` at census → **`ba4e625` at end of session** (v5 return `303f76c`: `package-v2.7/` per the GPT v4 adjudication; committed 16:07 local while the census ran) | main | 0 | AUTHORITATIVE for `package-v2.7/` (now the candidate canonical) and `package-v2.6/` (pinned historical); HISTORICAL for `package-v2.2…v2.5/`; ADVISORY for `inputs-gpt-*.md` (5 adjudications + GO; the v1 execution adjudication holding the S6 ruling exists only at the repo root) | **primary dataset**; two pins (D-008) |
| invariant factory canonical | `~/.invariant-factory/canonical.git` ref `refs/heads/invariant-canonical` | `d217ee2` (INV-R9.4) | — | n/a (bare) | AUTHORITATIVE | `CLAIM_LEDGER.json` (208 claims), `mosaic/*` |
| factory worktree (stale) | `~/.invariant-factory/wt-r9` | `2913613` (INV-R8.3 label) | — | 56 porcelain lines | **NOT a source** | 5 commits behind the ref by label, yet 60 of its 63 changed files are byte-identical to the ref's blobs (R7A §0): a stale label over current content; never read |
| a THIRD ledger state | `ProjectAmp2/CLAIM_LEDGER.json` + `ProjectAmp2/mosaic/` (tracked by the container) | `_round` INV-R7.8, **190 claims**, sha256 `b5a94117…` | main | — | HISTORICAL for G0 (the R7.x lane, content source of the factory's INV-R9 integration) | **the served `invariants.html` was built from this ledger** (`dist/artifact.json`: 182 claims @ INV-R7.6), not from the canonical 208 @ INV-R9.4 (Q-15) |
| computedriven (Edge/Fabric) | `computedriven/` | `21a1452eb6de` (R0.8.7; no remote) | master | 0 (a battery was writing git-ignored `lab/receipts-lab/` during the census) | AUTHORITATIVE for docs (7), receipts (39), code (5 crates + cd-micro); `receipts/STATUS.md` DERIVED | 88 commits; the package vendored `efa8881`, **26 commits behind HEAD**; F37/NC29/NC30 exist only here (not yet in any package at the census) |
| TRVM | `TRVM/` | `fd0df4cdf6ea` (in sync with origin) | `merge/governance-plane` | 0 (grid worktree == committed blob `9739bcc6`) | AUTHORITATIVE for `governance/invariant-grid.json` (v1.69.0; `date` field lags its commit by ten days) and `LAWS.md` (7 CANONICAL + 4 RESERVED, 0 Tier B) | law registry (138 entries / 107 ids / 106 canonical); derive protocol; `canonicalBytes`; `cas.mjs`; `certificate.mjs` |
| WRL | `WRL/` | `1f4c5fd4cf50` | main | 0 | AUTHORITATIVE (spec + identity spine) | `wrl.js`, `relation-identity.js`, `relation-v2.js`; conformance 890/890 re-run this session |
| TRAAVIIS | `TRAAVIIS/` | `dbe09009722c` | main | 0 | reference | the eight-rung identity ladder; RFC 8785 non-conformance finding |
| super | `super/` | `c4160fd06861` (2 commits ahead of `origin/main` = `7651697`, unpushed) | main | 3 → 4 (volatile: the worktree changed between two reads ten minutes apart — R7B) | AUTHORITATIVE for ampd code, the 42-vector conformance corpus, `release-receipt@3`; `docs/reviews/` (32) ADVISORY | the package vendored ampd `7651697`; receipts are sequence-numbered (`rcpt-NNNN`), not content-addressed; cite HEAD only |
| opensentience.org | `opensentience.org/` | `2c0f523dc597` | main | 0 | AUTHORITATIVE for `_invariants/data/cells.json` (46 cells) | the periodic table's data |
| AmpersandBoxDesign | `AmpersandBoxDesign/` | `7c692884fd1a` | main | 0 | reference | box-and-box law manifest discipline |
| studbook | `studbook/` | `9cc642ec590b` | main | 0 | ADVISORY (spec rung, unbuilt) | content-addressed record store spec |
| workbench | `workbench/` | `3947783c7b25` | main | 0 | reference | not used by G0 |
| WEK R0 documents | `ProjectAmp2/WEK_R0_*.md` (7) + `WEK_CENSUS_BASELINE.json` | tracked by the container repo, last touched `c1c7d82` 2026-08-28; sha256 per file in `research/census/R7B_census.json` | — | — | ADVISORY / DERIVED | WEK = "World Enforcement Kernel" (`WEK_R0_FINDINGS.md:165`); **no WEK code**; the frozen inputs the R0 documents review exist only in `~/Downloads` |

## 3. Files read verbatim this round (the frozen-input candidates)

| File | Bytes | Class | What it carries |
|---|---|---|---|
| `invariant-r10/package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json` | 84,677 | AUTHORITATIVE (crosswalk, DRAFT status by its own header) | 56 records E-01…E-51 (+splits); `r0_8`, `promotions`, `resolved_candidates`, `liveness_candidates`, `factory_candidates`, `ontology` |
| `invariant-r10/package-v2.6/evidence_state.json` | 29,688 | DERIVED (projection of the crosswalk for the factory kit) | `evidence-state@1`: 56 records, 5 promotions, 1 status (R0.8 OPEN, 5 open findings) |
| `invariant-r10/package-v2.6/10_MACHINE_READABLE_LEDGER.json` | 32,310 | AUTHORITATIVE (v2 claims P1…, C-1…) | 19 claims; P→S `semantic_map`; **19 float values** (`confidence`) |
| `invariant-r10/package-v2.6/INV_FRONTIER_R10_PRE.md` | 93 lines | AUTHORITATIVE prose (the four-column map) | mechanisms by substrate are **prose only** here |
| `invariant-r10/package-v2.6/12_R10PRE_SYNTHESIS.md`, `06_R10PRE_EXPERIMENTS.md`, `11_R10PRE_OPUS_HANDOFF.md`, `README.md` | — | AUTHORITATIVE prose / HISTORICAL for v1-provenance | current map, experiment status, reproduce lines |
| `invariant-r10/package-v2.6/witnesses/*` | — | AUTHORITATIVE witnesses (executed; TLA not run) | `adversarial_worlds.py` 19/19, `liveness_l1.py` 6/6, `liveness_l1_fair.py` 19/19, `L1Succession.tla` NOT RUN |
| `invariant-r10/experiments/*/RESULT.md` (9 dirs) | 535 MB tree incl. vendored artifacts | AUTHORITATIVE results; vendored trees are ARTIFACTS by identity | EXP-1…EXP-8, S6, EXP-6/6b, EXP-7 |
| `invariant-r10/px13/*` | 18.5 MB | RECEIPTS (hash-bound tarballs) | R0.8.3–R0.8.7 handbacks; `SHIPPED-SHA256SUMS.txt` |
| `invariant-r10/handoffs/*.md` (3) | 15 KB | ADVISORY (proposals to other lanes) | TRVM E-42/E-43, FAC-CONTROL-SENSITIVITY, SUPER E-50 |
| `invariant-r10/inputs-gpt-*.md` (4) + `package-v2.6/inputs/*.md` (5) | — | ADVISORY (GPT rulings) | the adjudications the crosswalk cites by section (`GPT v3 §1`) |
| `~/.invariant-factory/canonical.git:CLAIM_LEDGER.json` | 455,749 | AUTHORITATIVE | 208 claims; statuses PROVED 52 · DECLARED 71 · OPEN 46 · REFUTED 19 · KNOWN 7 · PROVISIONAL 7 · CONDITIONAL 3 · MEASURED 3 |
| `…:mosaic/{evidence,assumptions,arguments,sources,objectives,occupancy,operations,embodiment,factory}.json`, `mosaic/receipts/*.json` (20) | — | AUTHORITATIVE registries of the factory | evidence kinds, assumptions, arguments, cited results, round receipts |
| `TRVM/governance/invariant-grid.json` | 706,417 | AUTHORITATIVE | `law_registry.entries` 138 (citation form `law:<id>@<rev>`), status vocabulary of 8 |
| `TRVM/LAWS.md` | 10,356 | AUTHORITATIVE (Tier A) / RECONSTRUCTED (Tier B) / RESERVED | binding laws by number |
| `opensentience.org/_invariants/data/cells.json` | 64,772 | AUTHORITATIVE | 46 cells; `implementation_binding: cell:NN` from the ledger |
| `computedriven/docs/*.md` (7), `receipts/*` (39), git log | — | AUTHORITATIVE | mechanisms named in prose + code symbols; R0.x receipts |
| `super/README.md`, `release.json`, `and-super-rev-w233.receipt.json`, `ampd/lib/ampd/*.ex` (38 modules) | — | AUTHORITATIVE | ampd `world-meta@1`, effects, receipts |
| `WRL/wrl.js`, `relation-identity.js`, `relation-v2.js`, `spec.html`, `docs/spec/README.md`, `test/*` | — | AUTHORITATIVE | identity spine + §D6/§D8/§D9 drafts |
| `TRVM/governance/derive_protocol.mjs` (+ battery, worker, cas, certificate) | — | AUTHORITATIVE | TRVM-DERIVE-CORE-v1 (frozen; no `prim`) |

## 4. Live services and tools

| Item | Observed | Consequence |
|---|---|---|
| Graphonomous MCP (v0.4 engine, this machine) | `consolidate stats` → **0 nodes / 0 edges**; two `retrieve context` queries → 0 results, `routing: fast`, `abstention_signal: false`; 3 stale dev goals persist | no prior context to retrieve; an empty store reads as a confident miss (recorded as a v0.4 finding, not a G0 blocker) |
| Toolchain | node 25.2.1 · python 3.13.14 · Elixir/OTP 28 · sqlite 3.53.4 · rustc 1.94.1 · jq · rg | `dot` (Graphviz) MISSING · `zip` MISSING (use Python `zipfile`) · TLC/JVM MISSING |
| `/tmp` | 16 G tmpfs, 3 % used at snapshot | scratch here is fine today; it has been full before |

## 5. Known movement during the snapshot window

- The invariant lane (session `c33dcf12`) was active while this inventory was taken and copied the R0.8.7 handback into
  `invariant-r10/px13/` at 20:40Z; `invariant-r10` HEAD moved from `1426428` (START_HERE v4) to `699fbc2` during this session.
- `computedriven/` is at R0.8.7 (`21a1452`), eight commits past the `efa8881` the package vendored. G0 reads the package's
  pinned revision for package-derived facts and the live HEAD only for the "what is newer" diagnostic (G1).
- Rule (D-003): an adapter records the OID it read before it reads anything else.

## 6. Census results folded in (R7A / R7B, 2026-09-02; every count script-derived, scripts under `research/census/`)

| Source | Records | Resolution of references | Notes for adapters |
|---|---|---|---|
| crosswalk v2.6 (56 E-records) | ids `^E-\d{2}[abc]?$`, no gaps 1–51, no duplicates; 11 class tokens; 5 typed promotions, all 9 receipt sha256 MATCH at `699fbc2` | `witness_paths` 92/93 resolve (1 dangles: E-15 `EVIDENCE-nc17-19-23-AFTER-efa8881.txt`); `source_ids` 28/33 path-like resolve; `derivation_links` 20/61 are live ids, 4 name the retired `E-13`, the rest prose; 58 `§` citations to adjudications, no structured field; 0 line numbers; commits only in prose | roots: `invariant-r10/` 58 · computedriven 17 · package 10 · `super/` 4 · ProjectAmp2 2 · TRVM 1 |
| `evidence_state.json` v2.6 | 56 / 5 / 1 status / 3 artifacts; `executed` true 8, null 48; `conditions` on 3; `trust_profile` on 42; 80 receipt strings over 40 records | receipts 79/80 resolve (same dangling file); four `ampd/test effect (7)` entries resolve only because a directory exists; `governance/probe_worldalias_v02_repro.mjs` resolves against the live TRVM tree, never pinned | ADMISSIBLE by the factory kit at `699fbc2`; REFUSED (rule B, E-51 sha256) at `ba4e625` — receipts are pinned by relative path into a shared tree (Q-14) |
| research ledger v2.6 (19 claims) | `P1 P2 P3a P3b P4a P4b P5 C-1…C-7 X-1…X-4 D-1`; 15-token vocabulary; exactly two statuses moved since v1 (P5 SUPPORTED→TESTED, C-7 UNKNOWN→TESTED) | `semantic_map` still carries `C-7 → S6?` as origin | 19 floats (`confidence`) |
| factory ledger @ `d217ee2` (208 claims) | prefixes FAC 40 · FED 38 · MOS 29 · EMB 22 · ASR 19 · LED 17 · IMPACT 9 · TAX 6 · EVID 5 · ESC 4 · INC 3 · LINEAGE 3 · SUPPORT 3 · MEDIATION 3 · REPRO 2 · ADMISSION 2 · TERM/CONTROL/RECEIPT 1; 84 settled | `witnesses` **269/269** resolve in the ref's tree; `implementation_binding` 54/54 → 7 cells; typed provenance fields (`imported_from`, `readjudicated`, `evidence_qualifiers`, `assumption_refs`) | mentions the E-world **zero** times; `FAC-CONTROL-SENSITIVITY` NOT FOUND; the two registries meet only through 3 crosswalk records |
| `mosaic/*` | evidence kinds 11 · assumptions 29 (`ASM-*`) · arguments 27 (`ARG-*`) · sources 24 (`SRC-*`) · defeaters 68 · incidents 46 · receipts 20 | typed refs `{kind: witness|claim|source}` checked by `check-mosaic.mjs` | `receipt_version 4` receipts bind `parent.commit_oid` + tree-manifest sha256 |
| cells v0.8 (46) | `num` is a string `^\d{2}[ab]?$`; authored statuses missing 17 · sketched 9 · proved 8 · shipped 5 · named 4 · conditional 3 | cells carry no claim ids (reverse-only binding) | byte-identical between the site repo and the factory ref |
| computedriven `21a1452` | 88 commits R0.1→R0.8.7; 39 receipts (23 md / 8 JSON / 8 txt); 21 compile-fail gates; 10 NC scripts; 37 distinct F ids; 30 NC ids | markdown receipts: heading grammar `## F<n> — ` regular in `*-FALSIFIED.md`, no anchors; JSON receipts have no `id`/`schema` field; battery receipts are git-ignored (only in `lab/receipts-lab/` and the handback tarballs) | mechanism candidates = `pub` items in `cd-core/src/*.rs` (`LifecycleAdmission` L69, `reconstruct` L36, …) |
| super `c4160fd` | 26 commits; 44 modules / 17,926 lines (WEK measured 7,984 / 31 on 2026-08-27); 42 conformance vectors keyed by `name`; release receipt with 15 gate measurements | vectors: locator `/vectors/<i>`; receipts `rcpt-NNNN` per DETS store | worktree volatile; 2 unpushed commits |
| TRVM grid 1.69.0 | 138 entries / 107 ids / 106 canonical; PROPERTY-TESTED 126 · REGRESSION-LOCKED 6 · FALSIFIED 4 · PROVED 2; one id with no canonical revision (`kappa.carrier-preserving.monotonicity@2`) | `law:<id>@<rev>` resolves to exactly one entry (178 internal citations); `evidence` is prose | `E-1b…E-8` are exhibit labels, `S1/S2` session labels — namespace collisions with dataset A |
| GPT adjudications | 4 root inputs + 5 under `package-v2.6/inputs/` (two are the same blobs); `~/Downloads` copies byte-identical | sections `# <n>. <title> — <DISPOSITION>`; cited by number, never by anchor | ADVISORY |
