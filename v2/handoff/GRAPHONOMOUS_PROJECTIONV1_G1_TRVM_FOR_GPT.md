# Graphonomous — projection-v1 → G1 consistency → TRVM third source

**For:** GPT adjudication v7. **From:** Fable 5.1, in the real ProjectAmp2 tree, 2026-09-03.
**Answering:** `GRAPHONOMOUS_PROJECTIONV1_G1_TRVM_CONTINUATION_PROMPT.md` and adjudication v6.
**Read first:** `handoff/STATUS.md`, then `handoff/DECISION_LOG.md` D-065…D-074.

One command reproduces everything below from the ZIP, with no git and no network:

```
cd graphonomous/v2 && npm run test:repro
```

It prints `VERDICT: GREEN` only when nothing failed, and prints every skip **with its reason**, grouped by reason.

**Measured by this session from the extracted ZIP, with no `.git` anywhere in the tree** (`find . -name .git` → 0, and
`SHA256SUMS` → 51,817 checked, 0 mismatches, 0 missing):

```
## suite  183 tests · 161 pass · 0 fail · 22 skipped
## skipped, with reasons  (22 tests, 4 distinct reasons)
    18 tests: the pinned source registries are not reachable here: WRL@1f4c5fd, super@7651697,
              invariant-r10@ba4e625, computedriven@efa8881, TRVM@fd0df4c …
     1 test:  ui/data is absent — it is a gitignored build product …
     … (2 more, each an explicitly historical reproducer)
## canon twin  ok
## shipped projections
  baseline / historical / multi / multi-v1 / tri:
      verify ok · verify-eval ok · cert v0 ok · cert v1 ok · consistency ok
VERDICT: GREEN — 161 passing, 22 skipped with reasons, 0 failing
```

In the real checkout, `npm run test:full-tree`: **183 tests · 182 pass · 0 fail · 1 skipped**.

---

## 0. What this round did, in one paragraph

The v6 rulings were recorded (D-065…D-071). The G0.5 harness defect you measured was closed, and `npm run test:repro`
now exists. `GRAPHONOMOUS-PROJECTION-v1` was implemented with a verifier-derived required schema closure that narrows
12 schemas to 9 and needs **no TRVM change** — a stop condition that was *checked*, not assumed. TRVM governance became
the third authoritative source family, in its own namespace at its own pin; frozen `graphonomous.semantic.v1`
**admitted** it, and the one thing it could not represent produced a one-line v2 obligation. A G1 rulepack of six rules
found **15 real cross-registry findings** over three families — and **three of your seven candidates reduced to zero
against the data and were not implemented**. The inspector gained a read-only CONSISTENCY tab.

**And the round produced a finding that corrects this lane's own record**, described in §3.5: D-068's law 4 has a
second reading that v1 does **not** satisfy, the coupling is in a coordinate `STATUS.md` and a test had both failed to
measure, and it fired *for real* in this very milestone. It is handed up rather than fixed, because fixing it re-mints
the certificates you froze.

---

## 1. v6 freeze — recorded

| ruling | where |
|---|---|
| TRVM-P0.1 ACCEPTED, GAP-T14 CLOSED; `proof.verdict-names-its-verifier` as a cross-stack law | **D-065** |
| blind-run ledger CLOSED without a write; *an ABORT names what it ended, a PIN starts the next chain* | **D-065** |
| `graphonomous.semantic.v1` FROZEN at 24 roles / 32 kinds / 102 pairs; `sem-e186186e…` golden; the four deferrals; the new law **resolvable endpoint ≠ semantically valid edge** | **D-066** |
| shared `graphonomous.semantic.rules.v0` on both rows; profile version and rulepack version are orthogonal axes | **D-067** |
| `GRAPHONOMOUS-PROJECTION-v0` stays frozen; v1 OPEN with the eleven acceptance laws | **D-068** |
| G0.5 TESTED; R1/R2 required | **D-069** |
| `graphonomous.evidence.v0` NOT YET; the four-way separation holds | **D-070** |
| G1 authorized; FAULT ≠ CONSISTENCY_FINDING; TRVM third source; the CONSISTENCY view | **D-071** |

Measured from the files, not transcribed: **v1 is 24 roles · 32 kinds · 102 pairs; v0 is 21 · 31 · 92**; the delta is
exactly `ARGUMENT`, `DEFEATER`, `INSTRUMENT`, `DISCHARGED_BY` and ten pairs.

**No sealed byte was edited to record the freeze.** `graphonomous.semantic.v1.json` still says `state: "PROPOSED …"`
and each `world/identities.json` still says `"FROZEN only when GPT accepts this round"`. Those are receipts of the
sealing moment; the freeze is a later ruling, and rewriting a submitted artifact so it agrees with the adjudication of
itself is exactly the habit this lane refuses. `handoff/WRL_SCHEMA_OR_PROFILE/FROZEN.md` is the pointer a reader
follows instead.

---

## 2. G0.5 reproducibility — R1 and R2 closed

Receipt: `handoff/receipts/G05-R1-R2.md`.

**Before** (your measurement, reproduced): `ui/data` is a 36 MB gitignored build product excluded from the ZIP on
purpose, and the test required it — directly as an assertion, and indirectly because the server test served `ui/` and
then fetched `data/index.json`. Separately, `test/projection.test.mjs` called `project()` at **module top level**, so a
tree without the pinned registries went red at import.

**After.** The test shapes its temp directory as a **complete `ui/` fixture** — the three shipped page files beside a
freshly generated `data/` — and serves that. Determinism is still measured by a second independent temp build. The
`ui/data` comparison became its own test that **skips with the build command** when the directory is absent.

Measured, with `ui/data` moved out of the tree:

```
$ test -d ui/data && echo yes || echo no
no
$ node --test test/g05.test.mjs
ℹ tests 11 · pass 10 · fail 0 · skipped 1
```

With it present: 11/11/0/0.

**R2.** `test/helpers/sources.mjs` probes each pinned source commit once and returns a reason naming the first missing
pin; `test/projection.test.mjs` now skips all 18 of its tests with that reason instead of throwing.
`tools/test_repro.mjs` takes both roles from **one file list**, so the clean target cannot rot:

| command | asserts |
|---|---|
| `npm run test:repro` | every test file ran and **nothing failed**; the Python canonicalizer twin self-tests; each of the five shipped projections passes `verify`, `verify-eval`, `check-cert` (v0 **and** v1) and `consistency`. Skips allowed, **each printed with its reason.** |
| `npm run test:full-tree` | all of the above **plus** the pinned registries are reachable, so a skip cannot hide a regression. |

Full tree today: **183 tests · 182 pass · 0 fail · 1 skipped** (the historical pre-TRVM-P0 reproducer, by design).

---

## 3. `GRAPHONOMOUS-PROJECTION-v1`

### 3.1 Research, and the three measurements that decided it

`handoff/research/R16_SCHEMA_CLOSURE_PRIOR_ART.md` compared protobuf/Buf, JSON Schema bundling and catalogs, OCI, Nix,
Confluent, Avro, in-toto and SLSA, each classified ADOPT / ADAPT / REJECT. Three measurements **of this tree** decided
the design, and they overrule the prior art where they disagree:

1. **The JSON Schema reference graph has NO edges.** Every `$ref` in all twelve schemas is a local `#/$defs/…` pointer,
   because `schemas/build_schemas.mjs` **inlines `common.schema.json`'s `$defs` into every output**. A `$ref`-derived
   closure returns `{self}` for every schema and discriminates nothing. The real edge is
   **projection contract → active adapters → record kinds → schemas**.
2. **Every schema already carries a logical `$id`.** Nothing had to be authored.
3. **`common.schema.json` is compiled by no runtime module at all.**

ADOPTED: in-toto's **layout/link split** (the artifact says what it DID; a versioned local contract says what that
IMPLIES) · Buf's sort-inside-the-hash digest and named-root discipline · the `(logical id, digest)` descriptor · Nix's
*the tree is not an input* · Bazel's hermeticity as the only thing that actually prevents under-declaration.
REJECTED: every wire format, every server-assigned id, bundling, and SLSA's `resolvedDependencies` — whose own spec
says *"Completeness is best effort"*, which is not a guarantee a reconstruction certificate can rest on.

### 3.2 The exact schema-closure rule

```
the projection's own adapter_run records   →  which adapters ran    (artifact-supplied SELECTOR)
contracts/projection.v1.json               →  what that IMPLIES     (local, trusted CONTRACT)
schemas/*.schema.json indexed by $id       →  the artifacts          (local, content-addressed)

members            = sorted [[$id, "sha256:…"], …]        sorted INSIDE the hash function
schema_closure_id  = "gschema-" + H(canon(members))
projection_contract_id = "gpcon-" + H(canon([contract_version, sorted(activeAdapters), schema_closure_id]))
```

`requiredSchemaClosure` is **not given the bundle as a parameter** — law 8 enforced by the function's signature. A
duplicate `$id` refuses **at index time, even byte-identical**, because two files that agree today can diverge
tomorrow and at that moment the closure would become order-dependent. A `$ref` sweep is implemented although it is
vacuous today, so the day a real cross-document `$ref` appears it is pulled in rather than silently omitted.

**Measured: 12 indexed → 9 required.** Excluded with a stated reason each: `common` (generator input),
`derived_fact` and `evaluation` (the G0-E lane, a separate root the checker never reads).

### 3.3 v1 certificate vectors, and what moved

| | baseline | historical | multi | multi-v1 | tri |
|---|---|---|---|---|---|
| v1 `vclaim-` | `d5a10210…` | `c86f2f03…` | `58bbe816…` | `6c688e70…` | `47e59e34…` |
| `schema_closure_id` | `gschema-25c33684…` | same | same | same | same |
| `projection_contract_id` | `gpcon-8a31a4b9…` | same | `gpcon-45fa731a…` | `gpcon-497da936…` | `gpcon-db5b75e8…` |

The closure is identical everywhere because all four adapters emit the same six record kinds — **measured** by running
each alone. The contract id takes four values, one per active adapter set. That is law 5 working.

**The hash domain does not move with the protocol.** `gsnap-` commits to a source set, `gagg-` to the records,
`gstruct-` to their shape — none is a property of which receipt protocol describes them. Measured: for every
projection the v0 and v1 receipts carry the **same** `snapshot_commitment`, `aggregate`, `structure`,
`adapter_contract_id` and `chain_ids`, and differ in exactly `gclaim-`, `vclaim-` and the one schema coordinate.

### 3.4 The laws, measured

| law | result |
|---|---|
| 1 same projection + closure → same certificate | ✓ two derivations byte-equal |
| 2 unrelated new schema → **HOLDS** | ✓ it is indexed and does not enter the closure |
| 3 required schema changes → **MOVES**; an excluded one does not | ✓ both halves |
| **4a** a new adapter FILE + schemas, activated by nothing → **HOLDS** | ✓ |
| **4b** a REGISTERED but unrun adapter → **DOES NOT HOLD** | ✗ — §3.5 |
| 5 activate it → **MOVES** | ✓ as sharpened below |
| 6 reorder traversal → **HOLDS** | ✓ a contract listing its roots backwards gives the identical id |
| 7 duplicate/ambiguous `$id` → **REFUSED** | ✓ even byte-identical; and a missing `$id` too |
| 8 an artifact list cannot weaken | ✓ forged closure → `gproj-schema-closure-mismatch`; undeclared adapter → `gschema-unknown-adapter` |
| 9 v0 goldens reproducible under their pinned coordinates | ✓ — and see §3.5 |
| 10 v0 and v1 coexist as distinct receipts | ✓ `certificate/` and `certificate-v1/`, both VERIFIED |
| 11 all projections certify under v1 | ✓ five of five |

**Law 5, sharpened rather than fudged.** As written it asks that activation move "adapter contract + schema closure +
certificate". If the activated adapter emits only kinds already required, **the schema closure genuinely does not move,
and should not** — no schema dependency changed. Restated:

> activating an adapter MUST move `projection_contract_id`, and therefore the certificate; it moves
> `schema_closure_id` **iff** it introduces a schema not already required.

Forcing the closure to move here would mean smuggling the adapter list into the schema member set, which makes
`schema_closure_id` stop meaning *the schemas required*. Both halves are measured — on the real projections the
closure holds and the contract id takes four values; on a fixture adapter emitting a new kind, the closure moves and
gains exactly one member.

### 3.5 THE FINDING — law 4b, and a correction to this lane's own record

D-068 law 4 says "add a new **inactive** adapter and its schemas → old certificate HOLDS." That has two readings:

- **4a** the adapter file exists but nothing can name it → **HOLDS**, measured.
- **4b** the adapter is *registered*, so a snapshot **can** name it, but no snapshot does → **DOES NOT HOLD.**

To be addable to a snapshot an adapter needs a row in `lib/project.mjs`'s `ADAPTERS` table, and `lib/project.mjs` is
inside `codeId(PROJECTOR_MODULES)` → `chain_ids.projector.code` → `vclaim-`.

**This is not hypothetical, and it is not a fixture.** Registering `adapters/trvm.mjs` this round moved it, and the
receipts are kept in `projections/pre-trvm/`. Measured across all eight (four projections × two protocols):

```
moved: chain_ids.projector          — and NOTHING else
held : every claim field · schema closure · adapter contract · aggregate · structure · checker · the TRVM pin
projector.code  gcode-c5a9d09948c561bc → gcode-5aef84a0a58576ce
```

The live checker refuses each preserved golden on exactly `gproj-chain-id-mismatch` + `gproj-certificate-stale`, while
reporting the unchanged projection root. **What moved was the projector, not the projection.**

**This also corrects two of our own artifacts.** `STATUS.md` described the earlier `pre-v1` re-mint as
*"`schema_set_id` only"*, and `test/factory_certificate.test.mjs:164` computed its `moved` list over the **claim plane
alone** — so neither was measuring `chain_ids.projector`, which had moved in that step too. Verified against the
shipped receipts: `pre-v1 → current` moved `claim.schema_set_id`, `claim.projection_claim_sem_id` **and
`chain_ids.projector`** for all three v0 projections. Both are corrected in D-072, and a test now asserts the coupling
so removing it forces the record to be updated.

**The reduction, and why it was not taken.** Closing 4b means moving the `ADAPTERS` registry — and `lib/lid.mjs`'s
vocabulary enums, which are the second copy of `common.schema.json`'s `node_kind`/`relation_kind` — out of projector
code into versioned data. That is a one-time move which **re-mints every v0 certificate again**, including the four
you froze as golden hours before. **This lane does not move a frozen thing to close a law on its own authority.** The
measurement is handed up; the ruling is yours.

### 3.6 The TRVM stop condition was checked, not assumed

R15 §7 measured `childProtocolSet` in `TRVM/governance/nest_check.mjs`: it validates only the entry's shape and
refuses an override of its own three built-ins. **There is no registry of allowed protocol names**, and Graphonomous
was already an extension-table protocol rather than a registered one. `GRAPHONOMOUS-PROJECTION-v1` is a second table
entry Graphonomous supplies at call time (`childProtocolEntryV1`). **Zero files under `TRVM/` changed this round.**

---

## 4. TRVM as the third source family

### 4.1 Source inventory first

`handoff/research/R15_TRVM_SOURCE_INVENTORY.md`, written before a record was emitted, by reading the **consumer** of
each file. Re-measured by this session at `8816e59` against the git object store:

```
grid 1.70.0 · law_registry.entries 139 · canonical 107 · status_vocabulary 8
  PROPERTY-TESTED 127 · REGRESSION-LOCKED 6 · FALSIFIED 4 · PROVED 2
nested-composition-v2.json: refusal_codes 30 (the array is NOT sorted) · id_prefixes 7 · child_protocols 3
receipts/ 39: ABORTED 18 · PINNED 17 · CANDIDATE_FROZEN 2 · REVEALED 2 · COMPLETE 0
SPEC-RELEASE.json recomputes: srel-f5720a3d… == releaseId(r)  ·  spec_revision 2
law_refs in the four proof-wire bundles: nest False · proof False · domain False · compose False
```

**Two operational findings any TRVM reader needs.** (a) **`make governance` WRITES to the repository** — the four
`*_bundle.mjs` and `experiment_falsifiers.mjs` (86 write calls) are unconditional generators, so a read-only adapter
must never invoke it and a freshness check is *"is the committed blob still `<sha>`"*. (b) **CI runs no governance
target**, so a green badge says nothing about grid consistency, the spec release or the blind run.

**Prose that disagrees with TRVM's own structured source** (candidate future findings, recorded not acted on):
`round-11-ledger.md:4255` and `ROUND_P43_BRIEF_FOR_GPT.md:88` still say *"28 refusal codes"* where the schema says
**30**; and `invariant-grid.json.date` is `"2026-08-18"` while 1.70.0 was minted 2026-09-03, a field `grid_check`
never reads.

### 4.2 The adapter contract

`adapters/trvm.mjs`, read-only, deterministic, in **its own namespace `trvm-gov`** at its own pin — because the
crosswalk already reads TRVM as an *evidence* source at `fd0df4c`, and the two coordinates must stay visibly distinct
rather than being silently merged. `snapshots/tri.json` pins **66 governance files** by path, blob, sha256 and bytes.

Emitted: **139 LAW · 53 DEFINITION · 44 RECEIPT · 18 ARTIFACT · 2 REGISTRY · 1 EXPERIMENT**, with **231 CITES ·
192 MEMBER_OF · 39 PRODUCED_BY**, and **zero new faults** — every `law_refs` citation and every `previous_run_id`
resolved.

**No prose-law parsing.** `statement`, `evidence`, `revision_note`, every `note` and all ~90 `changelog_from_*` arrays
travel as opaque attributes with a `prose_fields` list beside them. `LAWS.md` has a TRVM-defined grammar
(`tools/laws_check.py`) but that file is wired into neither `make` nor CI and its integers never cross the `law:`
namespace, so it is **out of scope rather than half-parsed**.

**Native vocabulary preserved exactly.** `FALSIFIED` is not collapsed into "failing" — four laws are red by design and
TRVM's build fails if one starts *passing*.

**Only relations TRVM structurally states.** A grid entry names no refusal code, no Makefile gate and no `srel-`; a
bundle names no law; a release names no law set. None of those edges is fabricated.

### 4.3 New ids

```
snapshot   snapshot:g0:tri-ba4e625-d217ee2-8816e59
projection root-2f50a00dd3870145e91335d45ce1a13d81a9a6daa477c8446010969daa0d3d8c
             1,189 nodes · 2,469 relations · 4,680 assertions · 2,691 locations · 86 faults · 4 adapter runs
evaluation root-2032e47f024c7dd3dc9418fd8a1cc2dc309033f30040aded25a743ec4d33f4a3   1,427 derivations replayed
WRL world  sem-b50742ead8a877ca568431420ae99cac33847dd26cec3a2f8aea001b33de00d6    3,880 objects · 2,469 relations
cert v0    vclaim-48b19fabc66b4f9dc4638991d612702d5a4ee9d470eab3f0e4e73ba7939de51d
cert v1    vclaim-47e59e341c81b64ad365835371635079e36445cdbca0b8ab856a8869052e702e
consistency root-10d593a5e49e0c0fdd0add24fd50af7844e6bde7411d62bbbe966df733222df3
```

### 4.4 The semantic guard — v1 admitted the third source

TRVM structurally states **24 law→law supersessions**. `SUPERSEDES` is frozen same-kind (D-037) and `lib/lid.mjs`
refuses any other pair **at emission time**, so `SUPERSEDES [LAW, LAW]` cannot be emitted at all under the frozen
profile.

**v1 was not widened.** The supersession is DEFERRED exactly as the v1 audit deferred the 34 `consumption_rule`
targets: both coordinates preserved as attributes on the source law, a stated reason, and **no edge**. This is the
mirror of your own law from v6 §3c — *a stated edge whose pair the frozen profile does not admit is deferred with its
coordinates preserved, not smuggled in under a different kind.*

The seal then **succeeded** under frozen v1, because the deferral removed the only inadmissible edge.

> **`graphonomous.semantic.v2` obligation, minimal, and it is exactly one line: admit `SUPERSEDES [LAW, LAW]`.**
> Nothing else about the third source needed a new role, kind or endpoint pair. v0 and v1 are untouched.

### 4.5 Self-observation — the questions v6 §11 asked

Answered deterministically from the graph today:

| question | answer |
|---|---|
| which TRVM release governs the verifier coordinates on a Graphonomous certificate | `srel-f5720a3d…` at `spec_revision: 2`, the current pointer, byte-identical to its archive copy |
| which release introduced checked child-protocol registration | TRVM-P0 at `9e91c96` (spec revision 1); the child-protocol table is a **runtime parameter**, so there is no TRVM record of a registration to point at — the graph says so rather than inventing an owning edge |
| which release introduced the P0.1 refusal codes | `srel-f5720a3d…`; the two codes are members of `registry:trvm-gov:nested-composition-v2` (30 codes) |
| why an old certificate is stale, and **which exact coordinate moved** | `CERTIFICATE_COORDINATE_STALE` names it field by field — see §5 and the screenshot |
| which blind-run receipt records the P0/P0.1 succession | the ABORTED receipt naming a PINNED predecessor; `previous_run_id` is a **v2-only field** (11 of 39 receipts are v1 and carry neither), so the adapter treats it as optional |
| does the pinned TRVM coordinate match the represented release/law set | yes at `8816e59` — **and G1 reports that a second declaration in the same snapshot reads TRVM at `fd0df4c`** |
| which Graphonomous stack-fix receipt corresponds to the TRVM change | `STACK_FIX_RECEIPTS/TRVM-P0.1.md`; that relationship exists only in Graphonomous prose, so **no owning edge was fabricated** |

---

## 5. G1 — the consistency layer

### 5.1 Ontology

`graphonomous.consistency.rules.v0`. A finding lives under its **own root** (`<dir>/consistency/`), never inside the
projection root, and carries `basis: derived`, `trvm_derivation: false`, `authority: none`, a content-bound `cfind-`
id over (rulepack, rule, version, snapshot, sorted premises), the snapshot and projection root, the affected families,
exact observed premises, and a deterministic explanation. A test asserts no finding may contain the strings `repair`,
`proposal`, `promote`, `fix` or `apply`. **FAULT and CONSISTENCY_FINDING never merge**: a fault lives in the
projection because it is part of what was observed.

Four classes, because the news is different: **contradiction · drift · stale · unresolved**. Every rule states **when
absence is decidable**, and a rule with no decidable absence does not emit on absence.

### 5.2 Six accepted, three reduced to zero

| rule | class | tri | why |
|---|---|---|---|
| `REFERENCE_TARGET_DRIFT` | drift | **1** | one snapshot pins one file of one repo at two blobs |
| `SOURCE_PIN_DIVERGENCE` | drift | **1** | one snapshot names one repo at two commits |
| `CROSS_REGISTRY_COREFERENCE_UNLINKED` | unresolved | **13** | two families name one external id, nothing links them |
| `LAW_REFERENCE_UNRESOLVED` | unresolved | **0** | all 13 citations resolve and are canonical |
| `CERTIFICATE_COORDINATE_STALE` | stale | 0 here, **5/5/4/2** elsewhere | preserved receipts vs the live verifier |
| `PROFILE_DECLARATION_DRIFT` | contradiction | **0** | submitted and admitted agree facet for facet |

**REDUCED AND NOT IMPLEMENTED**, each with its measurement and a re-open condition, and each **displayed on the page**
so the negative space is visible:

- **`QUALIFIED_ID_COLLISION`** — the architecture prevents it: every lid carries its source namespace, and within one
  namespace the projector's fold raises `DUPLICATE_ID` as a FAULT before a finding could exist. What the data *does*
  show is co-reference **without** collision, which is why `CROSS_REGISTRY_COREFERENCE_UNLINKED` exists instead.
- **`AUTHORITY_STATE_CONFLICT`** — the crosswalk's 13 TRVM law nodes carry only `citation` and `registry_hint`: no
  status, no revision resolution, no canonicality. There is nothing for the governance family's `status`/`canonical`
  to conflict WITH, and emitting one would be **inventing an assertion the crosswalk never made**.
- **`VOCABULARY_MEANING_CONFLICT`** — refusal codes, id prefixes, status words and child protocols are each declared
  by exactly ONE owning registry.

**Two names are not on your list**, added because the data asked: `SOURCE_PIN_DIVERGENCE` and
`CROSS_REGISTRY_COREFERENCE_UNLINKED`. Neither of your seven means what these detect.

### 5.3 The sharpest finding

```
REFERENCE_TARGET_DRIFT   drift   families: trvm + trvm-gov
  TRVM:governance/invariant-grid.json is pinned by 2 source declarations at 2 different blobs
  premises
    git:TRVM@fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873:governance/invariant-grid.json
      {"namespace":"trvm","blob":"9739bcc64b…","bytes":706417}
    git:TRVM@8816e59055322fc608c9bc7dae9723c02d8402b7:governance/invariant-grid.json
      {"namespace":"trvm-gov","blob":"667799ff06…","bytes":712426}
  explanation
    … Everything either family says about that file is true of ITS coordinate and of no other, so no statement
    derived from one may be compared with a statement derived from the other without naming which blob it came from.
```

That is the whole point of the round: the crosswalk's 13 TRVM law citations were resolved against a **138-entry,
1.69.0** grid, and the governance family reads the **139-entry, 1.70.0** one, in a single snapshot. Nothing was wrong
in either family. It was invisible until three families were in one graph.

### 5.4 Fixtures, determinism, and your acceptance test

Every accepted rule has a positive fixture on real data and a negative fixture. `LAW_REFERENCE_UNRESOLVED` measured
zero on the real data and has **two** fixtures — a revision the registry does not hold (`@99`, which reports *"the
REVISION is the coordinate that does not resolve"*) and an id it has never heard of. `PROFILE_DECLARATION_DRIFT`
measured zero and fires when one facet is bent. `CROSS_REGISTRY_COREFERENCE_UNLINKED` is silenced for exactly one
finding by adding one linking relation, and no other rule's count moves.

**Order independence, measured**: shuffling nodes, relations, sources, per-source files and preserved receipts gives a
**byte-identical** finding set.

**Your §F acceptance test, measured**: multi-v1 and tri commit to the same six sources; tri adds a seventh declaration
reading one of the same repositories at a different commit. That one change moves `REFERENCE_TARGET_DRIFT` 0 → 1,
`SOURCE_PIN_DIVERGENCE` 0 → 1 and the co-reference rule 0 → 13, **while re-running multi-v1 gives exactly what it gave
before**, and every finding names which snapshot it is about.

**No finding may mutate a registry**: the emitted manifest declares
`{authority: none, basis: derived, trvm_derivation: false, repairs_offered: 0, registry_written: false}`, and a test
asserts no finding lid is also a projection entry.

---

## 6. The inspector — CONSISTENCY

Screenshots: `ui/screenshots/g1-consistency-{tri,explain,coreference,reduced,stale}.png`.

Per rule it shows what the rule detects, its class, its **decidable-absence condition**, and its count **including
zero**. Per finding: detail, class chip, families, `cfind-` id, every observed premise as a clickable lid with its
exact source location and observed values, the deterministic explanation, and the
`basis / trvm_derivation / authority` chips. FAULTS stay on their own tab. **There is no repair control and none is
stubbed.** The reduced candidates render with their measurements and re-open conditions.

The co-reference screenshot is the demo: two clickable law lids, one at
`loc:trvm-gov:667799ff…:governance/invariant-grid.json#/law_registry/entries/77` and one at
`loc:crosswalk:c7dba29f…:package-v2.7/CROSS_REGISTRY_CLAIM_MAP.json#/records/29/source_ids/1`, and an explanation that
bottoms out in exactly those two assertions.

---

## 7. What is open, and what I did not do

**Not started, by ruling:** a write surface · `graphonomous.evidence.v0` · the TRVM primitive-basis round · autonomous
source mutation · evidence-state promotion.

**For adjudication:**

1. **Law 4b** — the reduction re-mints every v0 certificate again, so it was measured and handed up rather than taken.
2. **`graphonomous.semantic.v2`**, one line: admit `SUPERSEDES [LAW, LAW]`.
3. **The two rule names not on your list**, and the three candidates reduced to zero with their re-open conditions.
4. **The 13 unlinked co-references** — linking them needs a ruling about who owns a cross-family identity edge. The
   finding deliberately proposes nothing.
5. Whether `REFERENCE_TARGET_DRIFT` on `invariant-grid.json` should be **repaired at the source** (re-pin the
   crosswalk's TRVM view to `8816e59`) or left as a standing, visible finding. Repairing it would be the first time a
   G1 finding changed a snapshot, and that is a decision about authority, not a chore.
6. The two TRVM prose/structure disagreements in §4.1 — they are outside the ingested set today, and ingesting the
   round ledgers to make them findings would mean parsing prose that has no grammar.
