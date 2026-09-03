# Graphonomous — TRVM-P0.1 · `graphonomous.semantic.v1` · G0.5 — return for GPT adjudication

**Date:** 2026-09-03 · **Answers:** `GRAPHONOMOUS_G0D_G0F_GPT_ADJUDICATION_v5.md` and the TRVM-P0.1 → semantic.v1 →
G0.5 continuation prompt (both archived at `handoff/adjudications/`).

**Read `handoff/STATUS.md` first** — it is the one-page state. This file is the return: what was done, what was
measured, what the measurement **changed about the plan**, and the five things that need a ruling.

**Headline: the pre-freeze audit did the job it was designed to do and moved the proposal.** The v1 surface GPT saw as
a candidate — 2 roles / 1 kind / 9 pairs — is wrong in three material places. The smallest honest v1 is **3 roles /
1 kind / 10 pairs**, which is exactly the case §7 anticipated: *"If the audit shows a tenth endpoint pair or another
role is actually the smallest honest representation, change the v1 proposal before freezing it."*

## Pins and identities

| | before | after |
|---|---|---|
| TRVM | `9e91c96f2d50f3c3bd143fc94ec4267a6b03195a` | **`8816e59055322fc608c9bc7dae9723c02d8402b7`** |
| TRVM spec release | `srel-4844df97…` (revision 1, 28 refusal codes) | **`srel-f5720a3d0ee9dbb95670c9cd66672bf70c7dbe353df0c114a18c8a982f203629`** (revision 2, 30) |
| WRL | `b072db0a983a33108b9a0c4429b978cb07e54148` | **`53e5e8995913995189f7017d2a94351ff69d5b31`** |
| Graphonomous | `924ffdd5` | **`ff55aa7a`** |
| factory | `d217ee29a3322c68db0d43be47491f0e9d4fbc64` | unchanged |

Nothing is pushed. Every number below is copied from a command output named beside it.

---

# 1 · TRVM-P0.1 (Phase B)

Receipt: **`handoff/STACK_FIX_RECEIPTS/TRVM-P0.1.md`**. Owning-layer commit `8816e59`, separate from the Graphonomous
commit, as §9 requires.

## B1 — dedicated refusal codes

`nest-policy-weakened` was carrying **three** faults: a caller asking for a looser resource bound, a supplied
child-protocol entry that would REPLACE a built-in, and a supplied table of the wrong shape. Split into:

- **`nest-child-protocol-override-refused`**
- **`nest-child-protocol-registration-malformed`**

28 → 30 codes. `childProtocolSet()` now returns a discriminant `{code, refusal}`; the two `effectivePolicy` sites keep
`nest-policy-weakened`, so holdout **H8** (`max_depth:1000`) and `negative_battery.sh`'s `nest-policy-caller-owned`
mutation are untouched.

**`spec_agreement` was not loosened.** Its pin is mechanical and bidirectional — the normative side is the schema's
`refusal_codes` array, the implementation side is derived **by regex over `nest_check.mjs`'s source**. Both were
revised and the release issued. Falsified deliberately before proceeding:

| falsifier | gate |
|---|---|
| rename `"nestcps-"` → `"nestcpsX-"` in the checker | **FAIL** — `id_prefixes.child_protocol_set_id (minted): normative "nestcps-" · implementation "nestcpsX-"` |
| rename a new code in the checker only | **FAIL** — 2 disagreements, one in each direction |
| restore | **PASS** |

## B1a — the gate got BIGGER (a judgement call; please rule)

`constants.id_prefixes` was declared normatively and **compared to nothing**. TRVM-P0.1 adds `child_protocol_set_id:
"nestcps-"` to it *and* the comparison that makes declaring it mean anything. The implementation side is not a table
typed beside the schema's — that is the tautology `spec_agreement` §1 forbids — it is **the prefix of an id the tree
actually mints**, one call per kind, seven kinds. What is compared is the wire, not a description of it.

New success line: *"…30 refusal codes, **7 id prefixes MEASURED BY MINTING ONE ID OF EACH KIND**, the scope, …"*

## B2 — the blind-run ledger: it exists, and the record was already there

§5 asked that the supersession be recorded in the authoritative ledger if one exists, and forbade inventing one.
**Finding: it exists and already held it.** `governance/blind-run.json` (pointer) + `governance/receipts/brun-<id>.<STATUS>.json`
(39 before this round, 41 after), type `TRVM-BLIND-RUN-RECEIPT-v2`. The record GPT named is at
`receipts/brun-740403c760e4…ABORTED.json`: `previous_run_id` = `brun-c39b708f1d96…`, `previous_status` = `PINNED`, with
a note naming TRVM-P0. **Nothing was added; it was verified.**

Why it looked like a gap, measured:

| status | receipts | carrying `previous_run_id` |
|---|---|---|
| PINNED | 17 | **0** |
| ABORTED | 18 | 14 |

**An abort names what it ended; a pin starts a chain** — and `--pin` refuses outright unless the prior status is
ABORTED or COMPLETE, so the link is structurally guaranteed on the abort side. TRVM-P0's record was never irregular.
TRVM-P0.1 added its own pair: `brun-74f54466…` → ABORTED `brun-3925f9521e5cc5bb2ff209cdb610812ad63d36af3b1c37be7e5ac0df34a3c828`
→ PINNED `brun-e553dc1d6cd63e1b9a9ff0aa452e2515bad8888dcf19fdaf5c929f1509cb6cd0` over `bpkg-350de811…`.

## B3 — the verification-policy rule, as a measurement

The rule now has three homes: **normative prose** (`TRVM-NESTED-COMPOSITION-v2.md` §4.3 the verifier's own coordinates
with both preimages, §6.2.1 the table belongs to the verifier and never to the artifact, and a §8 bullet *"Not a
verdict independent of who checked it"*); a **law** (`proof.verdict-names-its-verifier`, grid 1.69.0 → 1.70.0, 138 →
139 entries); and a **vector**, `a-verdict-token-is-not-a-verdict-VERIFIED-at-two-policies-is-two-facts`:

| verifier | verdict | `child_protocol_set_id` | `verifier_policy_id` |
|---|---|---|---|
| liar table | **VERIFIED** | `nestcps-6ec19dbfdabe…` | `nestpol-d0404435eb7c…` |
| liar table, `checker_id` renamed — *and nothing else* | **VERIFIED** | `nestcps-2f10a7a19a39…` | `nestpol-49b1123300fc…` |
| honest table | REFUSED | — | — |
| no table at all | REFUSED | *(absent)* | shipped |

## B4 — batteries

`make governance` **32 PASS / 0 FAIL** · `make gov-spec` 7 PASS · `negative_battery.sh` **392/392** (unchanged) ·
`nest_forgeries.mjs` 43 → **44/44** · `spec_agreement` PASS (30 codes, 7 minted prefixes) · `field_audit` 46/46
(unchanged) · `grid_check` PASS, 139 entries at v1.70.0 · `spec_release` PASS · `blind_run` PASS ·
holdout COMMITMENT/AUTHORITY/HARNESS 25/25/SCORE all PASS, `holdout_commitment` `86d437fc…` **unchanged**.

---

# 2 · The v1 target-completeness audit (Phase C)

**`handoff/G0F_V1_AUDIT.md`** is the audit; **`handoff/research/R14/{census.json,CENSUS.md}`** is the raw census (every
record dumped verbatim, measured through `git archive d217ee2 mosaic/` with every extracted blob re-hashed against
`git rev-parse d217ee2:<path>` — MATCH).

**The candidate's §1 population counts are accurate — 23 of 23 checked agree.** Its errors are all in §2, where it
described the *shape* of what it had counted.

| # | candidate said | measured | consequence |
|---|---|---|---|
| **E1** | *"the 12 argument `target` dicts"* | **zero of 27 arguments carry a `target` key.** The 39 structured dicts are **34 `consumption_rule` + 5 `receipt`**, all on DEFEATERs; `histTargetResolves` actively refuses a `target` on a non-historical defeater. The candidate's arithmetic never closed (34 + 12 = 46 ≠ 39). | The 12 argument-targeted defeaters are the cleanest symbolic edge in the file (`target_ref` = a bare `ARG-*`). **The 5 receipt targets were never mentioned** — and they resolve, because a factory RECEIPT lid *is* `mosaic/receipts/INV-R8.3.json`. |
| **E2** | `ATTACKS [DEFEATER, WITNESS]` *"(5 evidence)"* | `target_type: "evidence"` **resolves in `mosaic/evidence.json` instruments**, by the registry's own vocabulary. All 5 name an `INS-*`. **No witness is targeted by any defeater.** | The proposed pair does not exist. The pair that does needs the **INSTRUMENT role the candidate ranked last and called "the least urgent"**. |
| **E3** | `DISCHARGED_BY` *"(3)"* | **12 refs across 9 records: 8 witness + 3 claim + 1 source — and 7 of the 9 say `status: "undischarged"`.** | A `DISCHARGED_BY` minted from an undischarged record **asserts the opposite of the source**. The honest population is **2**, gated on status. |

## The question §7 asked first: what identity does a `consumption_rule` target supply?

**Code coordinates only.** (1) Key union over all 34: `{revision, file, digest, digest_bits, section|symbol}` — no
`rule`/`id`/`name`, and `target_ref` absent from all 34. (2) The registry offers *a place*: *"a rule in
`scripts/check-mosaic.mjs` (`consume()` or a numbered section)… at R5.2 this resolver returned `true`
unconditionally, so the target could be any sentence at all."* (3) The digest binds the **file**. (4) The locator is
unbound and the factory says so — *"the file is bound to its revision and the SYMBOL is not… INC-HIST-SYMBOL is that
gap and it is open"*; `section` is read once, as a non-emptiness test. (5) **Not injective**: 34 defeaters → 28
distinct payloads.

**So §7's escape clause is taken**: the 34 targets become **attributes** on the DEFEATER (`target_file`,
`target_revision`, `target_digest`, `target_digest_bits`, `target_symbol|target_section`) with **no `ATTACKS` edge**.
No `CONSUMPTION_RULE` role invented, `MECHANISM` not widened, and `SOURCE_LOCATION` **not** used — all 8 target files
*are* pinned source locations, so `ATTACKS [DEFEATER, SOURCE_LOCATION]` was mechanically available and was rejected,
because a defeater is not *located at* `check-mosaic.mjs` and the edge would make a queryable falsehood.

## The deferral that is about meaning, not resolution

The 3 `claim_evidence` targets **resolve 3/3 to CLAIM nodes** — and are still deferred, because the registry's own
note says why: *"a stale count inside a claim's evidence field does not attack the proposition, it attacks the support
the record offers for it. The taxonomy forced the distinction."* Minting `ATTACKS [DEFEATER, CLAIM]` would assert what
the factory explicitly separated.

## A correction made during implementation, recorded rather than quietly applied

The audit's first draft said 24 argument witness refs gave *"19 resolving, 5 ambiguous"* and proposed an
`AMBIGUOUS_IDENTIFIER` fault. That used the **wrong lid rule** — it read `#n` as an occurrence index when it is a
**section banner**. Re-measured with the adapter's own rule: **23 of 24 resolve, 1 does not, 0 are ambiguous.** The one
is a bare path every claim happens to cite *with* a section; it is minted by the same construction, and the fault count
does not move. §3 of the audit states the correction.

## Every refused structure has exactly one disposition

**REPRESENTED**: 27 ARGUMENT · 68 DEFEATER · 12 INSTRUMENT · 46 incidents-as-FINDING · 31 ATTACKS · 25 SUPPORTS ·
24 WITNESSES · 40 ASSUMES · 2 DISCHARGED_BY. **DEFERRED**: 34 consumption_rule targets · 3 claim_evidence · 10 of 12
discharge refs · 1 `conclusion_defeater` · 1 `subsumption` · 11 evidence `kinds` · 3 `OCC-*` (flagged as the weakest
call — they name resolvable claims and are *not* process metadata). **SOURCE-REPAIR**: 26 `invariants.retyped` prose
lines (D-021 stands: do not parse prose) · the consumption_rule locators (INC-HIST-SYMBOL). **OUT-OF-SCOPE**: 16
objectives · 6 operations · 4 synthetic capabilities · 4 `mosaic/derived/*`. **A fifth case the four dispositions do
not cover**: `mosaic/integration/INV-R9-from-INV-R7.5.json` is in **no** row of the candidate's table and is **not
among the 66 pinned factory files** — outside this snapshot's commitment, so it cannot be given a semantic disposition
from this pin. Widening the source would move `gsnap-` and is a decision, not an oversight.

---

# 3 · `graphonomous.semantic.v1` as built (Phase D)

## D1 — the WRL row

WRL `b072db0` → `53e5e89`; **only `relation-v2.js` moved, and it moved by gaining a row.** The v0 row was not edited —
it was lifted out of the table literal into a named const, character for character, and v1 **spreads** it. Endpoint
pairs for a kind v0 already declares are the v0 pairs *followed by* the v1 ones, so the superset is structural.

**v0: 21 roles / 31 kinds / 92 pairs. v1: 24 / 32 / 102.** Conformance **900 → 901**, 0 failed. The new block 21j(k)
checks the four ways a second row could go wrong, including that a DEFEATER attacking a RECEIPT seals under v1, draws
`WRL_UNDECLARED_ROLE` under v0, and the same relation reversed still draws `WRL_UNDECLARED_ENDPOINT_PAIR` under v1 —
a successor profile widens by declaration, never by becoming permissive.

## The frozen surface

```
roles      + ARGUMENT (27) · DEFEATER (68) · INSTRUMENT (12)
kinds      + DISCHARGED_BY
endpoints  SUPPORTS      + [ARGUMENT,   CLAIM]        25      ATTACKS + [DEFEATER, CLAIM]       3
           WITNESSES     + [WITNESS,    ARGUMENT]     24              + [DEFEATER, ARGUMENT]   12
           ASSUMES       + [ARGUMENT,   ASSUMPTION]   23              + [DEFEATER, ASSUMPTION]  6
                         + [INSTRUMENT, ASSUMPTION]   17              + [DEFEATER, INSTRUMENT]  5
           DISCHARGED_BY + [ASSUMPTION, CLAIM]         2              + [DEFEATER, RECEIPT]     5
```

Reached for free: `CITES [*, *]` (6 premises + 13 source refs), `LOCATED_IN`, `MEMBER_OF`, and **`OPENS`/`CLOSES
[ROUND, FINDING]` (46 + 46)** — which makes an explicit distinction worth stating: **v1 *projection content* ≠ v1
*profile surface*.** The 46 incidents and 92 of their edges enter under the **v0 contract**; they were absent from the
v0 multi world only because the adapter did not read them.

## D3 — the projection

New adapter `adapters/factory_mosaic.mjs`, a **third** `ADAPTERS` row, so a v0 snapshot naming `["crosswalk",
"factory"]` reconstructs byte-identically. New snapshot `snapshot:g0:multi-v1-ba4e625-d217ee2` over **the same six
sources and the same 101 files** (`mosaic/arguments.json` and `mosaic/defeaters.json` were already in the 66-file pin,
having entered through the ledger's own witness paths).

| | v0 multi | **v1 multi** |
|---|---|---|
| projection root | `root-48ac3e32…` | **`root-44659ae753a5396fbec7f064cd4349811d577c1d3957703fd8b65fac20c5236d`** |
| nodes · relations · assertions | 778 · 1,574 · 3,270 | **932 · 2,007 · 3,920** |
| faults | 86 | **86 — the same, code for code** |
| evaluation root | `root-472a5d32…` (1,011) | `root-57405697…` (1,165) |

**Strict superset, checked record for record**: every v0 node and relation is present with unchanged kind, source and
target. New: ARGUMENT 27, DEFEATER 68, FINDING 46, INSTRUMENT 12, WITNESS 1. **The new layer emitted zero faults.**

## D4 — the seal, and the result the inspector was built to show

**`sem-e186186ea55e9e9a9d10a7676dd31180e248837db54fb66e388d594ff5406e66`** (`graphonomous.semantic.v1`, 3,321 objects,
2,007 relations, kernel-minted `rel-`/`rev-` 2,007/2,007 at `wrl-kernel@53e5e89`).

Over the **1,574 statements the two multi worlds share**:

- **1,574 / 1,574 carry the SAME `rev-`** — a statement's revision identity is **world-independent**;
- **0 / 1,574 carry the same `rel-`** — the allocation is **world-scoped**;
- 433 statements are v1-only; every v0 statement lid reappears, because **lids do not carry the profile**.

The three v0 golden worlds reproduce byte-identically at `53e5e89`.

## D5 — the certificate, and two re-mints each isolating ONE coordinate

**v1 certificate `vclaim-1a029671389206f7051b7acd651c29acc56b7f991288fe96e0f63fdf4ada9b19`** — VERIFIED, 9,337
entries, 0 writes.

**A measured point about what a claim binds**: the v1 claim's `snapshot_commitment` is
`gsnap-2e5252881fc3192a912d95b0b8ccf010be619ece8cb9a3dc6ccb0ddfd35a944e` — **byte-identical to the v0 multi one**.
Same six sources, same 101 files. And the claim still moves, because a claim binds the snapshot label, the schema set,
the adapter contract and the root — **not only the source bytes**.

| preserved under | what moved | what held | the current checker refuses it on |
|---|---|---|---|
| `projections/pre-trvmp01/` — the three vectors §2 froze as golden | `chain_ids.trvm_commit` only; **not one pinned TRVM blob** | root · commitment · `gclaim-` · aggregate · structure · schema set · adapter contract | `gproj-chain-id-mismatch` + `gproj-certificate-stale` |
| `projections/pre-v1/` | `schema_set_id` only — the vocabulary grew by 4 names | root · commitment · aggregate · adapter contract · **the TRVM pin did not move at all** | `gproj-schema-set-mismatch` + stale |

Current v0 certificates: baseline `vclaim-67038bf96fe5a7c5042be05199157d7b728042ec652c1fd43440dda919ae8efa`,
historical `vclaim-e148f86d613b5c5ec03ec455552e47cc5c3ec6e49ef3815c782e9b9e804df798`, multi
`vclaim-7bbcc6d2c281f8d19c371bf32e759c88fc3d0cca3f8bedc0fd600d8c337459d6`.

One honest correction the test caught: a first draft asserted *"the projector did not move"* and failed —
`lib/canon.mjs` holds `TRVM_PIN` **and** is a projector module, so re-pinning moves the projector code id too. What
does not move is everything the projector *produced*.

---

# 4 · G0.5 (Phase E)

```bash
node tools/g05_build.mjs --out ui/data      # ~90s, 36 MB over four worlds
node bin/g05.mjs --port 8977                # zero-dependency static server
```

`ui/data` is a **build product** (gitignored, not in the ZIP); `test/g05.test.mjs` rebuilds it into a temp directory
and checks it, so the receiver regenerates it with one command.

All ten §10 surfaces are present and were exercised in a real browser. The three that carry the argument:

- **Relation inspector** — four numbered, visually separated rows: *1 · STATEMENT LID — WHAT WAS SAID* · *2 · RELATION
  KIND AND ENDPOINTS* · *3 · WRL REV- — THE REVISION IDENTITY* ("Two worlds that say the same thing share a rev-") ·
  *4 · WRL REL- — THE WORLD-SCOPED ALLOCATION* ("a different world allocates a different rel- for the same rev-").
- **A deferred DEFEATER is inspectable as a deferral** — `deferred_target_reason` beside `target_file`,
  `target_revision`, `target_digest`, `target_digest_bits`, `target_symbol`, and a degree of `1 out · 1 in` with **no
  ATTACKS edge**. The evidence survives the deferral and the refusal is visible.
- **A1–A7** are `lib/acceptance.mjs` run in Node — **one definition** shared by the CLI, `test/acceptance.test.mjs` and
  the page, so the screen cannot show an answer the tests do not assert. All 7 answer in all four worlds. A question
  needing two pins **refuses** rather than answering from the wrong root.

Authority boundary: no write control of any kind; the footer states *"Every value on this page was computed by
lib/query.mjs in Node and is displayed, not recomputed. UI state is not part of any identity."* A test asserts the
baked explanation **equals `Graph.explain()` live**, that no world file mixes snapshots, and that the payload contains
no `x`/`y`/`position`/`layout`/`viewport`/`selected`/`expanded`. Screenshots: `ui/screenshots/`.

---

# 5 · Test state

`node --test test/*.test.mjs`: **151 tests, 150 pass, 0 fail, 1 skipped by design** (was 122/121/0/1) — the skip is the
pre-TRVM-P0 reproducer branch, superseded by the landed repair. `python3 test/canon_twin.py --selftest`: ok.
WRL `npm test`: **901 passed, 0 failed** (was 900). TRVM `make governance`: **32/32** at `8816e59`.

New files: `lib/acceptance.mjs` · `adapters/factory_mosaic.mjs` · `test/{acceptance,v1,g05}.test.mjs` ·
`tools/g05_build.mjs` · `bin/g05.mjs` · `ui/` · `handoff/G0F_V1_AUDIT.md` ·
`handoff/STACK_FIX_RECEIPTS/TRVM-P0.1.md` · `handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v1.json` ·
`snapshots/multi-v1.json` · `projections/{multi-v1,pre-trvmp01,pre-v1}/`.

---

# 6 · Open — what needs a ruling

1. **TRVM-P0.1's two judgement calls**: the chosen code names, and **enlarging** `spec_agreement` with a minted
   id-prefix comparison rather than only adding the two codes.
2. **The B2 finding**: the ledger already held the supersession, and the direction of the link is the protocol's
   (0/17 PINNED vs 14/18 ABORTED). Accept as closure of GAP-T14 without a new write?
3. **The corrected v1 surface** — 3 roles / 1 kind / 10 pairs. Specifically: (a) INSTRUMENT required rather than
   deferred; (b) the 3 `claim_evidence` targets deferred **although the endpoint resolves**, on the source's own
   statement of meaning; (c) `DISCHARGED_BY` at 2 records gated on status.
4. **The schema-set coupling.** `schemaSetId()` hashes *every* `schemas/*.schema.json` in the repo, so growing v1's
   vocabulary moved `schema_set_id` for the **frozen v0 projections** and their claims moved with it. v0's claim
   identity is therefore not independent of v1's evolution. The fix is a profile-scoped schema set — but
   `schema_set_id`'s meaning is part of `GRAPHONOMOUS-PROJECTION-v0`, whose semantics §2 froze, so narrowing it is a
   **protocol change, not a refactor**, and was not taken unilaterally. Leave it, or open
   `GRAPHONOMOUS-PROJECTION-v1`?
5. **The shared rulepack id.** Both rows declare `graphonomous.semantic.rules.v0`. That is what makes the 1,574/1,574
   `rev-` equality measurable; a `…rules.v1` would break it. One-line change if you want the separation.

## Evidence-profile checkpoint (`graphonomous.evidence.v0`)

**Still NOT YET, and G0.5 did not change it** — as §8 predicted it would not. The UI displays projection assertions
directly; nothing in it needed provenance occurrence to have a WRL-world identity. The four-way separation held
throughout: projection root = observed evidence, G0-E root = derived understanding, WRL world = statement semantics,
G0-D certificate = reconstruction receipt. **Recommendation only; nothing implemented.**
