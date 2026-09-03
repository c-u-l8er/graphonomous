# R7B — Source census, dataset B (implementation-side registries)

**Census taken:** 2026-09-02, 15:40–15:55 −05:00, read-only, from `/home/travis/ProjectAmp2`.
**Purpose:** the source census for dataset B of the first Graphonomous G0 dataset — the
implementation registries that the invariant program's records (dataset A: `invariant-r10/package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json`, 56 records E-01…E-51) point at.
**Method:** every count below was computed by a script over the tree or over `git ls-files`; every
revision is a git OID read from the repo or a sha256 of the file. "NOT FOUND" is stated where a thing
the brief named does not exist.

Two facts about the census moment that a consumer must carry:

1. **`super/` was being edited by another session during the census.** `git status --porcelain`
   returned three entries at ~15:44 (`M ampd/lib/ampd/carrier/terminal.ex`, `M ampd/priv/data-elsewhere/world.json`,
   `?? ampd/lib/ampd/carrier/terminal.ex.orig`) and four *different* entries at 15:52:27
   (`M …/carrier/terminal.ex`, `M …/terminal_attachment.ex`, `M ampd/test/terminal_possession_test.exs`,
   `M ampd/tools/sabotage.sh`). The worktree is not a citable state; HEAD is.
2. **A battery was running in `computedriven/` during the census.** `lab/receipts-lab/` (git-ignored,
   root-owned) gained `BATTERY-20260902T200107Z.json` (20:01 UTC = 15:01 local, and newer files
   through 20:01:54Z) while this census ran. Tracked state was clean (`dirty=0`) throughout.

---

## 0. Summary table

| # | Source | Revision | Authority class | Records |
|---|---|---|---|---|
| B1 | `computedriven/` (own repo, no remote) | HEAD `21a1452eb6de183292e398872a4e83176566790b`, `master`, dirty 0 | AUTHORITATIVE (code, JSON receipts, falsification receipts); `receipts/STATUS.md` DERIVED | 88 commits · 39 receipt files · 7 model docs · 21 compile-fail gates · 10 NC scripts · 2 F falsifier scripts · 37 distinct F-ids, 30 NC-ids |
| B2 | `super/` (own repo since 2026-08-28) | HEAD `c4160fd0686163ea46f62dbefc9a26f8b6e9f9bf`, `main`, **2 ahead of `origin/main` = `7651697`**, dirty VOLATILE (3→4) | AUTHORITATIVE (ampd code, conformance corpus, release receipt); `docs/reviews/` ADVISORY | 26 commits · 44 `.ex` modules / 17,926 lines · 42 conformance vectors · 32 review briefs · release receipt with 15 gate measurements |
| B3 | `TRVM/` law registry + constitution | HEAD `fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873`, `merge/governance-plane`, dirty 0, in sync with origin | AUTHORITATIVE (grid registry, LAWS.md, ratification); handoff ADVISORY | 138 registry entries / 107 ids · 11 numbered laws (7 CANONICAL + 4 RESERVED) · 1 ratification · 1 inbound candidate-law handoff |
| B4 | `WEK_*` (8 files at container root) | container HEAD `90d254c013a688b84458130d785777d96d3f7a34`, `main`; per-file sha256 below | ADVISORY / DERIVED — **no WEK code exists** | 5 MAJOR + 9 MINOR + 3 QUESTION findings · 16 W-laws mapped · census of 22 measured + 10 judged figures |
| B5 | GPT-5.6 adjudication inputs | `invariant-r10` HEAD `699fbc2859efdaf57b2391d51dd7712b471e92b9`, `main`, dirty 0; sha256 per file | ADVISORY (external adjudicator; applied to dataset A by the lane's build scripts) | 4 root inputs + 5 in `package-v2.6/inputs/`; Downloads copies **byte-identical** |

---

## B1 — `computedriven/` (ComputeDriven Edge + Fabric, R0)

### Repository state

| Fact | Value |
|---|---|
| Path | `/home/travis/ProjectAmp2/computedriven` |
| HEAD / branch | `21a1452eb6de183292e398872a4e83176566790b` / `master` |
| Remote | none configured (`git remote -v` empty) |
| Dirty | 0 tracked entries; git-ignored generated state: `target/`, `lab/receipts-lab/` (600 entries: 142 `BATTERY-*.json`, 211 `R0.8-*.json`, 110 `legs-*` dirs, 55 R0.6, 42 R0.7, 36 R0.5), `lab/clab-*/`, `lab/cd-node-static` |
| Commits | 88, from `ec254a9` (2026-08-30T20:37Z, "R0.1-R0.4 + R0.4.1 semantic closure") to `21a1452` (2026-09-02T14:43−05:00, "R0.8.7 F36+F37 repair") |
| Vendored by the invariant package | `efa8881a5d44011c165b24276a17d07d6556c047` — "R0.8.3 round 4.1", 2026-08-31T20:26−05:00 (`experiments/vendor/computedriven@efa8881`, `git archive`) |
| Newer than the vendored commit | **26 commits** (R0.8.4 `cfde255`…`0b87256`; R0.8.5 `4e2dc54`…`af1cbc2`; R0.8.6 `479e007`, `afcb374`, `747f025`; R0.8.7 `fe883e9`, `21a1452`) |
| Toolchain pin | `rust-toolchain.toml` channel 1.75.0 (load-bearing: 1.94.1 SIGSEGVs cd-micro) |
| Workspace | `Cargo.toml` members `cd-core`, `cd-wire`, `cd-node`, `cd-lifecycle`, `cd-durable`; `cd-micro` deliberately outside the workspace |

Note the log carries two timestamp formats (`Z` for the Aug-30/31 morning commits, `−05:00` after) — a
consumer normalising dates must parse both.

### The R0.1 → R0.8.7 ladder (from `git log`, commit subjects)

| Round | Commits (first…last) | Receipt | Series |
|---|---|---|---|
| R0.1–R0.4, R0.4.1 | `ec254a9` | `receipts/R0.1.md`…`R0.4.1.md` | — |
| R0.4.2–R0.4.7 | `8dad113`…`c9cfee2`/`3eb9378` | `R0.4.2.md`…`R0.4.7.md` (each "bound to" a commit/tree) | guards |
| R0.5 | `abfb42d`…`cec0e22` (`cf550c1` receipts) | `R0.5.md`, two JSON, `R0.5-reproducibility.txt` | 30 PASS / 30 |
| R0.6A+B / R0.6 | `64a5caf` / `cf94403` | `R0.6AB.md`, `R0.6.md`, JSON, txt | 20/20 · 21/21 |
| R0.7 | `ae05f53`…`eb0643a` | `R0.7.md`, JSON, negative-controls.txt | 21 PASS + NC lines |
| R0.8 | `b516073`…`6bd73a9`; **falsified** `29d8298` | `R0.8.md`, `R0.8-FALSIFIED.md`, JSON | 21/21 then reopened |
| R0.8.2 | `5144d29`…`b2a3b77` (`8a7970a` receipts) | `R0.8.2-FINAL-*.json`, txt | 21/21 |
| R0.8.3 rounds 1–4.1 | `fcc71bc`, `ac218dd`, `d34eb29`, **`efa8881`** | `R0.8.3-FALSIFIED.md` (F1–F21) | 21/21 on the PX13 (`invariant-r10/px13/series.txt`) |
| R0.8.4 | falsify `cfde255` → repairs …`0b87256` | `R0.8.4-FALSIFIED.md` (F31, F23, F25, F22) | 21/21, 4 legs |
| R0.8.5 | falsify `4e2dc54` → `af1cbc2` | `R0.8.5-FALSIFIED.md` (F32, F33; F22/F24/F30/F34) | 21/21 |
| R0.8.6 | falsify `479e007` → `afcb374`, `747f025` | `R0.8.6-FALSIFIED.md` (F35) | 21/21, 7 legs |
| R0.8.7 | falsify `fe883e9` → `21a1452` | `R0.8.7-FALSIFIED.md` (F36, F37) | 21/21, 9 legs |

**What "21/21" is.** A *series* of 21 complete, independent executions of the whole battery from a
clean workspace, each producing a `BATTERY-<stamp>.json` whose `legs[]` all exit 0 and whose inner
`R0.8-<stamp>.json` reads `result: PASS`. At `efa8881` the unit was 3 legs (`guards`, `nc15`,
`run_r08`); at `21a1452` it is 9 legs (`guards`, `nc15`, `nc25`…`nc30`, `run_r08`). Since R0.8.5 a run
counts only if `tools/verify_battery.py` passes, which re-derives each leg's SUBJECT marker
(`"NC15 PASS"`, `"ALL GUARDS PASS"`, …) from the retained `legs-<stamp>/<leg>.log`. Battery receipts
are **git-ignored** — they exist only in `lab/receipts-lab/` on the machine and in the handback
tarballs (`invariant-r10/px13/COMPUTEDRIVEN_R08x_FOR_GPT.tar.gz`).

Shape of one battery receipt (`BATTERY-20260902T200107Z.json`, R0.8.7): `round`, `result`, `at_utc`,
`source{commit,tree,workspace_dirty_entries}`, `runner{image_tag,image_id,kernel,host,rustc,containerlab,sqlite3_cli,incarnation_anchor}`,
`legs[{leg,exit,log_sha256}]`, `inner_receipt{path,sha256,result}`.

### `docs/*.md` — the model documents (7 files, 8,972 words)

Every model doc is titled "written before the mechanism" and `receipts/STATUS.md` names two of them
canonical (`failure-model.md`, `durable-authority-model.md`). They use **round numbers and mechanism
names**, not S/E identifiers; only `durable-authority-model.md` uses F/NC numbers.

| Doc (blob @ HEAD) | Bytes/words | Identifiers used | Mechanisms named (backticked) |
|---|---|---|---|
| `admission-model.md` (`01c6d8ac`) | 4,580 / 627 | R0.4.1, R0.4.6, R0.4.7 | `LifecycleAdmission`, `LifecycleState`, `LifecycleHead`, `LocusAttachment`, `finalize_loss`, `recover_attachment`, `replay_lifecycle`, `audit_replay`, `reopen_after_closure`, `min_generation`, `WrongGeneration`, `WrongCarrier`, `CustodyMismatch` |
| `custody-model.md` (`268160ad`) | 5,379 / 693 | R0.4.2, R0.4.3, R0.4.5–R0.4.7 | `ForeignProvenance`, `MixedProvenance`, `CarrierCustody`, `LifecycleAdmission`, `FinalityWarden`, `WorldRoot`, `LocusRoot`, `LocusId`, `VacantLocus::genesis`, `genesis_with_warden`, `replay_lifecycle` |
| `durable-authority-model.md` (`c4cbc090`) | 32,995 / 5,039 | **F12, F14, F15, F16, F17, F19, F20, F21; NC1, NC8, NC15–NC23; G2**; R0.4–R0.8.3 | `CanonicalMutation::begin`, `Root::set_pending`, `Root::finalize`, `request_ledger`, `request_id`, `controller_epoch`, `already_applied`, `expectation_met`, `chain_checksum`, `pending_head`, `durable_revision`, `RecoveredSemanticState`, `SuccessionError`, `lab/scripts/nc15_repeated_crash.sh`, `lab/scripts/nc17_live_store_tamper.sh`, `tools/store_read_gate.sh` |
| `failure-model.md` (`6a35973a`) | 5,734 / 844 | NC1; R0.4.2, R0.7 | `LossBasis` (`::FencingEpoch`, `::PhysicalDecommission`), `FinalityWarden`, `FencingEpoch`, `DecommissionAttestation`, `LifecycleEvent`, `LocusId`/`NodeId`/`WorkerId`, `replay_lifecycle` |
| `freshness-model.md` (`3025e550`) | 3,327 / 475 | R0.4.5–R0.4.7 | `LifecycleAdmission`, `replay_lifecycle`, `audit_replay`, `create_locus` |
| `identity-layers.md` (`9abd9810`) | 4,638 / 622 | R0.4, R0.6, R0.6B, R0.6C, R0.7 | `LocusId`, `WorkerId`, `CarrierId`, `NodeId`, `recv_from`, `hello_once` |
| `linearity-model.md` (`85b0315a`) | 5,253 / 672 | R0.4.1–R0.4.7 | `PartialEq` (removed), `no_std`, `create_locus` |

No doc mentions `S1`…`S5` in the semantic-obligation sense, and no file in the repository mentions any
`E-xx` (0 hits over 142 tracked files). The mapping from these docs to S/E ids lives entirely in
dataset A (`CROSS_REGISTRY_CLAIM_MAP.json`: `source_registry: cd-core-docs` 11 records, `cd-durable-docs` 7).

### `receipts/` — 39 files

23 markdown, 8 JSON, 8 text. Sizes and blob OIDs are in `R7B_census.json`; the salient facts:

| Receipt (kind) | Bytes | Headings / identifiers |
|---|---|---|
| `R0.1.md` … `R0.4.md`, `R0.4.1.md`…`R0.4.7.md` | 1.7–6.2 KB | "Receipt R0.x — …", "## Provenance", "## Falsifiers …"; `R0.4.1.md` names F1–F6 (the *early* F namespace: six required negatives); `R0.4.3.md`/`R0.4.7.md` cite F2, F3, F5, F6 |
| `R0.5.md`, `R0.5-preflight.md`, `R0.5-pre-execution.md` | 15.9 / 4.5 / 1.8 KB | 30-run series; "## Eight R0.5.x repairs" |
| `R0.6.md`, `R0.6AB.md`, `R0.7.md` | 9.2 / 9.2 / 16.3 KB | `R0.7.md` names NC1, NC2 |
| `R0.8.md` | 12.2 KB | NC1–NC8; contains the R0.8.2 closure section |
| `R0.8-FALSIFIED.md` | 5.3 KB | "Attack 1/2 [CONFIRMED]", NC1–NC3, NC6–NC8 |
| `R0.8.3-FALSIFIED.md` | **40.0 KB, 881 lines** | one `##`/`###` heading per falsifier **F1–F21**, plus NC1, NC4, NC7, NC9, NC12, NC15–NC23, G1, G2 |
| `R0.8.4-FALSIFIED.md` | 6.8 KB | `## F31 — PRIORITY ZERO…`, `## F23`, `## F25`, `## F22`; mentions F15, F17, F24, NC6 |
| `R0.8.5-FALSIFIED.md` | 5.6 KB | `## F32 …`, `## F33 …`; F22–F25, F29, F30, F34; NC24, NC25 |
| `R0.8.6-FALSIFIED.md` | 3.9 KB | `## F35 …`, `### Why NC26 could not see this`; F22, F24, F30, F32–F34 |
| `R0.8.7-FALSIFIED.md` | 5.0 KB | `## F36 …`, `## F37 …`; F19, F35 |
| `STATUS.md` | 17.7 KB | "regenerated R0.4.7 round; supersedes prior STATUS" — **DERIVED** |
| `*-FINAL-<stamp>.json` (R0.5, R0.6AB, R0.6, R0.7, R0.8, R0.8.2) + `R0.5-<stamp>.json` | 7.6–54.4 KB | machine receipts, see below |
| `*-reproducibility.txt` (R0.5, R0.6AB, R0.6, R0.7, R0.8, R0.8.2), `R0.7-negative-controls.txt` | 1.7–3.3 KB | one line per run: `commit`, `tree`, `PASS`/`FAIL` |

JSON receipt shape (`R0.8.2-FINAL-20260831T225009Z.json`, blob `f796896a`): top-level keys
`experiment, started_utc, finished_utc, doctrine, scope_limits[7], environment{host,kernel,wireguard_kmod,containerlab,docker,sqlite}, source{commit,tree,source_workspace_clean,topology_sha256}, artifacts{cd_node_static_sha256,cd_durable_sha256,lab_image_id,frr_configured,frr_daemon_digest}, frozen_core_continuity[2], identity{…}, durable_observations[12], negative_controls[39], controller[34], forwarding_plane[2], fault_sequence[9], phases[4], snapshots, unmet_expectations[0], result`.
Every gate row has the same `{point|control|phase, expected, got, detail?, at_utc}` shape; negative
controls are named in lower snake case (`nc5_partition_changed_nothing`). The earlier R0.5/R0.6 receipts
have fewer sections (no `doctrine`, `negative_controls`, `controller`). There is **no schema/version
field** — `experiment` is a prose string.

### `lab/`, `tools/`, and the crates

| Set | Files |
|---|---|
| `lab/falsifiers/` (F control scripts) | `F22_tmp_symlink.sh`, `F25_vacuous_r08g.sh` |
| `lab/scripts/` NC controls | `nc15_repeated_crash.sh`, `nc17_live_store_tamper.sh`, `nc24_root_clone.sh`, `nc25_schema_contract.sh`, `nc26_stale_root_resurrection.sh`, `nc27_genesis_schema_contract.sh`, `nc28_foreign_successor.sh`, `nc29_foreign_pending_import.sh`, `nc30_anchor_reservation_window.sh` |
| `lab/scripts/` runners | `run_experiment.sh` (R0.5), `run_r06.sh`, `run_r07.sh`, `run_r08.sh` (43.8 KB), `faults.sh`, `faults_r07.sh`, `wg_overlay.sh`, `wg_overlay_r07.sh`, `lab_env.sh` |
| `tools/` gates | `guards.sh` (must print ALL GUARDS PASS), `verify_battery.py`, `store_read_gate.sh`, `doc_consistency.sh`, `schema_coverage.sh`, `unbound_check.py`, `provenance.sh`, `demo_r04.sh` |
| `tools/compile-fail/` (21) | `f1_forge_{attach_record,custody,detach_receipt,loss_finalization,warden}.rs`, `f3_reuse_vacancy`, `f7_locusid_mints_nothing`, `f8_reconstitute_removed`, `f9_custody_reuse`, `f10_custody_mint_removed`, `f12_live_and_recoverable`, `f13_suspend_consumes_live`, `f14_recover_from_slice`, `f15_admission_reuse`, `f16_forge_admission`, `f17_transition_without_admission`, `f18_state_is_not_admission`, `f19_reopen_removed`, `f20_append_removed`, `f21_no_reachability_lossbasis`, `f22_lifecycle_event_has_no_route` |

**Namespace warning:** the compile-fail `f<N>` numbers are the R0.4.x *semantic* falsifier series
(f15 = admission reuse, f17 = transition without admission). The `F<N>` headings in
`R0.8.3-FALSIFIED.md` and later are the R0.8.x *durable-authority* series (F15 = live store edit
laundered into the root, F17 = derived cache column as transition input). Same digits, different
claims. Dataset A's F31–F37 are the R0.8.x series.

Crate sources: `cd-core/src/{authority,guards,id,lib,locus}.rs`; `cd-node/src/{lib,main}.rs` +
`tests/{authority_vs_reachability,exchange,partition_finality,provenance_leakage}.rs`;
`cd-durable/src/main.rs` (4,903 lines), `cd-durable/src/bin/cd-tamper.rs`, `cd-durable/SCHEMA_CLASSIFICATION.md`;
`cd-lifecycle/src/main.rs` (1,046 lines); `cd-wire/src/lib.rs` + `tests/golden.rs`; `cd-micro/src/main.rs` + `link.ld`.

**Mechanism candidates (public items in `cd-core/src/*.rs` at `21a1452`):**

| File (blob) | `pub` items |
|---|---|
| `authority.rs` (`abba3576`, 619 lines) | enum `Evidence`, struct `Authority`, fn `reconstruct` (L36), enum `LifecycleEvent`, enum `SuccessionViolation`, struct `SuccessionError`, struct `LifecycleState`, fn `replay_lifecycle` (L176), fn `audit_replay` (L187), fn `recover_attachment` (L199) |
| `locus.rs` (`b69b62f0`, 443 lines) | type `Mark`, structs `WorldRoot`, `LocusRoot`, `VacantLocus`, `LocusAttachment`, `CarrierCustody`, `LifecycleAdmission` (L69), `AttachRecord`, `DetachReceipt`, `LossFinalization`, `FinalityWarden`; enum `LossBasis`; fns `begin` (L140), `attach` (L216), `suspend` (L255), `detach` (L267), `finalize_loss` (L328); impl blocks for each struct |
| `id.rs` (`09b40d41`) | structs `NodeId`, `WorkerId`, `LocusId`, `CarrierId`; const `LEN` |
| `guards.rs` (`0bf7830b`) | consts `MICRO_TOTAL_RAM_MAX`, `MICRO_STATIC_ARENA_MAX`, `MICRO_STACK_RESERVE_MIN`, `MICRO_HEADROOM_MIN`, `WIRE_FRAME_MAX` |

`cd-durable/src/main.rs` (blob `982d08b5`) is where F31–F37 land: `mod root` with struct `Root`
(`open`, `set_pending`, `finalize`, `adopt`, `adopt_genesis_head`, `reconcile_anchor`, `acknowledge`,
`persist`), struct `Lineage` (`read_lineage`, `write_lineage`), enum `PendingOrigin` (F36: Original vs
Replay), struct `PendingRec`, fns `canonical_head`, `verify_schema_contract`, `expected_schema`,
`write_atomic`, `anchor_lock_path`, const `DEFAULT_ANCHOR_DIR`, const `SCHEMA`.

### Identifier → files index (computedriven tracked files only, 142 files)

70 distinct identifiers matched `F\d+ | NC\d+ | S[1-5] | E-\d+ | G\d+`. Requested subset:

| Id | Total | Files | Where (count) |
|---|---|---|---|
| F31 | 9 | 4 | `receipts/R0.8.4-FALSIFIED.md`(4), `lab/scripts/nc24_root_clone.sh`(2), `lab/scripts/run_r08.sh`(2), `cd-durable/src/main.rs`(1) |
| F32 | 21 | 8 | `cd-durable/src/main.rs`(7), `receipts/R0.8.6-FALSIFIED.md`(4), `nc15_repeated_crash.sh`(3), `nc26_…`(2), `R0.8.5-FALSIFIED.md`(2), `nc17`, `nc25`, `run_r08` |
| F35 | 18 | 6 | `cd-durable/src/main.rs`(7), `R0.8.7-FALSIFIED.md`(4), `nc28_foreign_successor.sh`(2), `nc29_…`(2), `R0.8.6-FALSIFIED.md`(2), `tools/verify_battery.py`(1) |
| F36 | 12 | 4 | `cd-durable/src/main.rs`(6), `R0.8.7-FALSIFIED.md`(3), `nc29_foreign_pending_import.sh`(2), `nc15_repeated_crash.sh`(1) |
| F37 | 9 | 3 | `cd-durable/src/main.rs`(6), `nc30_anchor_reservation_window.sh`(2), `R0.8.7-FALSIFIED.md`(1) |
| NC15 | 12 | 5 | `R0.8.3-FALSIFIED.md`(5), `nc15_repeated_crash.sh`(3), `cd-durable/src/main.rs`(2), `docs/durable-authority-model.md`(1), `verify_battery.py`(1) |
| NC24 | 9 | 4 | `nc24_root_clone.sh`(4), `nc26_…`(2), `R0.8.5-FALSIFIED.md`(2), `run_r08.sh`(1) |
| NC25 | 6 | 4 | `nc25_schema_contract.sh`(3), `cd-durable/src/main.rs`, `R0.8.5-FALSIFIED.md`, `verify_battery.py` |
| NC26 | 9 | 4 | `nc26_stale_root_resurrection.sh`(4), `R0.8.6-FALSIFIED.md`(3), `nc28`, `verify_battery.py` |
| NC27 | 4 | 2 | `nc27_genesis_schema_contract.sh`(3), `verify_battery.py`(1) |
| NC28 | 6 | 3 | `nc28_foreign_successor.sh`(4), `nc29`(1), `verify_battery.py`(1) |
| NC29 | 5 | 2 | `nc29_foreign_pending_import.sh`(4), `verify_battery.py`(1) |
| NC30 | 5 | 2 | `nc30_anchor_reservation_window.sh`(4), `verify_battery.py`(1) |
| S1 | 6 | 2 | `nc28_foreign_successor.sh`(3), `R0.8.6-FALSIFIED.md`(3) — **not the semantic obligation**: here `S1`/`R1` are store/root copy labels |
| S2–S5, E-xx | 0 | 0 | absent from the repository |

Highest-frequency ids in computedriven: F17 (24 in 7 files), F32 (21/8), F15 (18/7), F35 (18/6),
NC1 (18/11), F16 (16/6), NC17 (15/5), NC19 (12/7), F36 (12/4), F19 (12/5), NC15 (12/5), NC18 (11/6),
F23 (11/4), F14 (11/4), NC6 (11/7), NC7 (11/6), F1 (10/7). Full per-file counts:
`gpr0/cd_ident_index.json`.

### Linkability (B1)

- **Deterministic today:** `commit` + `path` + blob OID (table in `R7B_census.json`); JSON receipts
  by JSON Pointer (`/negative_controls/0/control`, `/source/commit`, `/result`); battery receipts by
  `legs[i].log_sha256` and `inner_receipt.sha256`; the commit-subject grammar
  `^R0\.\d(\.\d)?( round \d(\.\d)?)?:? (F\d+|NC\d+|F\d+\+F\d+|F\d+/F\d+/F\d+)` recovers the F/NC → commit map
  (e.g. `afcb374` "R0.8.6 F35 repair", `21a1452` "R0.8.7 F36+F37 repair", `cfde255` "R0.8.4 falsification").
- **Markdown receipts have no stable anchors.** The only locator is heading text; it is regular in the
  `*-FALSIFIED.md` files (`^##+ F(\d+) — ` for F1…F37) and irregular elsewhere. Line numbers change
  when the file is appended (R0.8.3-FALSIFIED grew across four rounds; R0.8.md gained an R0.8.2 section).
- **Missing:** a record id or schema field in JSON receipts; a stable `id` per markdown falsifier; any
  S/E vocabulary (that mapping is dataset A's); and battery receipts are not in git — link them via the
  handback tarball sha256 in `invariant-r10/px13/SHIPPED-SHA256SUMS.txt`.

---

## B2 — `super/` ([&] Super, `ampd` authority runtime)

### Repository state

| Fact | Value |
|---|---|
| Path | `/home/travis/ProjectAmp2/super` |
| HEAD / branch | `c4160fd0686163ea46f62dbefc9a26f8b6e9f9bf` / `main` |
| Remote | `origin git@github.com:c-u-l8er/super.git`; `origin/main` = `76516978bfa84057d179c0dbdc8a323f512a828b`; HEAD is **2 commits ahead, unpushed** (`e5eb567`, `c4160fd`) |
| History | 26 commits; first `8074db7` 2026-08-28T13:49−05:00 "[&] Super becomes its own repo, at rev W.2.3.3"; tag `d13a-frozen` at `b7132a8` (2026-08-30) |
| Dirty | VOLATILE — 3 entries then 4 different entries within ten minutes (see preamble) |
| Vendored by the invariant package | `7651697` (= `origin/main`, 2026-09-02T12:03−05:00, "Answers that are the wrong shape, records that describe another attachment, and two gates that could not have failed") — `git archive 7651697 ampd`, 84 files, `experiments/s5_effect_adapter/vendor_ampd.SHA256SUMS`; also cited by `experiments/authority_merge/vendor/PROVENANCE.txt` |
| `release.json` (blob `59ef564e`) | `{"revision":"W.2.3.3","product":"Super (CD)"}` |
| `README.md` (blob `2c2dbd52`, 45,453 B) | "# [&] Super — Rev W.2.3.3 bundle"; sections: Layout · What's in here · The light · Release pipeline (truth gates) · The host gates are in the pipeline now · The browser battery must run the browser's source · The counts, and the tool that derives them · The bracket around the harnesses that write to the source tree · The gate release.sh did not run, until it shipped a bad release · The measurement must describe the bytes the receipt binds · Honesty notes |

### Release receipt `and-super-rev-w233.receipt.json` (blob `d698daba`, 4,663 B)

Top-level keys: `schema` (`release-receipt@3`), `revision` (`W.2.3.3`), `artifact` (`and-super-rev-w233.zip`),
`sha256` (`48873054d779…6e56`), `bytes` (1,668,056), `files` (153), `release_content_sha256`
(`8b5e9e4e…91ca`), `artifact_replay{scope:"matched", content:"byte-identical"}`, `measurements` (15
gates), `note`. Measurements: source_text_assets 150 · proof_literals 14 · browser_assertions 188 ·
bot_falsifiers 40 · guard_falsifiers 6 · scope_falsifiers 9 · count_refusals 5 · **conformance_vectors 42**
· beam_tests 220 · host_acceptance 78 · cockpit_assertions 72 · big_frame 8 · maintenance 8 ·
intent_surface 5 · webview_acl 18 — each `{value, gate, noun, reported, prose(regex), failures?}`.
It is **content-bound** (it commits to the zip's sha256 and the release-content hash) but **named by
revision**, not by hash; and, as its own `note` says, "the archive cannot contain its own hash".

### `conformance/` — the frozen vector corpus

One file, `authority-vectors.json` (blob `64ec2eed`, 22,678 B): `schema: authority-vectors@1`,
`source: "frozen JS simulator (app-prototype.html)"`, `generated_at: 2026-08-27T18:21:58Z`, `params`,
`digest_env` (12 fields), `effect_env` (5), `snap_list[2]`, **`vectors[42]`**. A vector is
`{name, steps: [[op, args…]…], expect: {…}}`; example `vectors[0]`:
`{"name":"install grants nothing","steps":[["install_pack","postgres"],["auth",{"cap":"postgres.schema.read","resource":"db-main"}]],"expect":{"allow":false,"reason":"authority-missing"}}`.
`expect.allow`: false 22 · true 2 · absent 18 (those assert receipts/snapshots/digests instead).
`expect.reason` vocabulary: `authority-missing`(5), `actor-mismatch`, `scope-mismatch`,
`workspace-mismatch`, `run-expired`, `denied-by-default|destructive`, `capability-undeclared`,
`pack-not-installed`, `request-missing`, `placement-denied`. Step ops: auth 26, commit 21, draft 19,
exercise 15, snap 12, mint 11, revoke_domain 7, forge_pr_create 6, approve_last 5, … Vectors have
**no numeric id** — the key is the `name` string; the deterministic locator is `/vectors/<index>`.
`Ampd.Conformance` (`lib/ampd/conformance.ex`, 123 lines) is "the C0 conformance interface — not a
product execution path"; `test/conformance_test.exs` + `test/fixtures/vectors.exs` run them on the BEAM.

### `ampd/lib/ampd/` — 44 modules, 17,926 lines (26 test files)

| Module (file) | Lines | `@moduledoc` first line |
|---|---|---|
| `Ampd` (`ampd.ex`) | 68 | ampd — the [&] Super authority runtime (C1). |
| `Ampd.Authority` (`authority.ex`, blob `fc218cf2`) | 517 | The linearized authority API — the only supported way to change what may… |
| `Ampd.AuthorityCoordinator` | 461 | The linearization point for authority. |
| `Ampd.Effects` (`effects.ex`, blob `a7892ca8`) | 288 | The durable effect journal — `effect-request@1` and `effect-attempt@1`. (state machine PROPOSED → AUTHORIZED → APPROVED → CLAIMED → ATTEMPTED → COMMITTED | FAILED | UNKNOWN → RECONCILE) |
| `Ampd.Receipts` (`receipts.ex`, blob `c087c07c`) | 73 | "The durable effect ledger — feeds Evidence; never a second audit system." |
| `Ampd.World` (`world.ex`, blob `0ae87ea2`) | 470 | `world-meta@1` — the durable proof that this machine's world was… |
| `Ampd.Locus` (`locus.ex`, blob `9b8375bc`) | 804 | Where a Lane becomes a Locus: the establishment of typed authority over… |
| `Ampd.GrantRegistry` (`grant_registry.ex`, blob `ecc3c24a`) | 481 | "What may be exercised: grant objects binding actor+capability+resource+duration." |
| `Ampd.Gateway` (blob `cbb9a396`) | 407 | The one door. No path reaches an adapter except through here: |
| `Ampd.Core` (blob `06529b19`) | 263 | Pure parity core. Every function here mirrors the frozen JS simulator |
| `Ampd.Store` (blob `69224fb7`) | 132 | Truth-preserving recovery. Every authority-bearing registry writes its… |
| `Ampd.Approvals` | 94 | "Which exact effects await consent — approvals bound to intent digests." |
| `Ampd.CapabilityRegistry` | 144 | "What exists: installed packs, versions, declared surfaces, policies." |
| `Ampd.Carrier` / `.Floor` / `.Machine` / `.Reaper` / `.Terminal` | 900 / 360 / 885 / 197 / 933 | D.1.3b·2 carrier attachment; `carrier-confinement-floor@1`; what starts/stops a Carrier; reaper; D.1.3c·2b attach-answer grammar |
| `Ampd.CommandSpec` | 675 | `command-spec@1` — **what may be said**, declared once. |
| `Ampd.Control` | 742 | The command surface, and the two laws that decide what a command means. |
| `Ampd.Peer` | 1,164 | `peer@1` — who is on the other end of a channel, decided by the runtime. |
| `Ampd.Worker` | 628 | `worker@1` and `carrier-attachment@1` |
| `Ampd.Worktree` / `.EffectChannel` / `.Effector` | 603 / 856 / 689 | the trusted host edge; the host effect reached by possessing a descriptor; the one place ampd runs a program |
| others | — | `Application`(no moduledoc), `Bootstrap`, `Bridge`, `Conformance`, `Embodiment`, `Frame`, `Loci`, `NativeFd`, `Ordered`, `Projection`, `Refusal`, `RefusalLog`, `Session`, `Subscriptions`, `TerminalAttachment`, `TestFixture`, `Transport`, `ViewClock`, `Wire` |

**Are Super's receipts content-addressed? No — the keys are, the records are not.**
`Ampd.Receipts.emit/1` mints `id = "rcpt-" <> pad(seq, 4)` (kind `capability-effect-receipt@1`) into
the DETS store `receipts`; `Ampd.Effects` mints `ef_NNNN` with attempt suffix `-aN`. What *is*
content-derived: the idempotency/effect key `Ampd.Core.intent_digest/1` = `"sha256:" <> sha256(canon(env))`
(`core.ex:50`), `pack_digest/1`, `Ampd.Locus.profile_digest/0`, and `Ampd.World.incarnation_of/1` =
sha256(`installation_id/generation`) truncated to 16 bytes (`world.ex:305`). The release receipt binds
the artifact by sha256. So a Graphonomous adapter can address an *intent* by digest but must address a
*receipt row* by `(store, seq id)`.

### `docs/reviews/` — 32 briefs, ADVISORY

`C1_0B`, `C1_0B1`, `C1_1_0`, `C1_1_1`, `C1_1_2`, `C1_1_8_1`, `C1_1_8_2`, `C1_1_8_2_1`…`_5`, `C1_1B`, `C1_1C`,
`C1_1`, `W_1`, `W_1_1`…`W_1_4_3`, `W_2`, `W_2_1`, `W_2_2`, `W_2_3`, `W_2_3_1`, `W_2_3_2`, `W_2_3_3`
(`*_REVIEW_BRIEF.md`, 7.9–39.1 KB, 2026-08-20 → 08-27). Two more advisory documents at the root:
`MOTOR_MACHINE_RESEARCH_BRIEF_FOR_OPUS.md`, `W_2_2_ADDENDUM_AFTER_PACKAGING.md`.

### Which invariant records reference Super

- `CROSS_REGISTRY_CLAIM_MAP.json` `source_registry: ampd-readme` — 5 records (e.g. **E-17** "journal
  before act; UNKNOWN terminal-until-reconciled", `source_ids: ["ampd/README.md Effect atomicity"]`,
  `witness_paths: ["ampd/test effect (7)"]`, class `in_tree`).
- **E-48** (S5 TESTED once under the stated profile), **E-50a / E-50b** (FALSIFIED-KEPT-RED, candidates
  for the Super lane), **E-51** (EXHAUSTIVE-IN-MODEL effect-identity model) — all from EXP-6 against
  `ampd @ super 7651697` (`trust_profile` field in `evidence_state.json`), receipts under
  `invariant-r10/experiments/s5_effect_adapter/receipts*/`, handoff `handoffs/SUPER_E50_EFFECT_IDENTITY.md`
  (blob `1a673866`). The handoff proposes `Ampd.Effects.claim/1` refusals `effect-key-unresolved` /
  `effect-key-satisfied`, a `SUPERSEDED` attempt terminal, and a `REPLAY_RISK_AUTHORIZED` fact.
- EXP-5 (authority merge) used `Ampd.Core.snapshot_of` from the compiled beam at the same commit.
- The WEK census baseline measures ampd (`G_0` 19 commands via `Ampd.CommandSpec`, `S_0` 6 stores via
  `Ampd.World.authority_stores/0`, `L_0` 7,984 lines / 31 modules on 2026-08-27). The tree now has 44
  modules / 17,926 lines — the baseline is dated, as its gate intends.

**Namespace warning:** `ampd/test/locus_test.exs` uses its own `F1`…`F17` (e.g. "F17 · the profile
basis is recoverable, not just a hash"), unrelated to computedriven's F-series.

### Linkability (B2)

Deterministic: commit + path + blob; `/vectors/<i>` in the corpus; `measurements.<gate>.value` in the
release receipt; module + function (`Ampd.Effects.claim/1`) via `grep -n "def claim"` at a commit.
Missing: vectors have no id field; receipts/effects are sequence-numbered per DETS store (not portable
across installations); the worktree is live, so nothing may be cited from it; and the two unpushed
commits are not yet visible at the remote.

---

## B3 — TRVM law registry, constitution, and the inbound handoff

### Repository state

| Fact | Value |
|---|---|
| Path | `/home/travis/ProjectAmp2/TRVM` |
| HEAD / branch | `fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873` / `merge/governance-plane` (2026-08-28T13:26−05:00, "Governance rounds 16 to 18") |
| Remote | `origin git@github.com:c-u-l8er/TRVM.git`; `origin/merge/governance-plane` = `fd0df4c` (in sync) |
| Dirty | 0 |
| `governance/invariant-grid.json` | worktree **identical** to committed: `git diff --stat` empty; sha256 `ffc293accb3abca335c89aad4e19d143a4bee5dac94a27d67bc456529bba8940` both; blob `9739bcc64bb3a23a19c9d5e6ed8e4af77d23bf7f`, 706,417 B. (The brief warned it may differ; at census time it did not.) |

### `invariant-grid.json`

`record: "invariant-grid"`, `version: "1.69.0"`, `date: "2026-08-18"` (the `date` field lags the
commit that last changed the file by ten days — a stale-field hazard), 118 top-level keys
(`changelog_from_*` × 60+, `law_registry`, `status_vocabulary`, `defect_class_vocabulary`, `hash_policy`,
`artifact_roots`, `artifact_versions`, `schemas`, `meta_laws`, `kernel_evidence`, `world`, …).

**`law_registry`** = `{note, grid_version: "1.69.0", entries[138]}`. Field presence over 138 entries:
`id`, `revision`, `status`, `canonical`, `statement`, `evidence` (138 each); `superseded_by` 25;
`revision_note` 26; `supersedes` 24; `defect_class` / `accepted_false_verdict` /
`underlying_observations_genuine` 15; `grid_law_id` 1 (`kappa_S.add-internal-edge.fixed-SCC-support.monotonicity`).

| status | canonical=true | canonical=false | total |
|---|---|---|---|
| PROPERTY-TESTED | 97 | 29 | 126 |
| REGRESSION-LOCKED | 5 | 1 | 6 |
| FALSIFIED | 3 | 1 | 4 |
| PROVED | 1 | 1 | 2 |
| **total** | **106** | **32** | **138** |

107 distinct ids; 12 ids carry more than one revision (`derivation.instantiation-identity` 1–6,
`derivation.emission-conformance` 1–6, `derivation.lowering-refinement` 1–5, `derivation.canonical-lowering` 1–4,
`derivation.implementation-provenance` 1–4, `film.native-emission` 1–4, `film.evidence-chain` 3–5,
`derivation.serialized-boundary` 1–3, `digest.adequacy`, `sched.certificate`, `grid.consistency`,
`kernel.identity` 1–2). Exactly one id has **no canonical revision** — `kappa.carrier-preserving.monotonicity@2`
(PROVED, superseded by `kappa.internal-edge.monotonicity@4`). No id has two canonical revisions; no
canonical entry carries `superseded_by`. Revision distribution: 1×104, 2×12, 3×8, 4×8, 5×4, 6×2.

- **Id grammar:** `^[a-z]+(\.[a-z0-9-]+)+$` — all 138 match. Prefix families: `kappa.`, `sched.`,
  `plane.`, `collapse.`, `deriv.`, `film.`, `digest.`, `grid.`, `cert.`, `state.`, `kernel.`, `refine.`,
  `world.`, `warrant.`, `footprint.`, `maintenance.`, `evidence.`, `derivation.`, `proof.` (the largest:
  `proof.bounded-claim` … `proof.mount-is-a-private-object`).
- **Citation form:** `law:<id>@<rev>` — the registry note calls it "the load-bearing reference
  everywhere (kernel, kappa witnesses, this grid, scheduler certificate, ledgers)"; `grid_check` v2
  fails the build on unknown ids/revisions or citations of non-canonical entries outside
  superseded/history context. 178 such citations occur inside the grid itself (most-cited:
  `law:state.semantic-quotient@1` 7, `law:film.terminal-witness@1` 7, `law:sched.free.float@1` 6).
  Lineage fields use bare `<id>@<rev>`.
- **`status_vocabulary`** (8): `PROVED`, `PROPERTY-TESTED`, `REGRESSION-LOCKED`, `MODEL-CHECKED-FRAGMENT`,
  `EMPIRICAL`, `OPEN`, `NOT_APPLICABLE`, `FALSIFIED` — four are used in the registry.
- **`defect_class_vocabulary`** (4): `authority-forgery`, `provenance-shape`, `instrument-vacuity`,
  `record-staleness` — used 2 / 1 / 0 / 12 times; every use is on a `derivation.*` entry and carries
  `accepted_false_verdict` (true on 3) and `underlying_observations_genuine`.
- **`hash_policy`:** `ArtifactHash256` = full SHA-256, never truncated ("films, sem ids, commitments,
  certificates, receipts"); `FastDigest64` = tables/debugging only, must never flow into an evidence path.
- **`artifact_roots`:** every governance executable resolves its artifact reads from its own module
  location (`import.meta.url`), overridable by `TRVM_GOV_ROOT`; `artifacts.json` (blob `ae16634b`)
  declares the case-input set once; `grid_check` refuses any governance artifact PRESENT but
  UNDECLARED; every `probe_*.mjs` must declare what it witnesses.
- **`evidence` is free text** (66–6,147 chars per entry; e.g. entry 0: "C1: 24,576 edge-additions at
  n=4, kappa decreased in 168; first witness graph#223 …"). `statement` runs 63–18,830 chars.

### `LAWS.md` and `LAW_RATIFICATION_2026-07-22.md`

| File | Size / blob / sha256 | Last commit |
|---|---|---|
| `LAWS.md` | 10,356 B, 200 lines, 1,467 words / blob `b1c6e1da…` / `02a51a87…fb9c` | `f30e88a6` 2026-07-23 |
| `LAW_RATIFICATION_2026-07-22.md` | 3,910 B, 141 lines, 560 words / blob `d87a6650…` / `01088a04…7e05` | `f30e88a6` 2026-07-23 |
| `tools/laws_check.py` | 13,391 B, 318 lines / blob `d35f8456…` | — |

`LAWS.md` is "the single index of TRVM's governance laws … two tiers plus a reserved state":
**Tier A — CANONICAL** (real cited source text OR architect ratification), **Tier B — RECONSTRUCTED
(NEEDS RATIFICATION)**, **RESERVED — canonical statement lost**. Provenance rule: B→A promotion is a
human act; never backfill canonical text from an agent's paraphrase.

| Series | Law | Tier | Provenance |
|---|---|---|---|
| I Binding (semantics) | 1, 2, 3, 7 | RESERVED | attested only via "1–7 unchanged" (`forge/FORGE_BINDING_RESULTS.md:1562`) |
| I | 4 | CANONICAL | ratified 2026-07-22 (reduction cost must name its strategy); witnesses `forge/binding_run3.py:177`, `3b.py:265`, `3c.py:307` |
| I | 5 | CANONICAL | attested text |
| I | 6 | CANONICAL, now GLOBAL | ratified 2026-07-22 (observable must carry every future-determining state variable); witnesses `binding_run3k.py:32,313,325`, `3h.py:21,285` |
| II Distribution (epistemics) | 10 | CANONICAL | `research/synth_async.py:8` |
| II | 13 | CANONICAL | `FINDINGS.md:341,371-373` |
| II | 23 | CANONICAL | ratified 2026-07-22 (memoization key must range over every dimension); witness `TRVM_july_21_research/async-memokey-fix.patch` |
| II | 26 | CANONICAL | `FINDINGS.md:406` (fault injection must assert the fault fired) |
| II | 20, 21, 22, 24, 25 | removed 2026-07-22 | "no coherent numbered 20–25 series"; two paraphrases kept as *Unnumbered candidate principles* (fixed-point coverage, oracle separation) |

Totals: **11 IDs = 7 CANONICAL (4 attested + 3 ratified) + 4 RESERVED; 0 numbered Tier B remain.**
Citation form in code: `Law N` / `Binding Law N` (`laws_check.py` `CITE_RE`); witness form
`path:line[,line…]`. `laws_check.py` reports ORPHAN CITATION, RESERVED LAW CITED, UNRATIFIED
AUTHORITY, UNCITED LAW, and — the reverse direction — BROKEN WITNESS and UNRESOLVED REF (it parses
`path:line` spans rather than pattern-matching). The ratification file is "additive, permanent" and is
itself the canonical provenance for Laws 4, 6, 23.

### The inbound handoff — how a candidate law is proposed to TRVM

`invariant-r10/handoffs/TRVM_E42_E43_CANDIDATE_LAWS.md` (3,932 B, 547 words; sha256
`3f51ff05…0781`; blob `b3c30636…`; 2026-09-02). ADVISORY. It proposes two kept-red candidate laws in
the grid's own grammar — **E-43 `world.scope-registry-versioned@1`** (S4 adequacy) and **E-42
`warrant.lineage-bound@1`** (S4 representation adequacy, S3 by cross-reference) — each with a witness
(W3, W4) produced by `experiments/observe_is_write/probe_observe_is_write_repro.mjs` against
`trvm_world.mjs` v0.12.0 at TRVM `fd0df4c` (the probe slices lines 160–1019 and refuses if the file's
sha256 moves), two encodable contracts (A/B), and the grid's own vocabulary: "if you register either
law today its status is `FALSIFIED` with these witnesses, kept red until the contract is encoded and
the probe goes green". It states "Nothing under `TRVM/` was edited by the R10-pre lane". The proposal
protocol is therefore: id in registry grammar `@1` → status from `status_vocabulary` → witness →
contract choice by the TRVM lane → entry in `law_registry.entries`. Neither id exists in the grid
today (0 hits).

**Namespace warnings:** the grid uses `E-1b`…`E-8` as *exhibit* labels (emission-conformance
exhibits: "E-8 SEMANTIC EQUIVALENCE", "E-1b CANONICAL BYTE REPRODUCIBILITY") and `S1`/`S2` as
*executor session* labels — both collide textually with dataset A's `E-xx` records and `S1–S5`
obligations. `law:` cites and `Law N` cites are two different systems (`invariant-grid.json` vs
`LAWS.md`).

### Linkability (B3)

Deterministic: `law:<id>@<rev>` resolves to exactly one entry (JSON Pointer `/law_registry/entries/<i>`
at blob `9739bcc6`); `Law N` resolves to one `###` heading in `LAWS.md`; witnesses are `path:line` and
are checked by `laws_check.py`. Missing: `evidence` is unstructured prose (no witness paths, no
hashes inside the registry entry); the grid `date` is stale relative to its commit; `grid_law_id`
appears on one entry only; there is no field linking a registry entry to the `changelog_from_*` round
that introduced it.

---

## B4 — WEK (World Enforcement Kernel) R0 documents

**What WEK is.** The acronym is expanded exactly once in the tree: `WEK_R0_FINDINGS.md:165` —
"(**World** Enforcement Kernel, **World** Reference Monitor, `wek-control`, per-World quotas)". It is
a *proposed* enforcement kernel reviewed in rounds R0–R3 against a frozen handoff. **There is no WEK
code:** `find` over the tree yields only the 8 documents plus `scripts/make-wek-census-gate.mjs`
(15,675 B), `scripts/sabotage-wek-census-gate.sh` (6,924 B) and `scripts/.wek-sabotage-result.json`
(census tooling, not WEK); `WEK_R0_FLOOR_CENSUS_V0.md:224` says "WEK-specific code 0 LOC (WEK does not
exist)". The frozen inputs the findings are written *against* — `WEK_0_R2_FROZEN_R0_R2_OPUS_HANDOFF.md`
and `WEK_FABLE_R3_EXECUTION_ADDENDUM_FOR_OPUS.md` — are **NOT FOUND in the tree**; they exist only in
`/home/travis/Downloads/` (with `WEK_0_BUILD_AND_FALSIFICATION_BRIEF.md`, `WEK_0_R1_REVISED_OPUS_HANDOFF.md`,
`WEK_FABLE_REVIEW_R2.md`, `WEK_FABLE_REVIEW_R3.md`, `WEK_FABLE_REVIEW_R3_1.md`).

All 8 files are tracked in the container repo (`/home/travis/ProjectAmp2`, HEAD `90d254c`, `main`),
last touched by `c1c7d82` 2026-08-28.

| File | Bytes | sha256 (prefix) | blob | Class |
|---|---|---|---|---|
| `WEK_R0_FINDINGS.md` | 26,716 | `2d94fa4e` | `e4f7c47b` | ADVISORY (review findings) |
| `WEK_R0_EXISTING_LAWS_MAP.md` | 15,216 | `e349fbc7` | `8989fc82` | ADVISORY/DERIVED (maps other registries) |
| `WEK_R0_FLOOR_CENSUS_V0.md` | 14,317 | `f4c21a88` | `996ba763` | ADVISORY (census proposal, "not self-approved") |
| `WEK_R0_REPO_MAP.md` | 13,993 | `a24ac521` | `2b60fdaf` | DERIVED (revision snapshot 2026-08-27) |
| `WEK_R0_REVIEW_BUNDLE.md` | 12,304 | `bcd839a5` | `9c970c76` | ADVISORY ("GO to R1") |
| `WEK_R0_PRIOR_ART_MATRIX.md` | 12,009 | `ea2a2e73` | `8e2b5dfe` | ADVISORY |
| `WEK_R0_CENSUS_GATE.md` | 7,702 | `a3544699` | `84964fb5` | DERIVED (generated by `make-wek-census-gate.mjs`; "regenerate rather than edit") |
| `WEK_CENSUS_BASELINE.json` | 3,933 | `063d8b47` | `78272b90` | DATA, status "PROPOSED, not approved — awaits Fable countersign and GPT reconciliation" |

**Findings id scheme** (`^[MNQ]0-\d+$`): BLOCKER 0; MAJOR **M0-1…M0-5**; MINOR **N0-1…N0-9**;
QUESTION **Q0-1…Q0-3**. Cross-round ids referenced but defined elsewhere: `M3-1`, `M2-2`, `M2-5`,
`M2-6`, `N3-1`, `N3-2`, `N3-3`, `N3-5`, `Q3-1`. Symbols `Σ.W`, `Σ.E`, `Σ.H`, `Σ.P`, `Σ.R`, `Σ.A`
(WEK's state components). Census symbols `G_0`, `M_0`, `P_0`, `S_0`, `D_0`, `L_0`, `U_0`; census id
`WEK-CENSUS-R0.0`. W-laws `W-1`…`W-16` (16, all named in the laws map).

**The existing-laws map** (`WEK_R0_EXISTING_LAWS_MAP.md` §0) names four law registries "that actually
enforce something", by path and measured count: box-and-box kernel (`AmpersandBoxDesign/box-and-box/test/laws.mjs`,
**109 enforced**), box-and-box CC2 compose (`test/compose-laws.mjs`, **101 enforced + 3 declared-open**),
TRVM governance laws (`TRVM/LAWS.md` + batteries + `laws_check.py`, **11 IDs: 7 CANONICAL, 4 RESERVED**),
and `ampd` compile-time/runtime invariants (`super/ampd/lib/ampd/`, "not a numbered register"). It
then maps W-1…W-16 each to an existing analogue with a verdict (compatible / superseded-by-sharper /
contradicted), lists six repo laws WEK lacks (§2: P-3 evidence–action linkage,
canonical-wire/content-address-is-not-a-warrant, bounded-claim, installation confers zero authority,
a read that can refuse is not free to re-execute, B→A promotion requires a human), and records one
contradiction (§3: W-7 Atomic Internal Commit vs the substrate's declared limit).

**Census figures:** `WEK_CENSUS_BASELINE.json` holds `measured` (G_0: 19 commands / 11 agent-reachable
/ 15 human-control-reachable; S_0: 6 durable authority stores; D_0; L_0: ampd_lib 7,984, host_rust 3,258,
parkvps 1,609; U_0: 22 `unsafe`) and `judged` (M_0 11/5/8 present-full/partial/absent; P_0 8 decoders).
The gate re-derived all 22 measured figures exactly and found the delta protocol "unsatisfiable as
written for M_0 and P_0" (10 judged figures have no falsifier). `WEK_R0_REPO_MAP.md` §0 pins sub-repo
revisions at 2026-08-27 (TRVM `4ba5997`, PARKVPS `ac1bae0`, …) and records "`super/` has no revision
of its own" (N0-8) — resolved the next day when Super became a repo.

**How dataset A points at WEK:** `CROSS_REGISTRY_CLAIM_MAP.json` `source_registry: wek-w-laws` (4
records); the ledger cites "WEK_FABLE_REVIEW_R3_1 M3-1" as a source (a file not in the tree);
package-v2.2/v2.3 ledgers cite "WEK W-16".

**Authority class:** ADVISORY / DERIVED throughout. Linkability: file sha256 + heading (`## M0-1 — …`,
`### W-7 — …`) — regular heading grammars, no anchors; the baseline JSON is addressable by pointer
(`/measured/G_0/total`).

---

## B5 — GPT-5.6 adjudication inputs (ADVISORY)

`invariant-r10` HEAD `699fbc2859efdaf57b2391d51dd7712b471e92b9` (`main`, dirty 0; 2026-09-02T15:40−05:00
"R0.8.7 handback staged in px13 … unadjudicated"). All files below are git-tracked.

| File | Bytes | Date (header) | Disposition (header) | sha256 | blob |
|---|---|---|---|---|---|
| `inputs-gpt-execution-go.md` | 5,837 | 2026-09-01 | GO TO OPUS EXECUTION. NO FURTHER FABLE THEORY ROUND. | `48fbe3c7…4971` | `718a0569` |
| `inputs-gpt-execution-adjudication.md` (v1) | 21,558 | 2026-09-02 | SCIENTIFIC RESULTS GO. PACKAGE v2.3 REVISE BEFORE CANONICALIZATION. | `34e3afc8…cd3d` | `43fb7a29` |
| `inputs-gpt-execution-adjudication-v2.md` | 17,146 | 2026-09-02 | PACKAGE-v2.4 SEMANTICS: ACCEPT. R0.8.4: PARTIAL CLOSURE UNDER EXPLICIT TRUST PROFILES. L1?: KEEP AS CANDIDATE… | `6ee5827b…458b` | `4d194f8e` |
| `inputs-gpt-execution-adjudication-v3.md` | 26,943 | 2026-09-02 | SCIENTIFIC RESULTS GO. `package-v2.5` ACCEPT WITH AN ADJUDICATION PATCH… | `6e6c2701…6c09` | `571f4334` |
| `package-v2.6/inputs/FABLE51_RESEARCH_GPT56_ADJUDICATION_FOR_OPUS.md` | 13,462 | 2026-09-01 | ACCEPT THE RESEARCH AS A HIGH-VALUE FRONTIER MAP; REVISE THE PROPOSED BASIS BEFORE PROMOTION. | `ffe88b85…7742` | `1a3eede7` |
| `package-v2.6/inputs/FABLE51_R10PRE_V2_GPT56_AUDIT_FOR_OPUS.md` | 12,276 | 2026-09-01 | REVISE PACKAGE SURFACES; ACCEPT THE R10-PRE SEMANTIC DIRECTION. | `34b269fa…3819` | `0c3bac9c` |
| `package-v2.6/inputs/FABLE51_R10PRE_V21_GPT56_FINAL_AUDIT_FOR_OPUS.md` | 9,138 | 2026-09-01 | GO TO EXECUTION. Canonical enough for Opus after two trivial text fixes. | `16a4b746…613e` | `657a64f0` |
| `package-v2.6/inputs/R10PRE_EXECUTION_V2_GPT56_ADJUDICATION.md` | 17,146 | — | (= v2 above) | `6ee5827b…458b` | `4d194f8e` (same blob) |
| `package-v2.6/inputs/R10PRE_EXECUTION_V3_GPT56_ADJUDICATION.md` | 26,943 | — | (= v3 above) | `6e6c2701…6c09` | `571f4334` (same blob) |

**Downloads comparison — byte-identical in every case:**
`~/Downloads/R10PRE_EXECUTION_V1_GPT56_ADJUDICATION.md` (21,558 B, `34e3afc8…`) = repo v1;
`…_V2_…` (17,146 B, `6ee5827b…`) = repo v2 = package copy; `…_V3_…` (26,943 B, `6e6c2701…`) = repo v3 =
package copy; `~/Downloads/FABLE51_R10PRE_V22_GPT56_EXECUTION_GO.md` (`48fbe3c7…`) = `inputs-gpt-execution-go.md`.
The v1 adjudication is carried at the repo root only (not under `package-v2.6/inputs/`; `package-v2.5/inputs/`
carries V2 only; v2.3/v2.4 carry the three FABLE51 audits only).

Each input has the header triple `**Date:** / **Input:** / **Disposition:**`, then numbered `#` sections
(`# 1. S6? ruling — ACCEPT the reduction to S1`, `# 2. R0.8.6 / F35 — DO NOT adjudicate closure from
prose`, `# 6. E-42 / E-43 — hand both to the TRVM lane, keep red`). They use E-ids (v1/v2: E-13, E-13a,
E-13b, E-14, E-15, E-42, E-43, E-46; v3: E-14, E-42, E-43, E-50, E-50a, E-50b), S1–S5, F/NC numbers,
and `§` references. Dataset A cites them as "GPT v3 §21.2" — **section numbers, not anchors** — and
records them structurally in `10_MACHINE_READABLE_LEDGER.json` (`adjudication{file,disposition,countersign}`,
`adjudication_v2{file,disposition,applied_in}`, `adjudication_v3{…}`) and in
`CROSS_REGISTRY_CLAIM_MAP.json` (`adjudication_v2_4/_v2_5/_v2_6 {input, applied}`); the lane's
`tools-lane/build_v2_{4,5,6}.py` apply them. Authority class: ADVISORY (external ruling, applied by
convention; nothing in code enforces it beyond the drift gate's expectations).

---

## Cross-source: how dataset A addresses dataset B

`CROSS_REGISTRY_CLAIM_MAP.json` (56 records) uses `source_registry` ∈ {`r10pre-execution` 13,
`cd-core-docs` 11, `trvm-law-registry` 8, `cd-durable-docs` 7, `ampd-readme` 5, `wrl-core` 5,
`wek-w-laws` 4, `claim-ledger` 3}; `source_ids` are **free strings** mixing path + symbol/heading
(`"cd-core/src/locus.rs LifecycleAdmission"`, `"docs/failure-model.md §Identity vs validity"`,
`"ampd/README.md Effect atomicity"`, `"law:world.write-mediated@1"`, `"cells.json:16 ⊥"`);
`witness_paths` are repo-relative paths, sometimes with a `#fragment` (`witnesses/adversarial_worlds.py#M3`,
`probe_observe_is_write.output.txt#W1,W2`) and sometimes prose (`"ampd/test effect (7)"`), rooted in
`experiments` 47, `witnesses` 10, `px13` 9, `tools` 7, `receipts` 7, `ampd` 4, `cd-node` 2, `governance` 1.
No record carries a commit or blob; the commit binding is global (`efa8881`, `7651697`, `fd0df4c` in
`START_HERE_GPT.md`, `evidence_state.json.trust_profile`). Only the `law:` form resolves
deterministically today; everything else needs the grammar an adapter would have to supply
(`path[ §heading | symbol | :line ]` at a named commit).

## Combined identifier index — top 40 across all five sources

Scanned: computedriven 142 tracked files; super 202 (excluding `old_scrap/`); invariant-r10 171
(excluding vendored copies, `px13/`, and packages ≤ v2.5 to avoid double counting); TRVM 4 files
(`LAWS.md`, ratification, grid, `laws_check.py`); WEK 8. Full table: `gpr0/R7B_ident_index_all.json`.

| Rank | Id | Total | Files | computedriven | super | invariant-r10 | TRVM | WEK |
|---|---|---|---|---|---|---|---|---|
| 1 | S1 | 262 | 48 | 6* | 2* | 251 | 3* | — |
| 2 | S3 | 227 | 46 | — | — | 227 | — | — |
| 3 | S5 | 225 | 43 | — | — | 225 | — | — |
| 4 | F35 | 124 | 23 | 18 | — | 106 | — | — |
| 5 | E-42 | 124 | 24 | — | — | 124 | — | — |
| 6 | F22 | 119 | 26 | 9 | — | 110 | — | — |
| 7 | F24 | 118 | 24 | 8 | — | 110 | — | — |
| 8 | S2 | 109 | 37 | — | — | 105 | 4* | — |
| 9 | F23 | 102 | 21 | 11 | — | 91 | — | — |
| 10 | S4 | 100 | 32 | — | — | 100 | — | — |
| 11 | F31 | 98 | 21 | 9 | — | 89 | — | — |
| 12 | E-43 | 98 | 18 | — | — | 98 | — | — |
| 13 | E-14 | 85 | 20 | — | — | 85 | — | — |
| 14 | F32 | 83 | 21 | 21 | — | 62 | — | — |
| 15 | E-13b | 73 | 18 | — | — | 73 | — | — |
| 16 | F30 | 68 | 21 | 6 | — | 62 | — | — |
| 17 | E-50a | 66 | 16 | — | — | 66 | — | — |
| 18 | F33 | 65 | 21 | 8 | — | 57 | — | — |
| 19 | E-50b | 54 | 16 | — | — | 54 | — | — |
| 20 | F34 | 52 | 16 | 3 | — | 49 | — | — |
| 21 | E-50 | 48 | 15 | — | — | 48 | — | — |
| 22 | F1 | 40 | 20 | 10 | 5* | 12 | 13* | — |
| 23 | E-15 | 39 | 15 | — | — | 39 | — | — |
| 24 | E-13 | 38 | 14 | — | — | 38 | — | — |
| 25 | F15 | 34 | 16 | 18 | 2* | 14 | — | — |
| 26 | E-51 | 34 | 12 | — | — | 34 | — | — |
| 27 | F17 | 33 | 10 | 24 | 3* | 6 | — | — |
| 28 | NC24 | 33 | 15 | 9 | — | 24 | — | — |
| 29 | E-46 | 31 | 13 | — | — | 31 | — | — |
| 30 | E-48 | 30 | 13 | — | — | 30 | — | — |
| 31 | NC25 | 28 | 14 | 6 | — | 22 | — | — |
| 32 | F16 | 24 | 9 | 16 | 2* | 6 | — | — |
| 33 | NC17 | 24 | 12 | 15 | — | 9 | — | — |
| 34 | F36 | 22 | 12 | 12 | — | 10 | — | — |
| 35 | F25 | 21 | 10 | 6 | — | 15 | — | — |
| 36 | NC26 | 21 | 14 | 9 | — | 12 | — | — |
| 37 | E-8 | 20 | 1 | — | — | — | 20* | — |
| 38 | E-49 | 19 | 12 | — | — | 19 | — | — |
| 39 | F19 | 18 | 8 | 12 | 2* | 4 | — | — |
| 40 | F14 | 18 | 8 | 11 | 3* | 4 | — | — |

`*` = textual collision, a different namespace: computedriven `S1` is a store label; super `S1` is a
SHA-256 rotation variable in `app-prototype.html` and super `F1`…`F17` are `locus_test.exs` case labels;
TRVM `S1`/`S2` are session labels, `E-8`/`E-1b` are exhibit labels, `F1` is grid prose. The F37/NC29/NC30
identifiers (R0.8.7) appear **only in computedriven** (9/5/5 hits) — dataset A has not ingested them
yet, consistent with `px13/README.md` ("R0.8.7 staged … not yet reflected in any package").

## What is missing for deterministic linking (all sources)

1. **Stable anchors in markdown.** None of the receipts, adjudications, review briefs or WEK
   documents carry heading ids. Heading text is regular enough to key on in the `*-FALSIFIED.md`
   files (`## F<N> — `), WEK findings (`## [MNQ]0-<n> — `), and adjudications (`# <n>. `), and
   irregular elsewhere.
2. **Per-record ids in JSON receipts.** computedriven JSON receipts have no `id`/`schema`; battery
   receipts are git-ignored; Super conformance vectors are keyed by `name`; Super receipts are
   sequence-numbered per DETS store.
3. **Commit binding on the A→B edge.** `source_ids`/`witness_paths` carry no commit; the pins live in
   three prose/`trust_profile` fields. An adapter must join each record to `{efa8881 | 7651697 | fd0df4c}`
   by `source_registry` and then to a blob OID by path.
4. **Namespace tagging.** `F`, `S`, `E-` collide across sources; every identifier stored in the graph
   needs a `(source, namespace)` qualifier, e.g. `computedriven:F35`, `superlocus_test:F17`,
   `trvm-grid-exhibit:E-8`, `inv-r10:E-50a`.
5. **Volatility.** `super/` worktree changes minute to minute; `computedriven/lab/receipts-lab/` grows
   while batteries run; the TRVM grid `date` field lags its commit. Cite HEAD OIDs, never worktree state.
