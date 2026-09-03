# DEMO SCRIPT — "the ComputeDriven Floor, explained by its own evidence"

**State: steps 1–3 TESTED by G0-B/B.1 (2026-09-02/03); step 6 TESTED by G0-E (2026-09-03: A1 is an executable `explain` over a DERIVED `not_primitive`, `test/query.test.mjs`); step 5 partly TESTED (A4/A3 as queries); step 9 REACHED AS A SPIKE (G0-C: `gsem-` moves on exactly the edited relation, every other kernel `rev-` holds — identities PROVISIONAL, D-036); steps 4, 7, 8 DESIGNED, not run.** Each step names what it proves and the gate that
must be green before it may be shown. The demonstration is stronger than "we drew nodes and edges" only if every
answer on screen is a traversal over stored records (spec §13), never prose typed for the demo.

| # | Step | What it proves | Gate before showing |
|---|---|---|---|
| 1 | Freeze a real invariant snapshot: `g0 snapshot` writes `snapshots/baseline.json` / `historical.json` with six pinned trees (commit, tree, blob per file) | the input is pinned; anyone can re-read the same bytes | **TESTED** — `openSources` refuses a moved blob or tree (`SOURCE_MOVED`) |
| 2 | Ingest it: `g0 project` runs the crosswalk adapter over the frozen snapshot; `projections/EVIDENCE.md` shows 61 typed faults beside 3,200 records | malformed/ambiguous source states are visible, not guessed away | **TESTED** — zero `SOURCE_MOVED`; every fault names its rule and what it concerns |
| 3 | Build the same semantic digest three times (plain; shuffled inputs + reversed adapters; a second seed); show the roots | reconstruction is deterministic (spec §6.5, A8) | **TESTED** — roots identical, record files byte-identical, the Python twin re-derives the root from the manifest |
| 4 | Open the "ComputeDriven Floor" graph: S1–S5 as obligations, L1? on its own axis, FAC-CONTROL-SENSITIVITY on the factory axis; filters by kind/relation/status/scope | the projection carries the dataset's own five-level ontology | G0-G gates green; UI reads the canonical JSON, not a hand-made file |
| 5 | Select S3: mechanisms (`IMPLEMENTS`), falsifiers/findings (F31–F37 with CLOSES/OPENS), experiments (R0.8.x, EXP-1 ARM A/B), receipts (handback tarballs with sha256), profiles (`SCOPED_BY`), and every source location | one obligation explained end-to-end from provenance | A4 passes for the R0.8.5 handback receipt |
| 6 | Ask "Why was S6 reduced?": the answer is the A1 traversal — `obligation:S6?` → `REDUCES_TO` → `obligation:S1`, premises E-44, the S6 experiment result, GPT execution adjudication v1 §1, ledger C-7 UNKNOWN→TESTED | an explanation is a derivation path, not recollection | A1 passes; every node on the path has a `SOURCE_LOCATION` |
| 7 | Toggle to a historical snapshot (package v2.5 or v2.4 — HISTORICAL sources ingested as their own snapshot) and show how E-13b's evidence state moved, with the typed sensitivity witness on the transition | history is kept; supersession never deletes | two snapshots ingested; `SUPERSEDES` relations present; the v2.5→v2.6 promotions match `promotions[]` |
| 8 | Introduce a controlled fixture: a copy of the crosswalk with one record's token set to `TESTED` and its receipts removed; run G1; show the `UNSUPPORTED` diagnostic with its evidence and the rule id | G1 detects a missing-receipt promotion and shows why | the same fixture is refused by `check-evidence-transitions.mjs` (the factory kit) — two independent gates agree |
| 9 | Sandbox mode (optional): change one relation in the sandbox WRL world (textually or visually), re-seal, re-project; show that the `sem-` id moved and the graph reflects exactly the one change | bidirectional WRL integration without canonical write authority | depends on the WRL contract (spec §7); shown only if the WRL profile decision lands in G0-C |

What the demo must **not** do: type a count into a caption (counts are read from the manifest); show a
"confidence" that the source did not state; hide a fault; use an LLM answer anywhere on the path.
