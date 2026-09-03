# Graphonomous v2 — G0/G1 lane (the semantic/evidence graph over authoritative registries)

**Opened 2026-09-02; G-PR0 complete the same day — `SPEC FREEZE: READY FOR G0` (see `handoff/STATUS.md`).** This directory is the new direction for Graphonomous, worked under the
master brief `~/Downloads/GRAPHONOMOUS_FABLE51_MASTER_PROMPT_v1.md` (GPT, 2026-09-02). It sits
beside the v0.4 Elixir memory engine in this same repository and does not modify it.

> **Working definition under test:** *Graphonomous is the persistent semantic/evidence graph that
> makes what a system understands queryable, falsifiable, provenance-linked, and reducible.*
>
> **Authority boundary (frozen for G0/G1):** Graphonomous is a *derived semantic projection* over
> authoritative registries and evidence. It is **not** another authoritative registry. It may
> derive, relate, rank, challenge, detect inconsistency, and propose. Canonical evidence-state
> promotion stays with the owning registry / factory / adjudication mechanism.

## Where things are

| Path | What |
|---|---|
| `handoff/STATUS.md` | the only place that says what is DESIGNED / IMPLEMENTED / TESTED / FROZEN / BLOCKED / PROPOSED |
| `handoff/SOURCE_INVENTORY.md` | every repository, registry and artifact used, with revision and authority class |
| `handoff/RESEARCH_REPORT.md` | the G-PR0 research answers (online + repo-grounded) |
| `handoff/DECISION_LOG.md` | every consequential decision, alternatives, evidence, reversibility |
| `handoff/G0_G1_SPEC.md` | the frozen G0/G1 contract (ontology, identity, provenance, WRL/TRVM, projection, query, UI, faults, acceptance) |
| `handoff/STACK_GAP_REGISTER.md` | WRL / TRVM / WEK / ComputeDriven gaps, classified |
| `handoff/STACK_FIX_RECEIPTS/` | one receipt per stack change made under the repair protocol |
| `handoff/INGESTION_CONTRACTS/` | one contract per authoritative source adapter |
| `handoff/WRL_SCHEMA_OR_PROFILE/` | the WRL profile / schema that carries the semantic graph |
| `handoff/TEST_FIXTURES/` | frozen input snapshots and expected digests |
| `handoff/DEMO_SCRIPT.md` | the demonstration, step by step, with what each step proves |
| `handoff/research/` | the nine G-PR0 reports verbatim (R1–R8 + census JSON) and the probe scripts that produced their measurements |
| `handoff/SOURCE_QUALITY_FINDINGS.md` | what the registries look like from an adapter's seat (Q-01…Q-21) |

## Ground rules carried from the brief

- Research/spec freeze (**G-PR0**) before broad implementation. Scratch experiments are allowed; production feature work is not, until `G0_G1_SPEC.md` is frozen.
- Never mutate authoritative source data during read-only ingestion. The registries this lane reads (`invariant-r10/`, `~/.invariant-factory/canonical.git`, `computedriven/`, `TRVM/`, `super/`, `opensentience.org/_invariants/`) are owned by other lanes that may be running concurrently in this same tree.
- A stack defect found by this work is reproduced minimally, fixed in the owning layer only when the evidence supports it, tested there, receipted under `handoff/STACK_FIX_RECEIPTS/`, and then the interrupted Graphonomous acceptance case is re-run. No private "Graphonomous semantics" layer that duplicates WRL/TRVM.
- No LLM output is evidence. Deterministic, content-addressed, replayable transforms only.

## The code (G0-A/G0-B 2026-09-02 · G0-B.1, G0-E, G0-C spike, WRL-P0 + G0-C sealed, G0-D certificate 2026-09-03)

```
lib/canon.mjs        canonical bytes = TRVM canonicalBytes over the G0 value domain; the strict source reader; hashes
lib/lid.mjs          logical ids; relation lids ARE propositions (D-029); contextBoundLid for unnamed statements (D-030); SUPERSEDES/STATE_TRANSITION_OF endpoint pairs refused at emission and projection (D-037)
lib/schema.mjs       a JSON Schema 2020-12 subset validator (refuses keywords it would ignore)
lib/rules.mjs        the rule set as data: load, validate, stratify, content-bound rule ids (variables: Capital+lowercase)
lib/emit.mjs         what an adapter emits: rel(kind, src, tgt, at, {attrs, asrt}) — occurrence data goes on the assertion
lib/project.mjs      the projector: fold, validate, hash, write, CAS, manifest, root, verify
lib/facts.mjs        records → base facts node/attr/rel/rattr/asrt/aattr                          (G0-E)
lib/eval.mjs         the stratified semi-naive evaluator with per-fact derivations                 (G0-E)
lib/check.mjs        the INDEPENDENT derivation checker (shares no logic with eval.mjs)             (G0-E)
lib/evaluation.mjs   run/verify an evaluation: <projection>/derived/ with its own CAS root          (G0-E)
lib/query.mjs        node · neighbors · path · facts · explain · as_of                              (G0-E)
lib/wrl_world.mjs    G0-C: builds the graphonomous.semantic.v0 SUBMISSION; WRL seals it (canonicalizeV2Artifact → v2WorldIdOfArtifact → deriveV2Relations): real sem-, kernel rel-/rev- (WRL-P0, pin b072db0; D-041/D-047)
lib/wrl_world_spike.mjs  HISTORICAL: the D-036/D-037 spike canonicalizer (gsem-/grelpre-), kept only to reproduce the supersession mapping (D-038)
lib/certificate.mjs  G0-D: the GRAPHONOMOUS-PROJECTION-v0 certificate — build <projection>/certificate/{bundle.json,VCLAIM} (TRVM verifiedClaimSemId over claim/aggregate/chain) and the checker that re-derives every plane from the directory, writes nothing, returns TRVM's public result shape; `childProtocolEntry(dirs)` is the entry a TRVM nest verifier supplies after TRVM-P0 (D-054/D-055, R13 §6)
adapters/git.mjs     pinned, read-only git access (never the working tree)
adapters/crosswalk.mjs  the first authoritative adapter (crosswalk + evidence_state, v2.6 and v2.7; bare ids per D-031; transition → claim is STATE_TRANSITION_OF, never SUPERSEDES — D-037)
bin/g0.mjs           g0 snapshot | project | verify | census | eval | verify-eval | query | world | certify | check-cert
rules/g0.rules.json  spec §13, D-022 names, assertion-aware (D-032)
schemas/*.schema.json  record schemas incl. derived_fact + evaluation (regenerate with node schemas/build_schemas.mjs)
snapshots/*.json     the two pins (baseline ba4e625 / historical 699fbc2)
projections/         baseline + historical (each: records, cas (+ the snapshot record beside the manifest), derived/, world/ = the WRL-sealed world, world-spike/ = the D-037 spike receipt, certificate/ = the G0-D certificate) · pre-b1/ and pre-d034/ receipts (superseded, preserved) · EVIDENCE.md
handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json  the SUBMITTED profile declaration (SEALED by WRL-P0; the admitted one is WRL's V2_PROFILES row, held equal by test)
handoff/G0C_IDENTITY_MATRIX.md  the measured identity-change matrix (tools/identity_matrix.mjs)
handoff/G0D_GOLDEN_VECTORS.md  the G0-D certificate ids per pin + sensitivity table (tools/g0d_vectors.mjs; labelled with the TRVM pin — re-minted when it moves)
test/                node --test; canon_twin.py is the independent Python twin; helpers/fake_repo.mjs for synthetic sources
tools/               evidence.py (regenerates EVIDENCE.md) · identity_matrix.mjs (G0C_IDENTITY_MATRIX.md) · g0d_vectors.mjs (G0D_GOLDEN_VECTORS.md) · make_gpt_bundle.mjs (handoff ZIP + REPRO_DEPENDENCIES)
```

Run: `npm test`; `node bin/g0.mjs project --snapshot snapshots/baseline.json --out projections/baseline`;
`node bin/g0.mjs verify --dir projections/baseline`; `python3 test/canon_twin.py --manifest projections/baseline`;
`node bin/g0.mjs eval --dir projections/baseline && node bin/g0.mjs verify-eval --dir projections/baseline`;
`node bin/g0.mjs query --dir projections/baseline,projections/historical --as-of snapshot:g0:historical-699fbc2 neighbors round:computedriven:R0.8 OPENS out`;
`node bin/g0.mjs world --dir projections/baseline` (seals through WRL; prints the `sem-`);
`node bin/g0.mjs certify --dir projections/baseline && node bin/g0.mjs check-cert --dir projections/baseline` (G0-D: mints and re-checks the certificate; exit 1 on REFUSED). Zero runtime dependencies; the TRVM encoder/CAS and the WRL
relation layer (`relation-v2.js`, which imports the kernel and the spine) are imported from the pinned sibling checkouts and their blob OIDs are checked at test time. The tests that need
only the shipped projections (canon, lid, schema, rules, eval, b1, query, wrl_world, certificate, certificate_trvm) run from the handoff ZIP;
`test/projection.test.mjs` rebuilds from the pinned registries and needs the real tree.
