# R17 — WRL source inventory (the fourth source family, read-only)

**For:** the fourth authoritative source family, authorized by GPT Adjudication v7 §12–§14 → **D-077**: *"WRL is the fourth
authoritative source family, AUTHORIZED NEXT. Inventory first; do not assume a JavaScript source file is an authoritative
registry merely because it contains the data. Read-only, own namespace and pin, and no mutation-capable tooling may be
invoked to ingest it. If WRL needs a role/kind v2 cannot represent, do not widen v2 — preserve everything and return a
minimal `graphonomous.semantic.v3` obligation."*
**Rule followed (R15's):** every claim below was read out of the file a **consumer** actually loads, and every count was
re-measured by this session with `node` against the checked-out commit, not copied from a page or a receipt.
**Date:** 2026-09-08. **Nothing was ingested; no adapter exists yet.**

```
source_family : WRL
repo          : /home/travis/ProjectAmp2/WRL          (own GitHub repo c-u-l8er/WRL; main; pushed; live at wrl.traaviis.com)
commit        : 32160fec77a13ad152176fed3001b0afbdebee42   ("Sync amp-nav 0.12.1: Graphonomous shows in_tree")
read method   : git cat-file blob <commit>:<path>          — never the worktree (it carries an untracked floor_band.png)
mutation      : none. Nothing in WRL is run by an adapter; node test/conformance.mjs is the OWNER's gate, not ours.
```

## 0. What WRL is, in its own words, and why that bounds the inventory

WRL's README: *"Nothing in this repository runs, reduces, stores or explains a world; it says exactly what one is."* WRL
owns the first of three verbs — **describes** — and it says three things get called "WRL" and must not be confused:
(1) **Core 0.1.2, the writable surface** (five roles, one texture, no behaviours); (2) **the authored design** (forty-six
sections, tier-marked, *not built*, `draft.html`); (3) the identity spine that seals a world to a `sem-` id. For
Graphonomous the authoritative WRL is (1) and (3): what the spine admits and seals. (2) is prose — research, never a
premise (the D-077 rule for TRVM's prose applies verbatim).

## 1. The registries, with their enumeration points

| registry | file at `32160fe` | blob | bytes | enumeration point (the consumer) | measured |
|---|---|---|---|---|---|
| **The profile table** `V2_PROFILES` | `relation-v2.js` | `68029bc10280a0a3db4d17bad09c74e984214b48` | 135,600 | `v2ProfileOf(artifact)` — the ONLY way a v2 artifact's profile is resolved; `graphonomous/v2/lib/wrl_world.mjs` reads `V2.V2_PROFILES[id]` and refuses `PROFILE_NOT_ADMITTED` otherwise | **4 rows**: `forge.world.core.v1` (derivation `lowered`, rulepack `forge.world.core.rules.v1`) · `graphonomous.semantic.v0` (`static`, `graphonomous.semantic.rules.v0`, 21 roles · 31 kinds · 92 pairs) · `graphonomous.semantic.v1` (24 · 32 · 102) · `graphonomous.semantic.v2` (24 · 32 · **103**) |
| **Relation-layer refusal codes** `RELATION_V2_CODES` | `relation-v2.js` | same | — | thrown by `assertV2Artifact` / `assertV2World` / `validateV2Relation`; Graphonomous's `wrl_world.mjs` pre-check names them | **24 codes** (`WRL_LEGACY_EDGES_IN_V2` … `WRL_PROFILE_SIGNATURE_MISMATCH`) |
| **Source families / IR versions** `V2_RELATION_SOURCE_FAMILIES`, `V2_IR_VERSIONS`, `V2_PROFILE_DERIVATIONS` | `relation-v2.js` | same | — | the IR header check | 1 family (`"2.0"` → `forge.world.core.v1`); IR versions `["2.0"]`; derivations `["lowered","static"]` |
| **The identity spine** (Core 0.1.2) | `wrl.js` | `19e94ad97acec633f7a83bcff4e3a01acd867b07` | 57,191 | every seal; `relation-v2.js` imports it as `W` | `IR_VERSION` 1.0 / 1.1; `PROFILE_ID forge.world.core.v1`; `RULEPACK_ID`; policy ids `admit_candidate_min_firstreceipt_v1`, `admit_mailbox_deliver_all_v1`, `film.v0.7`, `film.v0.7.mailbox.v1`, `POLICY_FORGE`, `sugar.v2`; **6 roles** (`Pulser Relay Door Spinner Orb Mailbox`, 5 writable), **2 edge kinds** (`SignalWire SocketControl`); **22 `CODES`** (18 browser codes); named-rotor policy tables |
| **Relation identity** (§D8 kernel) | `relation-identity.js` | `880cfe0406ab570f4963dbb3a9b6a7cc0ab39f01` | 61,760 | `relation-v2.js` (seeds, `rev-`/`rel-` minting) | not re-measured here; owned by WRL-P0's receipts (`handoff/STACK_FIX_RECEIPTS/WRL-P0.md`) |
| **The conformance corpus** | `test/conformance.mjs` | `cd079661f4e733d561bc7fce4e0a1a241f5032a7` | 350,216 | `node test/conformance.mjs` (WRL's own gate) | **924 passed, 0 failed; 70 annotated doc blocks of 115 swept; 26/26 capabilities cited; not-current: 9 complete worlds, 54 fragments** (run 2026-09-08) |
| **Projection vectors** | `test/projection-vectors.json` · `test/projection-negative-vectors.json` | `4527d50d…` · `ee3163c4…` | 19,916 · 67,869 | the conformance suite | `wrl.projection-vectors.1`: 5 vectors; `wrl.projection-negative-vectors.1`: 23 base + 15 negative |
| **The spec** | `docs/spec/` (tree `d6cdf760…`) | — | — | `spec.html` (Part I normative extract) | prose; the profile/register tables on `reference.html#profiles` / `#relation-codes` are **generated from `relation-v2.js` and held equal by the suite** (WRL `083ae6b`) — the page is a projection of the registry, never the registry |

**Three profile rows are Graphonomous's own declarations, admitted by WRL.** The submitted forms live on OUR side
(`handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v{0,1,2}.json`) and are **submissions**; the admitted rows in
`V2_PROFILES` are the **authority** (WRL-P0/P1). A future WRL adapter reads the admitted rows and may cite the submissions
as `SOURCE_LOCATION`s of a `PROFILE` node — it must never read the submission as if it were the admission.

## 2. Not authority (excluded)

`WRL.zip`, `WRL_PATH_C4_PACKET.zip` (packets); `HANDOFF_D8_PATH_A.md`, `HANDOFF_D8_PATH_B.md`, `PACKET_README.md` (history);
`forge-probe/` (a probe); every `*.html` (generated projections of the registries, plus prose); `draft.html`'s forty-six
sections (design, not built); `floor_band.png` (untracked in the worktree, not at any commit); `amp-nav.js` (the shared nav).

## 3. What `graphonomous.semantic.v2` can and cannot represent of this family

The v2 row admits **24 roles** — `OBLIGATION ENFORCEMENT_PROPERTY CLAIM LAW MECHANISM DEFINITION REPRESENTATION PROFILE
ASSUMPTION WITNESS FALSIFIER FINDING EXPERIMENT RECEIPT ARTIFACT ADJUDICATION EVIDENCE_STATE_TRANSITION ROUND CELL REGISTRY
SOURCE_LOCATION ARGUMENT DEFEATER INSTRUMENT` — and **32 kinds**.

| WRL entity | a v2 role that fits | verdict |
|---|---|---|
| a profile row (`forge.world.core.v1`, `graphonomous.semantic.v2`, …) | `PROFILE` | **representable** (the role exists for exactly this; `wrl_world.mjs` already names profiles) |
| the profile table, the code table, the vector sets | `REGISTRY` | representable |
| a projection vector, a conformance case | `WITNESS` / `FALSIFIER` (positive / negative) | representable |
| the spine's policy ids (`admit_candidate_min_firstreceipt_v1`, `film.v0.7`, …) | `MECHANISM`? `DEFINITION`? | **strained** — a policy id is a pinned rule, neither a mechanism nor a definition in the rulepack's sense |
| a **role** (`Pulser`, `CLAIM`, …), a **relation kind** (`SUPERSEDES`, `SignalWire`), an **endpoint pair** | — | **not representable**: v2 has no role for a vocabulary item, and the pairs are the very endpoint constraints the sealer enforces |
| a **refusal code** (`WRL_UNDECLARED_ENDPOINT_PAIR`, `CODES.*`) | — | **not representable** |
| a `sem-` / `rev-` / `rel-` identity | `ARTIFACT`? | strained — an identity is what a world *is*, not an artifact *in* it |

**So the family splits.** Its *world-level* objects (profiles, registries, vector sets as witnesses) fit v2; its
*vocabulary* — roles, kinds, endpoint pairs, codes, policy ids — does not, and that vocabulary is exactly what WRL exists
to own. Per D-077 the answer is not to widen v2.

## 4. The minimal `graphonomous.semantic.v3` obligation, measured

Exactly what the registries above state and v2 cannot carry, and nothing more:

```
roles   + VOCABULARY_ITEM      one role for a role, a relation kind, an endpoint pair, a refusal code, a policy id
                               (a `vocabulary_class` attribute names which; a second role per class would be five roles
                                for one idea and five endpoint-pair rows each)
kinds   + ADMITS               [PROFILE, VOCABULARY_ITEM]    a profile row admits a role / kind / pair
        + REFUSES_WITH         [REGISTRY, VOCABULARY_ITEM]   the sealer's code table names a refusal code
        (MEMBER_OF, DEFINES, CITES, WITNESSES already exist and carry the rest: an item is MEMBER_OF a registry,
         a vector WITNESSES a profile, a page CITES a registry)
```

Counts the adapter would emit at `32160fe`, if the obligation is accepted as stated: 4 `PROFILE`, ≥ 4 `REGISTRY`,
6 + 21 + 24 roles as items (with the v0/v1/v2 overlap shared by statement LID), 2 + 31 + 32 kinds, 92 + 102 + 103 pairs,
22 + 24 codes, 8 policy ids, 5 + 38 vectors as `WITNESS` / `FALSIFIER`. **None of these numbers is a promise; they are the
sizes of the registries as measured, so the obligation can be judged against what it would have to hold.**

If the obligation is refused, the family is still admissible *partially* under v2 (profiles, registries, vectors), with
the vocabulary **deferred with its coordinates preserved and no edge** — the D-073 pattern — and the deferral count
reported on the page.

## 5. Consumers on our side that already touch WRL, and what they are not

`lib/wrl_world.mjs` pins WRL (`WRL_PIN`: commit `6a8304c9a598bb…`, blobs of `relation-v2.js`, `relation-identity.js`,
`wrl.js`) and **uses** it — to seal our worlds. That is a *dependency*, not a source family: nothing in it reads WRL's
registries as facts about WRL. The pin is at `6a8304c` (WRL-P1); WRL HEAD is `32160fe`, two commits later, both nav-only
(`git log 6a8304c..32160fe -- relation-v2.js wrl.js relation-identity.js` is empty — the three pinned blobs are identical
at both commits, as the blob ids above show). An adapter would carry **its own** pin under its own namespace (`wrl`),
per D-077, and the two pins would be allowed to differ.

## 6. Not done here

No `adapters/wrl.mjs`, no snapshot, no projection, no page. The next step is the obligation's adjudication (v3 as stated
in §4, or partial admission under v2 with deferral), then the adapter — read-only, `git cat-file` at the pin, its own
namespace, and `contracts/projection.v1.json` gaining a fifth adapter row whose emitted kinds are measured by the probe,
not declared.
