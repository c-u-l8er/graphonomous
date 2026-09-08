# R15 — TRVM governance source inventory

**For:** G1-B, the third authoritative source family (GPT Adjudication v6 §11 → D-071, Phase E0).
**Rule followed:** *do not assume a markdown file is authoritative because it has a useful name.* Every claim below was
read out of the file that a **consumer** actually loads, and the counts were re-measured by this session against the
git object store, not copied from any markdown.

```
source_family : TRVM-GOVERNANCE
repo          : /home/travis/ProjectAmp2/TRVM
commit        : 8816e59055322fc608c9bc7dae9723c02d8402b7   (TRVM-P0.1, accepted GPT v6 §1 / D-065)
read method   : git cat-file blob <commit>:<path>          — never the worktree
mutation      : none. DO NOT invoke `make governance` (see §8.2).
```

**Two planes use the word "law" and must never be merged.**

| plane | where | id namespace | machine-readable |
|---|---|---|---|
| **governance law registry** ("the grid") | `governance/invariant-grid.json` → `law_registry.entries` | `law:<dotted-id>@<int-rev>` | **yes** — JSON, 139 entries |
| **proof-wire protocol suite** | `docs/spec/proof-wire/` | `srel- bpkg- brun- nclaim- nagg- nstruct- vclaim- root- nestpol- nestcps-` | **yes** |
| **"TRVM Laws" constitution** (Series I/II) | `LAWS.md` | bare integers, `Law 5` | **prose, but TRVM defines a grammar** (`tools/laws_check.py`) |

Frozen snapshots that are **not** authority and must be excluded: `p479-review/` (cut at `srel-4844df97…`, grid 1.69.0,
138 entries), `governance/ic32_handoff{,_v2,_v3}/` (grid 1.5.0/1.8.0), `TRVM_july_21_research/`, `attic/`.

## 1 Laws

**`governance/invariant-grid.json`** · blob `667799ff06737132efcc113e8d4bb7007ae24c57` · 712,426 bytes.
The enumeration point is `governance/grid_check.mjs` (`make gov-grid`'s only command), whose single load is
`JSON.parse(readFileSync(A("invariant-grid.json")))`. **No other file enumerates laws.**

**Re-measured by this session:**

```
grid version 1.70.0 · law_registry.grid_version 1.70.0 · entries 139
status dist  PROPERTY-TESTED 127 · REGRESSION-LOCKED 6 · FALSIFIED 4 · PROVED 2
status_vocabulary 8 · canonical 107 · proof.verdict-names-its-verifier present: True
```

**Two id forms, and they differ.** The registry key (`supersedes` / `superseded_by`) is **bare** `<id>@<rev>`; the
**citation** used in source, receipts and prose is `law:<id>@<rev>` (`grid_check.mjs`'s
`CITE = /law:([a-z0-9_.\-]+)@(\d+)/g`). The registry's own note says so. **Do not normalise one into the other.**

**Record shape, measured field frequency over all 139:** `id` 139 · `revision` 139 · `status` 139 · `canonical` 139 ·
`statement` 139 · `evidence` 139 · `revision_note` 26 · `superseded_by` 25 · `supersedes` 24 · `defect_class` 15 ·
`accepted_false_verdict` 15 · `underlying_observations_genuine` 15 · `grid_law_id` 1.

**`canonical` is derived and enforced**, not free-form: `grid_check` requires
`canonical === (revision === maxRevisionForId && superseded_by == null)`, and requires lineage **symmetry**.

**Native status vocabulary (closed, enforced, 8):** `PROVED` `PROPERTY-TESTED` `REGRESSION-LOCKED`
`MODEL-CHECKED-FRAGMENT` `EMPIRICAL` `OPEN` `NOT_APPLICABLE` `FALSIFIED`. Four are unused at this commit.
**Preserve these verbatim.** Do not collapse `PROVED`/`PROPERTY-TESTED`/`REGRESSION-LOCKED` into "passing", and do not
collapse `FALSIFIED` into "failing" — **4 laws are red by design** and TRVM's build fails if one starts *passing*.

Two verbatim entries, one canonical and one deliberately red:

```json
{ "id": "digest.adequacy.sampled", "revision": 1, "status": "PROPERTY-TESTED", "canonical": true,
  "statement": "on freshly sampled term pairs the digest separates semantically distinct states",
  "evidence": "Kernel row L-ADEQ-2: 269 distinct-NF pairs this round, 0 digest collisions." }

{ "id": "kappa.monotonicity.unrestricted", "revision": 1, "status": "FALSIFIED", "canonical": true,
  "statement": "kappa(G') >= kappa(G) under arbitrary single-edge addition — NO",
  "evidence": "C1: 24,576 edge-additions at n=4, kappa decreased in 168; … Kept red by design; the falsifier is the design pressure that produced the flagship." }
```

**A trap:** `deriv` and `derivation` are **both** live first segments (`law:deriv.count-invariance.float@1` is cited in
`scheduler_certificate.json`). Do not normalise them together.

**`LAWS.md`** (blob `b1c6e1dab846aa39d0be6fc6a3e62495fd72108f`) is a **disjoint namespace** (`Law 1`…`Law 26`) about
forge/binding semantics. It is prose **with a TRVM-defined grammar** — `tools/laws_check.py`'s
`DEF_RE = ^###\s+Laws?\s+([\d,\s]+?)\s+[—-]\s+(.+?)\s*$`, yielding 11 definitions; tier is `RESERVED` / `CANONICAL` /
`TIER-B` by the stated prefix rule. **Caveat: `laws_check.py` is wired into neither `make` nor CI.** The grammar exists;
nothing enforces it. And **nothing links a `LAWS.md` integer to a `law:` registry id** — the namespaces never cross.

## 2 Grid

**"The grid" and "the law registry" are the same object.** The claim *"grid 139 entries at v1.70.0"* is correct on both
halves. `grid_check` enforces `version === law_registry.grid_version`, that `version` is the **head of a hard-coded
`LINEAGE` array**, and that the changelog key for the previous version is non-empty. Per-executable versions live in
`artifact_versions` (6 entries, each regex-extracted from source and compared).

Version history: `fd0df4c` 1.69.0/138 → `9e91c96` (TRVM-P0) 1.69.0/138 → **`8816e59` (TRVM-P0.1) 1.70.0/139**. The one
entry added is **`proof.verdict-names-its-verifier@1`**, `PROPERTY-TESTED`, canonical — the law GPT v6 §1 accepted.

**Staleness finding.** `invariant-grid.json.date` is **`"2026-08-18"`** while 1.70.0 was minted 2026-09-03, and
`grid_check` never reads `date`. Treat it as advisory; use the commit date.

Other structured, checked sections worth ingesting: `status_vocabulary` (8) · `defect_class_vocabulary` (4) ·
`schemas` (8 law schemas) · `candidate_schemas_v0_2` (3) · `meta_laws` (7) · `law_shape` · `planes` ·
`artifact_versions` (6) · `semantic_film.replay_refusals` (**19 `sem-*` codes**) · `film_v3_1.replay_refusals` (18) ·
`film_history.v3.replay_refusals` (5) · `warrant.executable.replay_refusals` (10) ·
`scheduler_certificate.claims_vocabulary` (5) · `v1_criteria.criteria` (9, prose values).

## 3 Spec release

| role | path | blob |
|---|---|---|
| current pointer | `docs/spec/proof-wire/SPEC-RELEASE.json` | `09c7dc183e5b8d3f8e00bded005d5b9a29e3ffe7` |
| immutable archive | `docs/spec/proof-wire/releases/srel-f5720a3d….json` | `09c7dc183e5b8d3f8e00bded005d5b9a29e3ffe7` |

**The two are the same git blob** — byte-identical. **17 archived releases**; 16 at `spec_revision: 1`, exactly one at
`spec_revision: 2`, and that one is the current pointer.

**What `srel-` hashes.** `governance/spec_release.mjs`:
`"srel-" + sha256("TRVM-PROOF-WIRE-SPEC-RELEASE-v1|" + canonicalWire(releaseCore(r)))`, `canonicalWire` being the
RFC 8785 encoder from `cas.mjs` gated against 6 upstream vectors. `releaseCore` is 11 members:
`release_type, protocols{wire,verified_claim,nested_composition}, spec_revision, spec_digest, experiment_revision,
experiment_digest, public_corpus_revision, public_corpus_digest, jcs_upstream{...}, holdout_commitment, holdout_entries`
— excluding `spec_files`, `experiment_files`, `note`, `spec_release_id`.

**Re-executed by this session** (import is side-effect free behind an `IS_MAIN` guard):

```
stored    : srel-f5720a3d0ee9dbb95670c9cd66672bf70c7dbe353df0c114a18c8a982f203629
recomputed: srel-f5720a3d0ee9dbb95670c9cd66672bf70c7dbe353df0c114a18c8a982f203629
MATCH: true | spec_revision: 2
```

**Every release field is classified** in `RELEASE_FIELD_PLANES` — four categories, "no fifth":
`CHECKED` · `DECLARED_AND_BOUND` · `DERIVED` · `NON_AUTHORITATIVE`. TRVM's own note:

> *Revision numbers are LABELS. Digests are IDENTITIES.* Two releases may both call themselves spec revision 1; only the
> digest distinguishes them.

Three counters move independently: `spec_revision` 2, `experiment_revision` 12, `public_corpus_revision` 1.

**`constants.id_prefixes`** lives in `docs/spec/proof-wire/schema/nested-composition-v2.json`
(blob `dc91d0f354b42454645bf069eb6462aa48caa45c`, 6,874 bytes) — **7 entries, re-measured**:
`nested_claim_sem_id → nclaim-` · `aggregate_id → nagg-` · `structure_sem_id → nstruct-` ·
`verified_claim_sem_id → vclaim-` · `artifact_root → root-` · `verifier_policy_id → nestpol-` ·
`child_protocol_set_id → nestcps-`. This schema file is inside `spec_digest`. `spec_agreement.mjs` enforces the map
**by minting one id of each kind and reading the text before the first `-`** — the strengthening GPT v6 §1 accepted —
and asserts the runtime does not import the schema, so the two declarations stay independent.

## 4 Refusal vocabulary

**Authoritative:** `nested-composition-v2.json` → `refusal_codes`. **Re-measured: 30 strings, and the array is NOT
sorted** (`nest-certificate-stale` sits between `nest-cycle` and `nest-depth-exceeded`). Do not assume ordering.

The 28→30 growth is TRVM-P0.1's, recorded in `changelog_from_1_69_0[0]`. `TRVM-NESTED-COMPOSITION-v2.md` §7 lists the
same 30 with glosses in a different order — the sets are identical, **but nothing mechanically compares §7 to the JSON**;
§7 is bound only by `spec_digest`. Prefer the JSON; treat the glosses as prose. §7 also states normatively that
conformance compares **sets**, and that refusal precedence is not part of the protocol.

**Three enumerating consumers:** `spec_agreement.mjs` §5 (derives the implementation side from `nest_check.mjs`'s
**string literals**, refusing in both directions) · `nest_forgeries.mjs` (`make gov-nest`, reports `44/44`) ·
`negative_battery.sh` (392 cases).

**Other, separate refusal vocabularies** — in the grid, different namespaces: `sem-*` (19), film v3.1 (18), film
history (5), executable warrant (10). And three **source-literal-only** vocabularies with no normative schema:
`proof-*` (17, `proof_check.mjs`), `domain-*` (20), `compose-*` (16). `docs/spec/proof-wire/schema/` contains exactly
one file, so **only `TRVM-NESTED-COMPOSITION-v2` has a schema-vs-implementation gate**. Ingest the other three as
*implementation-declared*, not normative.

## 5 Verifier policy / checker sets

**There is no on-disk registry.** These are runtime, reported-beside-the-verdict values.

`governance/nest_check.mjs` (blob `aaa8e74304cfda790ee5c4907c6c97f556c0c403`) declares
`SHIPPED_POLICY = {max_depth 32, max_artifact_bytes 8388608, max_total_resolved_bytes 67108864,
max_operands_per_node 64, max_artifact_resolutions 4096, derivation_reuse true}`, with
`policyId(p) = "nestpol-" + H(NEST_PROTOCOL + "|" + sortedKeyValueJoin(p))` and
`childProtocolSetId(supplied) = "nestcps-" + H(NEST_PROTOCOL + "|" + stable(supplied))` over the **sorted list of flat
`{protocol, checker_id, claim_field}` records**. The same six values appear normatively at
`constants.verifier_policy` and `spec_agreement` compares them field for field.

**Composition:** when no table is supplied, `child_protocol_set_id` is `null` and `verifier_policy_id` is
**byte-identical to every id issued before the mechanism existed**. When one is supplied, the set id is folded into the
policy preimage, so one coordinate names both what was bounded and who was allowed to check.

`effectivePolicy` allows **tightening only**: a numeric field above the shipped bound is `nest-policy-weakened`;
`derivation_reuse:false` is stricter and allowed; an unknown key refuses.

**Critical for ingestion: these are verdict-time values, not persisted ones.** `governance/nest_bundle.json` contains
no `verifier_policy_id`, no `child_protocol_set`, no `checker_id`. Spec §8 states the consequence, and it is exactly
law `proof.verdict-names-its-verifier@1`:

> A `checker_id` is a NAME, not a warrant … **verification without verifier identity is incomplete evidence.**

## 6 Blind-run ledger

**Live record** `governance/blind-run.json` (blob `2f8937f0bacc74225cee05c3db98cb1579a3c95a`, 1,083 bytes):
`type TRVM-BLIND-IMPLEMENTATION-RUN-v3` · `status PINNED` · `spec_release_id srel-f5720a3d…` ·
`blind_package_id bpkg-350de811…` · `instrument_digest 1f763b5b…` · `blind_contract_revision 12` · one javascript
reference adapter · `run_id brun-e553dc1d…`.

**State machine** — `docs/spec/proof-wire/experiment/run_state.mjs`:

```
STATES = [PINNED, CANDIDATE_FROZEN, REVEALED, COMPLETE, ABORTED]
NEXT   = { PINNED:[CANDIDATE_FROZEN,ABORTED], CANDIDATE_FROZEN:[REVEALED,ABORTED],
           REVEALED:[COMPLETE,ABORTED], COMPLETE:[], ABORTED:[] }
RUN_ID_RE = /^brun-[0-9a-f]{64}$/     receiptFile(run) = `${run_id}.${status}.json`
```

`runCore(r)` is the whole record but its own id, and **`status` is inside the core — so every transition mints a new
`run_id`.** The preimage is line-oriented (`key\tJSON.stringify(value)`), a **different encoding from `srel`'s JCS**.

**Ledger, re-measured by this session:** `governance/receipts/` holds **39 files**, all tracked, all
`brun-<64hex>.<STATUS>.json`:

```
18 ABORTED · 17 PINNED · 2 CANDIDATE_FROZEN · 2 REVEALED · 0 COMPLETE
```

**Two receipt generations coexist**: `TRVM-BLIND-RUN-RECEIPT-v1` (11 files) and `-v2` (28). **`previous_run_id` and
`previous_status` are v2-only fields** — an adapter must treat them as optional. This is the structural reason behind
GPT v6 §2: every `PINNED` receipt has `previous_run_id: null` (a pin starts a fresh chain) and every v2 `ABORTED`
receipt names a `PINNED` predecessor that is present on disk. **The experiment has never reached `COMPLETE`**; the 12
experiment revisions and 17 releases are abort-and-repin cycles.

The ABORTED receipt `brun-3925f952…` is the record of the P0.1 release act itself and is the single best structured
statement of what changed at HEAD — its `note` names the code split, spec revision 2, the affected spec sections, and
the id_prefixes addition. (`note` is classified NON_AUTHORITATIVE by design.)

## 7 Child protocols — the headline finding

**There is no persisted registry. The child-protocol table is a runtime API parameter, not a file.** Nothing in TRVM
writes an accepted registration to disk. A protocol id can be *declared* in exactly two places:

1. **normative** — `nested-composition-v2.json` → `constants.child_protocols`, **3 entries**
   (`TRVM-BOUNDED-PROOF-v1`, `TRVM-BOUNDED-DOMAIN-PROOF-v1`, `TRVM-NESTED-COMPOSITION-v2`), each `{claim_field, composed}`;
2. **implementation** — `IMPLEMENTED_CHILD_PROTOCOLS` in `nest_check.mjs`, the same 3 keys plus a `check` function.

`spec_agreement` compares the key sets and each entry's `claim_field`/`composed` (never `check`).

**Registration validation** — every failure is a *named refusal*, never a throw. Key set must be exactly
`{check, checker_id, claim_field, composed}`; `composed` must be `false`; `checker_id` non-empty; a key colliding with a
built-in draws **`nest-child-protocol-override-refused`**, everything else
**`nest-child-protocol-registration-malformed`**. Entries are copied field by field, merged **under** the built-ins, and
frozen.

**TRVM-P0 exists because of Graphonomous** — `nest_forgeries.mjs:549` says so, citing *"Graphonomous D-054/D-055,
research note R13"*.

**Consequence, and it constrains G1-B directly:** registering `GRAPHONOMOUS-PROJECTION-v0` (or v1) produces **no
durable TRVM state**. The only durable artifact is a verdict Graphonomous itself keeps — and by TRVM's own law
`proof.verdict-names-its-verifier@1`, that verdict is meaningless without `verifier_policy_id`,
`child_protocol_set_id` and `child_protocol_set.supplied[]` stored beside it. **Any "Graphonomous is a registered child
protocol" edge is Graphonomous-owned and must never be attributed to TRVM at this commit.**

## 8 Deterministic read plan

**8.1** Every authoritative artifact is a plain file tracked in git at HEAD. None requires running a command; none
lives only in a CAS or only in memory. `git rev-parse HEAD:<path>` pins every one, and
`git cat-file blob HEAD:<path>` is strictly better than a worktree read here — **this tree is shared by concurrent
sessions**, so a worktree read is not reproducible while a pinned-commit read is.

**8.2 DO NOT RUN `make governance`.** Measured by counting write calls and reading guards:

| tool | writes to the repo? |
|---|---|
| `grid_check.mjs` | **no** — 15 writes, all into `mkdtempSync(tmpdir())`, cleaned in `finally` |
| `nest_check.mjs`, `holdout_score.mjs`, `field_audit.mjs`, `jcs_vectors.mjs`, `live_dag.mjs` | **no** — 0 writes |
| `spec_release.mjs`, `blind_run.mjs`, `spec_vectors.mjs`, `blind_package.mjs` (no args) | **no** — writes only under their `--update`/`--pin`/… flags |
| `nest_bundle.mjs`, `proof_bundle.mjs`, `domain_bundle.mjs`, `compose_bundle.mjs` | **YES, unconditionally as main** |
| `experiment_falsifiers.mjs` | **YES — 86 writes**; the Makefile says it drives the run record through every state and restores it |

So `make governance` mutates `blind-run.json`, `receipts/` and the four `*_bundle.json`. **A read-only adapter must
never invoke it.** Any freshness check is *"is the committed blob still `<sha>`"*, never *"re-run the harness"*.

**8.3 The safe re-derivation surfaces** (pure exports, import side-effect free): `spec_release.mjs`
(`releaseId`, `releaseCore`), `run_state.mjs` (`runCore`, `runId`, `STATES`, `NEXT`, `INSTRUMENT`), `nest_check.mjs`
(`policyId`, `childProtocolSetId`, `SHIPPED_POLICY`, `IMPLEMENTED_CHILD_PROTOCOLS`), `cas.mjs` (`canonicalWire`).

**8.4 A second operational caution:** `.github/workflows/ci.yml` runs `native`, `native-selftest`, `conformance`,
`wasm-smoke`, `swarm`, `research` — and **no governance target**. A green CI badge says nothing about grid consistency,
spec release, or the blind run. The evidence plane is a local gate only.

## 9 Prose-only (advisory — no edges)

`statement` · `evidence` · `revision_note` · every `note`/`why`/`annotations`/`informational` field (several of which
declare themselves NON-AUTHORITATIVE) · all ~90 `changelog_from_*` arrays · `invariant-grid.json.date` ·
`v1_criteria.criteria` · the round ledgers and their numbered "ledger items" (referenced everywhere, **no grammar
defines them**) · `ROUND_*_BRIEF_FOR_GPT.md` and the review packs · `FINDINGS.md`, `docs/spec/paper.md`,
`docs/spec/SPEC.md`, `README.md` · `LAW_RATIFICATION_2026-07-22.md` · the `WRL_*`/`FORGE_*` memos ·
`TRVM-NESTED-COMPOSITION-v2.md` §1–6, 8, 9 · `LAWS.md` statement bodies (the *headings* have a grammar; the bodies do
not) · **the mapping "grid law ↔ Makefile gate", which exists in prose only.**

**Count claims in TRVM prose that disagree with TRVM's structured source** — candidate G1 findings:

| claim | where | structured truth |
|---|---|---|
| "28 refusal codes" | `governance/round-11-ledger.md:4255`, `ROUND_P43_BRIEF_FOR_GPT.md:88` | **30** in `nested-composition-v2.json` |
| grid `date` = 2026-08-18 | `invariant-grid.json` | 1.70.0 was minted 2026-09-03 |

No case was found where the 139 / v1.70.0 grid claim or the `srel-f5720a3d…` claim disagreed with its source.

## 10 Structural cross-references TRVM actually states

```
law         --supersedes-->        law          (24, bare <id>@<rev>, symmetry enforced)
law         --superseded_by-->     law          (25)
law         --has_status-->        status_vocab (139, closed set)
law         --has_defect_class-->  defect_class (15, closed set)
receipt     --cites_law-->         law          (law_refs arrays; 5 artifacts, 20 top-level + 4 nested)
blind_run   --against_release-->   spec_release (1 live + 39 receipts)
blind_run   --uses_package-->      blind_package
blind_run   --uses_instrument-->   instrument_digest
blind_run   --previous_run_id-->   blind_run    (v2 receipts ONLY; optional)
spec_release--binds_file-->        spec_file (4) / experiment_file (15)
spec_release--pins_upstream-->     jcs_upstream{repo, commit, digest, vectors}
spec_release--declares_protocol--> protocol id  (3)
schema      --declares_code-->     refusal_code (30)
schema      --declares_prefix-->   id_prefix    (7)
schema      --declares_child-->    child_protocol (3)
schema      --declares_policy-->   verifier_policy (6 bounds)
gov_artifact--has_role-->          case_input|tool|generated_evidence|probe|gating_probe
```

The **five artifacts carrying a `law_refs` array** are `scheduler_certificate.json` (3), `refinement_receipt.json` (3),
`world_warrant_receipt.json` (8 + 3 nested + 1), `maintenance_receipt.json` (5), `golden_prehash_vectors.json` (3).

**Re-measured by this session: the four proof-wire bundles carry NO `law_refs`** — `nest` False, `proof` False,
`domain` False, `compose` False.

**Weaker: free-text `law:` citations.** `grid_check` scans a declared artifact set for `law:<id>@<rev>` and requires
every hit to resolve and be canonical unless in history context. An edge derived from those is *"TRVM's checker
requires this token to resolve"*, **not** *"TRVM declares this law governs this artifact"*. Label accordingly.

### What is NOT stated structurally — do not fabricate

- **A grid entry names no refusal code in any field.** Codes appear only inside `statement`/`evidence` prose.
- **A grid entry names no Makefile gate.** Prose only.
- **A grid entry names no `srel-`.** Prose only.
- **A bundle names no law.** Confirmed absent, all four.
- **A release names no law set.** There is no `law_refs` in any release object. **Do not fabricate release→law.**
- **Nothing links a `LAWS.md` integer to a `law:` registry id.**

## 11 The ingestion contract this recommends

**Ingest, at the pin above:** `governance/invariant-grid.json` · `docs/spec/proof-wire/SPEC-RELEASE.json` ·
`docs/spec/proof-wire/releases/srel-*.json` (17) · `docs/spec/proof-wire/schema/nested-composition-v2.json` ·
`governance/blind-run.json` · `governance/receipts/*.json` (39) · `governance/blind-package.json` ·
`governance/holdout/INDEX.json` · `governance/artifacts.json` · the five `law_refs`-carrying receipts ·
the four `*_bundle.json` **headers only** (`compose_bundle.json` is 1.6 MB of children).

**Preserve verbatim, never re-mint:** `<id>@<rev>` · `law:<id>@<rev>` · the grid version string ·
`srel- bpkg- brun- root- vclaim- nclaim- nagg- nstruct- nestpol- nestcps-` · the chain prefixes
`cema- cemp- dsem- erul- esem- isem- lsem- xenc- tenc-` · `H1`…`H10` · `Law <n>` · every native status word.

**Mark advisory:** everything in §9, plus any law→refusal-code, law→gate or law→release association.
