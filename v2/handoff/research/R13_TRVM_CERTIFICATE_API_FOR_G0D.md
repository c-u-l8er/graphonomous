# R13 — the TRVM certificate API, measured for G0-D (`GRAPHONOMOUS-PROJECTION-v0`)

Read-only research, 2026-09-03. TRVM at `fd0df4c` (clean before and after; nothing written into either tree). Every
`file:line` below is at that commit; `certificate.mjs`, `nest_check.mjs`, `nest_bundle.mjs`, `compose_check.mjs`,
`cas.mjs`, `schema.mjs`, `live_dag.mjs` are under `TRVM/governance/`. Probes beside this file:
`probe_g0d_nest_child.mjs` (+ `.out`) — the GAP-T9 reproducer; `probe_g0d_claim_design.mjs` (+ `.out`) — a candidate
claim over the real baseline projection. Outputs are appended verbatim (§7).

**Verdict up front.** The mint side is protocol-agnostic; the judge side is closed on every path a caller has.
**TRVM-P0 is NEEDED** (D-054 GAP-T9 discipline: "TRVM can mint but cannot generically check/register the child
protocol except by a Graphonomous-local checker" — reproduced, §3). Recommended design: §4 option **(a′)**.

## 1. What `verifiedClaimSemId` commits to; what `chain_ids` and `aggregate_id` mean

`verifiedClaimSemId({protocol, claim_sem_id, aggregate_id, chain_ids})` = `"vclaim-" + sha256(CERTIFICATE_PROTOCOL +
"|" + canonicalBytes({certificate_protocol, protocol, claim_sem_id, aggregate_id, chain_ids}))`
(`certificate.mjs:60-68`; normative `docs/spec/proof-wire/TRVM-VERIFIED-CLAIM-v1.md:19-31`, prefix appears twice by
design `:31`). The three string inputs must be non-empty strings and `chain_ids` an object, else it throws
`certificate-incomplete: <k>` (`:61-65`; spec §2.1 `:33`). No verdict, signature or registry is in the preimage
(`:37-44`). The probe printed the exact preimage for a Graphonomous-shaped input (555 octets, §7.1 [2]) and re-derived
the id by hand: equal. Sensitivity measured: annotations reworded → HOLDS; `chain_ids.projector` changed → MOVED;
`claim_sem_id` changed → MOVED; missing `chain_ids` → `certificate-incomplete: chain_ids`.

`certificateOf(bundle, claim_field)` reads `bundle.protocol`, `bundle.claim[claim_field]`,
`bundle.aggregate.aggregate_id`, `bundle.chain_ids` (`certificate.mjs:75-82`). The claim field is the **citer's**
knowledge, never the bundle's (`:46-49`; spec §2.2 `:35`).

**`chain_ids` in the two leaf protocols** is a flat record of ten compiler-chain identities —
`lowering_sem_id, instantiation_sem_id, emission_sem_id, emission_rules_sem_id, target_template_encoding_sem_id,
target_executable_encoding_sem_id, decode_sem_id, canonical_emitter_profile_id, canonical_emitter_artifact_id,
lowering_version` — produced by `chainIds()` (`proof_bundle.mjs:231-243`; domain reuses it, `domain_bundle.mjs:70`).
Meaning: "under which compiler". It is **not** derived from the bundle: both checkers call the LIVE `chainIds()` and
refuse any field that differs (`proof_check.mjs:360-364` → `proof-chain-id-mismatch`; `domain_check.mjs:379-382` →
`domain-chain-id-mismatch`). So a leaf chain is a *relation to the checker's own module*, not a value the artifact may
assert. For the composed protocol the chain is `{leaf_chains: [...]}`, the flat deduplicated set of the direct
children's chain records, derived and compared as a set (`nest_check.mjs:659-666`, `:737-746`; spec
`TRVM-NESTED-COMPOSITION-v2.md:132-148` "A producer MUST NOT write its own chain").

**`aggregate_id`** for a leaf = `H(PROOF_PROTOCOL | canonical(aggregate without aggregate_id))`
(`proof_bundle.mjs:222-`); it commits to case ids, counts, case-set commitment, measurements and the verdict — "WHAT
WAS MEASURED, and nothing about WHAT WAS CLAIMED" (`certificate.mjs:13-21`; measured: swapping the proposition leaves
it byte-identical). Every aggregate field is *derived* by the checker and compared (`proof_check.mjs:520-585`). For the
nest protocol it is `nagg-` over `{operands, child_verdicts, leaf_receipts_rederived_by_parent: 0,
films_replayed_by_parent: 0, nested_verdict}` (`nest_bundle.mjs:143-146`, `:241-253`; derived again at
`nest_check.mjs:684-699`).

## 2. Relations vs values; the checked child-bundle layout

`live_dag.mjs:24-34` states the discipline: assert **relations** (leaves verify under their own checkers; the DAG
verifies; every *semantic* identity — `nested_claim_sem_id`, `aggregate_id`, `chain_ids`, each operand's
`verified_claim_sem_id` — equals the frozen corpus, `:76-98`; every reference resolves, `:101-108`) and **report** the
complete artifact root, which binds execution provenance and is allowed to differ (`:110-131`). The nest artifact's
planes (spec `TRVM-NESTED-COMPOSITION-v2.md:22-36`): `protocol` CHECKED · `claim` semantic · `chain_ids` derived ·
`references` transport · `aggregate` evidence · `structure` shape (authenticated in the root, outside the certificate,
`nest_check.mjs:701-724`) · `type/version/annotations` NON-SEMANTIC. `field_audit.mjs` forces every grammar field into
DERIVED / CHECKED / NON_AUTHORITATIVE (header `:17-36`). Layout the checker demands: `GRAMMAR` at
`nest_check.mjs:181-199` — bundle `{protocol, claim, chain_ids, references, aggregate, structure}` + optional
`{type, version, annotations}`; `claim {connective, scope, operands, nested_claim_sem_id}`; operand
`{protocol, claim_sem_id, aggregate_id, verified_claim_sem_id}` (no address — law reference-is-not-claim); reference
`{verified_claim_sem_id, artifact_root}`; exact key sets via `schema.mjs:84-101 grammar()`. The leaf grammars are their
own (`proof_check.mjs:194-221`, `domain_check.mjs:201-227`), bundle-level `{protocol, claim, chain_ids, port_names,
cases, aggregate}`. Result shape every checker returns: `publicResult` → `{ok, verdict, evidence_verdict, refusals:
[{code, detail}], measured}` with `ok === (verdict === "VERIFIED")` (`schema.mjs:121-133`).

## 3. What `nest_check` can check generically today; the reproducer

Generically (protocol-independent) it does: byte budget before parse and canonical-wire ingress (`:219-259`); ownership
snapshot (`:265-273`); phase 1 resolution of every `references.operands[].artifact_root` through the store with the eight
`cas.mjs` outcomes mapped 1:1 to refusal codes (`:391-403`); depth/cycle/budget policy (`:353-438`); the two-plane
set equality of operands vs references (`:554-575`); and, for a *resolved* child, the certificate recomputation and
field-by-field cross-wire check (`:642-656`). What it cannot do: judge a child whose `protocol` is not a key of the
frozen table `IMPLEMENTED_CHILD_PROTOCOLS` (`:151-159`, "DECLARED HERE, NOT IMPORTED — sixth round running") —
`:584-589` refuses `nest-child-protocol-unsupported` and `continue`s *before* the child joins `resolvedChildren`, so the
derived chain set, the derived verdicts and the structure all disagree with the honest bundle as a consequence.

**Reproducer** (`probe_g0d_nest_child.mjs`, output §7.1): a 1254-byte `GRAPHONOMOUS-PROJECTION-v0` child with
`claim.projection_claim_sem_id`, `aggregate.aggregate_id`, `chain_ids` (TRVM pin blobs + projector id), stored in
`memoryStore` (resolves `ok`), wrapped by hand in a one-operand nest bundle (the producer refuses first:
`buildNestBundle([child]) → nest-bundle-unknown-child-protocol`, `nest_bundle.mjs:220`). `checkNestBundle(nest,
{store})` → `REFUSED`, refusals verbatim: `nest-child-protocol-unsupported` (`operand 0: child protocol
"GRAPHONOMOUS-PROJECTION-v0"; this checker implements [TRVM-BOUNDED-PROOF-v1, TRVM-BOUNDED-DOMAIN-PROOF-v1,
TRVM-NESTED-COMPOSITION-v2]`) plus the consequential `nest-chain-ids-mismatch`, 2× `nest-count-inconsistent`, 3×
`nest-structure-mismatch`, `nest-child-refused`; `checker_evaluations = 0`, `unique_artifact_resolutions = 1`. The
bytes boundary `checkNestBytes` gives the same set. `verifiedClaimSemId` **does** mint for the protocol
(`vclaim-c278d3b2…`). Every registration route a caller has is closed (§7.1 [4]): (a) assignment to the frozen table →
`TypeError: Cannot add property GRAPHONOMOUS-PROJECTION-v0, object is not extensible`; (b) an opts field
`child_protocols` → `effectivePolicy` refuses any key not in `SHIPPED_POLICY` (`:129-133`) → `nest-policy-weakened`
before anything is checked; (c) `SHIPPED_POLICY` has six fields, none a registry (`:111-118`); (d) the producer table is
frozen too and the checker does not import it (`nest_bundle.mjs:79-88`). `checkComposeBundle` over the same child →
`compose-child-protocol-unsupported` (+ consequentials) from its own frozen table (`compose_check.mjs:85-91`,
`:247-252`). Note a real trap met on the way: `canonicalBytes` **refuses** an `undefined` member
(`derive_protocol.mjs:350`, `not-canonical: undefined at $.projection_claim_sem_id`) — G0 identity helpers must omit
fields by destructuring, never set them `undefined`.

## 4. Can a child protocol be registered without an app-specific branch? No — and the minimal TRVM-P0

Why hard-coded, in the ledgers' own words: `round-11-ledger.md:3601-3604` — "`IMPLEMENTED_CHILD_PROTOCOLS` is the
checker's, not the bundle's, and `claim_field` is why: a composer that let the artifact name its own claim field would
let it choose which of its hashes to be judged on. Third round running for the same defect — P1.1 the claimant defining
scope, P2.1 the claimant defining absence"; `:3669` "declared inside its own CHECKER and not imported — the fourth
round running for that rule"; `schema.mjs:5-44` (law `proof.semantic-vocabulary-closed@1`: a checker reading its
vocabulary out of the generator/artifact "would be back where P1.1 started"); `certificate.mjs:46-49`. The table is
also pinned by two gates: `spec_agreement.mjs:91-97` compares its keys, `claim_field` and `composed` against the
normative schema `docs/spec/proof-wire/schema/nested-composition-v2.json:57-60`, and `SPEC-RELEASE.json:25` digests
that schema. The spec itself calls the interface awkward and leaves it un-redesigned on purpose
(`TRVM-VERIFIED-CLAIM-v1.md:59-65`). So the rule being protected is: **the artifact never names its own claim field or
checker; a VERIFIER does.** A caller-supplied registry does not violate it, provided the caller is the verifier, the
built-ins cannot be overridden, and the verdict names which checker set produced it.

**(a′) recommended — caller-supplied registry beside `store`.** `checkNestBundle(bundle, {store, child_protocols})`
and `checkNestBytes(raw, {store, child_protocols})`: destructure `child_protocols` out with `store`
(`nest_check.mjs:226`, `:276`) so it never reaches `effectivePolicy`; validate each entry
`{claim_field: string, check: function, composed: false, checker_id: string}` (refuse `nest-child-protocol-malformed`);
refuse any key already in `IMPLEMENTED_CHILD_PROTOCOLS` (`nest-child-protocol-override-refused`) and any `composed:
true` (composition stays this checker's); build `effective = Object.freeze({...IMPLEMENTED_CHILD_PROTOCOLS,
...supplied})` inside `checkOwned` and use it at `:584`; report `measured.child_protocol_set = {builtin: [...],
supplied: [{protocol, checker_id}]}` and fold a `child_protocol_set_id` into the reported `verifier_policy_id`
(`:124-125`) so a verdict says which checker set accepted it — the same move `proof.verifier-policy-owned@1` made for
resource policy (`:37-49`). No new file (a new governance file must be declared in `artifacts.json` or `grid_check`
refuses it as present-but-undeclared, `harness_selftest.sh:92-98`). Built-in table and grammar byte-identical ⇒
`spec_agreement`, `field_audit`, `spec_vectors`, the frozen corpus and the existing
`child-protocol-with-no-checker-here` vectors (`nest_forgeries.mjs:227-232`, `compose_forgeries.mjs:182-188`) are
unchanged. Trade-off: a supplied checker widens the set of VERIFIED artifacts, so it must be visible in the measured
record; the `checker_id` is a name, not a warrant — the parent still recomputes the certificate (`:642-656`).

**(b) module-level `registerChildProtocol(...)`** — global mutable state in a module whose whole lineage is "no
authority channel outside the call" (`nest_check.mjs:16-35`, `persistent_warrant_hits: 0` `:325-326`); registration
order and process-wide reach make a verdict depend on who else imported the module; a second registrant in the same
process (a test, a battery) is a collision. Refusal on re-registration only proves the second caller lost. Rejected.

**(c) a protocol descriptor artifact in the CAS** — the CAS holds JSON only, never code (`cas.mjs` header; `:173-194`
memory store), so it can carry a `claim_field` and a checker *identity* but not a checker; letting the citation (or the
child) supply the claim field is precisely the P3 defect. Acceptable only as the *identity* a supplied registry entry is
compared against (its `checker_id`), never as dispatch. Rejected as the mechanism.

**Batteries that must stay green** (all run by `Makefile`): `gov-nest` `:272-372` — `jcs_vectors`, `nest_bundle`
(**writes** `governance/cas/` and `nest_bundle.json`, `nest_bundle.mjs:316-327`), `nest_check`, `spec_vectors`
(verify mode compares a scratch candidate to the frozen corpus; UPDATE mode is the only writer, `spec_vectors.mjs`
header), `spec_agreement`, `field_audit`, `live_dag`, `experiment_falsifiers`, `nest_forgeries`; `gov-proof`
`:217-235` — `proof_bundle` (**writes** `proof_bundle.json`), `proof_check`, `proof_forgeries`, `domain_bundle`
(**writes**), `domain_check`, `domain_forgeries`, `compose_bundle`, `compose_check`, `compose_forgeries`; `gov-spec`
`:254-259` — `spec_release`, `jcs_vectors`, `spec_vectors`, `spec_agreement`; `gov-negative` `:136-140` —
`negative_battery.sh` copies `artifacts.json` `case_inputs` (which include `nest_check.mjs`, `certificate.mjs`) into
`$SCRATCH=/tmp/neg5` per case; `gov-harness` `:374-377` — `harness_selftest.sh` (`/tmp/harness-selftest`) +
`runner_contract.sh`; `gov-grid` `grid_check.mjs` (scratch via `mkdtemp` only). The forgery suites mutate in memory
and write nothing. TRVM-P0 therefore runs in a separate local TRVM commit, never while another battery is running,
and adds: one failing-first positive vector (an alien leaf protocol with a supplied honest checker → VERIFIED with the
set reported), the override refusal, the malformed-entry refusal, and a LYING supplied checker (in the
`nest_forgeries.mjs:65-69` style) whose cross-wired certificate is still refused by the parent.

## 5. "Not a warrant" at the API boundary — what the Graphonomous checker must do

`certificate.mjs:37-49`: the id NAMES a (protocol, claim, aggregate, chain) tuple; whoever cites it must run the
child's own checker. `compose_check.mjs:45-51` says the same and `:258` re-runs `spec.check(child)` on every
citation; `nest_check.mjs:616` does the same once per distinct artifact, memoised only inside one call over a snapshot
it owns (`:16-35`). Consequently the Graphonomous checker `checkProjectionCertificate(bundle, {dir | store})` must
(i) take an owned snapshot of the bundle (`schema.mjs:71-73 ownSnapshot`) and an exact key set per record
(`grammar()`); (ii) re-derive everything: resolve the manifest through the CAS and recompute the root
(`lib/project.mjs:156-173 verify()`), recompute the snapshot commitment from `snapshot.json`, recompute the ruleset id
(`lib/rules.mjs:25`), schema-set and adapter-contract ids from the files, recompute the aggregate from the manifest,
compare `chain_ids` against its own LIVE pin table (`lib/canon.mjs:30-53 TRVM_PIN / assertTrvmPinned` — the analogue of
`chainIds()`), recompute `verifiedClaimSemId` and compare field by field; (iii) return `publicResult`-shaped
`{ok, verdict, refusals, measured}` so it is pluggable as a leaf `check` under (a′) (the leaf branch reads `r.ok`,
`r.verdict`, `r.refusals`, and `r.measured.films_replayed_on_two_classes / derived_cases`, absent → 0,
`nest_check.mjs:616-624`); (iv) write nothing, keep nothing, issue nothing — no registry of accepted certificates
exists anywhere, and possession of a `vclaim-` confers no authority (D-054).

## 6. Protocol design for `GRAPHONOMOUS-PROJECTION-v0` (derived from the real API; measured in §7.2)

Bundle (five planes, same discipline as the nest grammar; exact key sets, extras refused):

```
protocol   "GRAPHONOMOUS-PROJECTION-v0"                                  CHECKED
claim      { projection_root, snapshot_id, snapshot_commitment, spec, ruleset, schema_set_id,
             adapter_contract_id, scope, projection_claim_sem_id }      SEMANTIC (all DERIVED)
chain_ids  { trvm_commit, trvm_blobs{3}, projector, checker }           CHECKED against the live pin table
references { contract: {CONTENT_ADDRESSED, CANONICAL, address_is_a_warrant:false},
             operands: [{role:"manifest", artifact_root}, {role:"snapshot", artifact_root}] }   TRANSPORT
aggregate  { count, per_kind, faults{count,digest,by_code}, adapter_runs, aggregate_id }        EVIDENCE (DERIVED)
structure  { kinds, cas_objects, manifest_bytes, structure_sem_id }     SHAPE (in root, outside certificate)
annotations prose only                                                   NON_AUTHORITATIVE
```

`projection_claim_sem_id = "gclaim-" + H("GRAPHONOMOUS-PROJECTION-v0|" + canonicalBytesG0({protocol, projection_root,
snapshot_id, snapshot_commitment, spec, ruleset, schema_set_id, adapter_contract_id, scope}))` — WHAT was reconstructed
and FROM WHAT. `scope` is the checker-owned record `{kind: PROJECTION_RECONSTRUCTION_IDENTITY, quantifier:
OVER_THE_PINNED_SOURCE_SET, truth_claimed:false, evidence_sufficiency_claimed:false, state_promoted:false,
registry_written:false, trvm_derivation:false}` compared value-for-value like `IMPLEMENTED_NEST_SCOPE`
(`nest_check.mjs:161-167`, `:496-503`) — D-054's "must not mean" list made refusable. **`snapshot_commitment`** =
`"gsnap-" + H(PROTO|snapshot| + canonicalBytesG0(sortSet(sources.map(identity))))` over `{namespace, registry, repo,
commit, tree, files: sortSet({path, blob, sha256, bytes})}` — measured: reversing source order HOLDS, dropping `trvm`
MOVES, a duplicate source is refused `G0_SET_DUPLICATE` (`lib/canon.mjs:151-159`), whereas the stored snapshot hash is
order-dependent (§7.2 [2]) — so the commitment is the set-valued thing D-054/G0-F require, and it is needed at all
because the manifest binds only the snapshot *label* (`project.mjs:140`, `manifest.snapshot = "snapshot:g0:…"`), not
the pins. `aggregate_id = "gagg-" + H(PROTO| + canonical(aggregate without aggregate_id))` over manifest facts — WHAT WAS
MEASURED (the manifest's `count, per_kind, faults, adapter_runs`, `project.mjs:140`; `adapter_runs` already binds the
adapter blob, `:98`). `chain_ids` = `TRVM_PIN.commit` + the three pinned blobs (`canon.mjs:30-38`) + `projector` /
`checker` ids — UNDER WHICH CODE; checked like `chainIds()`, never derived from the bundle. Certificate id =
`verifiedClaimSemId({protocol, claim_sem_id: projection_claim_sem_id, aggregate_id, chain_ids})`; claim field for
citers = `projection_claim_sem_id`. Measured over the real baseline (§7.2 [4]): root, dropped source, ruleset, schema
set, adapter contract, protocol id → claim MOVED · certificate MOVED; TRVM pin → claim HOLDS · certificate MOVED;
source reorder, `witness.json`, README, prose → HOLDS. Two projector notes for G0-D: `snapshot.json` is written but
**not** put into the CAS (`project.mjs:148` vs `:132`, `:149`) — put the snapshot identity record into `cas/` so the
second reference resolves; and `manifest.schema.json` leaves `ruleset` optional (`schemas/manifest.schema.json:7-15`)
— the claim must require it (`gproj-ruleset-missing`).

**Refusal codes for D-054's seven** (own code per fault, `cas.mjs` outcomes mapped 1:1 as `nest_check.mjs:391-403`):
1 wrong root → `gproj-root-mismatch`; 2 missing/extra/duplicated bound source → `gproj-snapshot-commitment-mismatch`,
unpinned source → `gproj-source-unpinned`; 3 wrong manifest/CAS object → `gproj-artifact-unresolvable |
-non-canonical | -invalid-utf8 | -root-mismatch | -malformed`, record bytes ≠ manifest entry → `gproj-entry-mismatch`;
4 protocol/version → `gproj-protocol-mismatch`, spec id → `gproj-spec-mismatch`; 5 forged chain → `gproj-chain-id-
mismatch`; 6 certificate copied to another snapshot → `gproj-certificate-stale` (recomputed vclaim ≠ cited) and
`gproj-citation-cross-wired` (field-by-field); 7 malformed/noncanonical → `gproj-ingress-refused`,
`gproj-vocabulary-unknown`, `gproj-claim-id-mismatch`, `gproj-count-inconsistent`, `gproj-scope-mismatch`,
`gproj-checker-threw`.

**Test plan for the eight acceptance items (D-054):** (1) versioned protocol id — `gproj-protocol-mismatch` on `-v1`
and on any other string; (2) content-bound id — hand re-derivation of the preimage equals `verifiedClaimSemId` (as
§7.1 [2]); (3) binds the exact root — the two frozen D-049 roots (`root-da4f3d7a…`, `root-c5d650b0…`) each verify and
each refuses the other's certificate `gproj-certificate-stale`; (4) binds the source set — drop / add / duplicate /
reorder sources: three MOVE, reorder HOLDS; (5) binds ruleset, schema set, adapter contract, spec — each MOVES; (6)
moves on bound, holds on unbound — `witness.json`, README, annotations, `head_drift` edits HOLD (field_audit-style sweep:
every grammar field classified DERIVED/CHECKED/NON_AUTHORITATIVE and mutated); (7) old certificates stay checkable —
the pre-G0-F baseline certificate verifies against `projections/baseline/` after a G0-F snapshot exists; (8) not a
warrant — the checker writes nothing (directory digest before/after), a forged `ok:true` in `annotations` changes
nothing, and — after TRVM-P0 — `checkNestBundle(nest, {store, child_protocols: {GRAPHONOMOUS-PROJECTION-v0: …}})`
returns the identical verdict and refusal-code set as the Graphonomous checker on every positive and forgery vector,
while the same call without the registry still returns the §3 refusal verbatim. Run as `node --test test/*.test.mjs`
(`v2/package.json`), temp dirs only.

## 7. Probe outputs, verbatim

### 7.1 `node probe_g0d_nest_child.mjs`

```
[2] certificateOf(child, 'projection_claim_sem_id') = {"protocol":"GRAPHONOMOUS-PROJECTION-v0","claim_sem_id":"gclaim-54f7c0063fe2980fc4c14d14b083baad28ba94a29da038988835f4f61978eaec","aggregate_id":"gagg-a73803067…
    preimage bytes (555 octets):
    TRVM-VERIFIED-CLAIM-v1|{"aggregate_id":"gagg-a7380306706fd7722e6da3a80b112bc936a37ba8e875065d0d2598032144ad06","certificate_protocol":"TRVM-VERIFIED-CLAIM-v1","chain_ids":{"projector":"graphonomous.g0.project.v0","trvm_blobs":{"governance/cas.mjs":"4b84dff4b4d1fd68412c579cd9683b8dc4075d7f","governance/derive_protocol.mjs":"8ec73d9b3401e1e013388c6daf9d8b2c63d43954"},"trvm_commit":"fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873"},"claim_sem_id":"gclaim-54f7c0063fe2980fc4c14d14b083baad28ba94a29da038988835f4f61978eaec","protocol":"GRAPHONOMOUS-PROJECTION-v0"}
    verifiedClaimSemId = vclaim-c278d3b204595d8710a323798298e805530384d4a6768c0c5e2d5aa6ac1d30ab
    re-derived by hand   = vclaim-c278d3b204595d8710a323798298e805530384d4a6768c0c5e2d5aa6ac1d30ab  equal: true
    reword annotations →  HOLDS
    change chain_ids.projector →  MOVED
    change claim_sem_id →  MOVED
    missing chain_ids → certificate-incomplete: chain_ids

[3] child stored: root-a3cd9f1d1731889b2cc914590ca60d6837a4929469fdee40270c262aacad8c07  resolve: ok  bytes: 1254
    IMPLEMENTED_CHILD_PROTOCOLS = TRVM-BOUNDED-PROOF-v1, TRVM-BOUNDED-DOMAIN-PROOF-v1, TRVM-NESTED-COMPOSITION-v2
    Object.isFrozen(IMPLEMENTED_CHILD_PROTOCOLS) = true
    buildNestBundle([child]) → nest-bundle-unknown-child-protocol: GRAPHONOMOUS-PROJECTION-v0
    nest bundle chain_ids (derived from the child) = {"leaf_chains":[{"trvm_commit":"fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873","trvm_blobs":{"governance/cas.mjs":"4b84dff4b4…

[3a] checkNestBundle(nest, {store}) → ok: false verdict: REFUSED
     nest-child-protocol-unsupported: operand 0: child protocol "GRAPHONOMOUS-PROJECTION-v0"; this checker implements [TRVM-BOUNDED-PROOF-v1, TRVM-BOUNDED-DOMAIN-PROOF-v1, TRVM-NESTED-COMPOSITION-v2]
     nest-chain-ids-mismatch: chain_ids does not identify the compilers of the artifacts this checker resolved — a composition's chain is DERIVED from its children and may not be declared
     nest-count-inconsistent: aggregate.child_verdicts says {"vclaim-c278d3b204595d8710a323798298e805530384d4a6768c0c5e2d5aa6ac1d30ab":"VERIFIED"}, this checker derives {}
     nest-count-inconsistent: aggregate.nested_verdict says "VERIFIED", this checker derives "REFUSED"
     nest-structure-mismatch: structure.unique_artifacts says 1, this checker derives 0
     nest-structure-mismatch: structure.max_depth_below says 1, this checker derives 0
     nest-structure-mismatch: structure.unique_bytes says 1254, this checker derives 0
     nest-child-refused: the claim is a CONJUNCTION of 1 child claims and 0 are verified
     measured.refusal_codes_transitive = ["nest-chain-ids-mismatch","nest-child-protocol-unsupported","nest-child-refused","nest-count-inconsistent","nest-structure-mismatch"]
     checker_evaluations = 0  unique_artifact_resolutions = 1

[4] registration routes:
    (a) assignment to the frozen table → TypeError: Cannot add property GRAPHONOMOUS-PROJECTION-v0, object is not extensible
        table still = TRVM-BOUNDED-PROOF-v1, TRVM-BOUNDED-DOMAIN-PROOF-v1, TRVM-NESTED-COMPOSITION-v2
    (b) checkNestBundle(nest, {store, child_protocols:{…}}) → effectivePolicy: {"refusal":"child_protocols is not a field of this verifier's policy"}
        → verdict: REFUSED refusals: nest-policy-weakened
    (c) SHIPPED_POLICY fields = max_depth, max_artifact_bytes, max_total_resolved_bytes, max_operands_per_node, max_artifact_resolutions, derivation_reuse — no registry field exists
    (d) producer table CHILD_PROTOCOLS frozen: true ; nest_check declares its own copy and does not import it (nest_check.mjs:151)
    (e) the bytes boundary is the same checker: nest-child-protocol-unsupported, nest-chain-ids-mismatch, nest-count-inconsistent, nest-count-inconsistent, nest-structure-mismatch, nest-structure-mismatch, nest-structure-mismatch, nest-child-refused

[5] checkComposeBundle over the same child → codes: compose-vocabulary-unknown, compose-scope-mismatch, compose-child-protocol-unsupported, compose-claim-id-mismatch, compose-count-inconsistent, compose-child-refused

[6] leaf chain_ids() keys = lowering_sem_id, instantiation_sem_id, emission_sem_id, emission_rules_sem_id, target_template_encoding_sem_id, target_executable_encoding_sem_id, decode_sem_id, canonical_emitter_profile_id, canonical_emitter_artifact_id, lowering_version
    e.g. lowering_version = 0.13.0  canonical_emitter_profile_id = cemp-e0a333a957121be7d25396d4f49343c1f23…
    nest GRAMMAR.bundle.required = protocol, claim, chain_ids, references, aggregate, structure | optional = type, version, annotations
    nest GRAMMAR.operand.required = protocol, claim_sem_id, aggregate_id, verified_claim_sem_id
```

### 7.2 `node probe_g0d_claim_design.mjs`

```
[1] baseline ROOT = root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85  artifactRoot(manifest) equal: true
    manifest keys = adapter_runs, count, entries, faults, kind, per_kind, ruleset, snapshot, spec
    manifest.snapshot = snapshot:g0:baseline-ba4e625  ruleset = g0rule-279caadc7dec1b030…  adapter_runs = 1
    snapshot sources (declared order) = wrl → super → r10 → factory → computedriven → trvm

[2] snapshot commitment (sorted set of source identities) = gsnap-d67431565fa32b7de8a19b9bdda5e30adfcd74e54ce2eca2b97d41820b05146b
    reversed source order → HOLDS (order-independent)
    dropped source 'trvm' → MOVED (dropped source refused)
    for contrast, hashRecord(snapshot) as stored: reversed order → MOVED (the stored snapshot hash is ORDER-DEPENDENT)
    duplicate source → refused: G0_SET_DUPLICATE

[3] schema_set_id = gschema-a3a2ad28d2927482ac42d3… over 12 schemas
    adapter_contract_id = gadapt-3b9e4e555ca5654099262b0… over crosswalk.mjs, git.mjs
    ruleset (loaded) = g0rule-279caadc7dec1b030ba3657… equals manifest.ruleset: true
    TRVM pin verified: {"governance/derive_protocol.mjs":"8ec73d9b3401e1e013388c6daf9d8b2c63d43954","governance/c…

[4] projection_claim_sem_id = gclaim-ff2c5fb9cafdc9c422190f9fecd19a5372c771fd1ae395655079b37cee963eaf
    aggregate_id = gagg-02ce97b7b9d9f1664cce6862b8529c6f57a579d5af513976cafcb9960d334548
    verified_claim_sem_id = vclaim-a5223d69d6be2a570afc162d546fe141264afc83e8394c13184fda4b11610b97
    projection_root changed            claim MOVED · certificate MOVED
    snapshot: source dropped           claim MOVED · certificate MOVED
    snapshot: sources reordered        claim HOLDS · certificate HOLDS
    ruleset changed                    claim MOVED · certificate MOVED
    schema set changed                 claim MOVED · certificate MOVED
    adapter contract changed           claim MOVED · certificate MOVED
    protocol id bumped to v1           claim MOVED · certificate MOVED
    witness.json / README / prose changed  claim HOLDS · certificate HOLDS (not in any bound value)
    TRVM pin moved (chain)                 claim HOLDS · certificate MOVED
    certificate copied to another snapshot: the checker recomputes claim from the projection dir it is handed; a different ROOT ⇒ different projection_root ⇒ nest-style 'certificate-stale' refusal (relation, not value)
```

Both runs: TRVM `git status --short | wc -l` = 0 before and after; the Graphonomous `v2/` tree unchanged.
