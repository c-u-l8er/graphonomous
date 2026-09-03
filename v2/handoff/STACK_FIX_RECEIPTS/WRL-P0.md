# STACK FIX RECEIPT — WRL-P0 "Static Profile + Seal Closure" (2026-09-03)

The first change made to a stack layer under the repair protocol (brief §10), authorized by GPT Adjudication v3 §3
(D-039) after the G0-C spike (D-036) reduced the failure to a reproducer. Owning layer: **WRL relation layer**
(`relation-v2.js`). Kernel (`relation-identity.js`) and spine (`wrl.js`): **untouched** (blob OIDs equal before/after).

| | |
|---|---|
| Exposing Graphonomous case | G0-C: a deterministic `graphonomous.semantic.v0` world exists, WRL cannot seal it to a `sem-`, so the kernel cannot mint `rel-` (R10 §4; GAP-W11/W13; the spike minted `gsem-`/`grelpre-` instead) |
| Minimal reproducer | `WRL-P0/graphonomous_seal_reproducer.mjs` — a two-object world (RECEIPT → WITNESSES → CLAIM) in the exact G0-C shape; at `1f4c5fd`: `WRL_UNSUPPORTED_PROFILE`; output after repair in `WRL-P0/reproducer-output.json` |
| WRL commit before → after | `1f4c5fd4cf50ce65e3939fe1981efb9bb3363aba` → **`b072db0a983a33108b9a0c4429b978cb07e54148`** (local commit, not pushed) |
| `relation-v2.js` blob | `b5e9ff8101e3557bea9dbb1db76bbba341fbeaf3` → `fd1babc5459206c4de1ac1c994b880d24e18ef81` (+409 / −19) |
| `test/conformance.mjs` blob | `06c92016032a8695e4bc0e0c97968374005df11e` → `ab8e90f9c763c4a1aad5a78f209902fb1ed72597` (+346: section 21j, 10 checks) |
| `relation-identity.js` · `wrl.js` blobs | `880cfe0406ab570f4963dbb3a9b6a7cc0ab39f01` · `19e94ad97acec633f7a83bcff4e3a01acd867b07` — **unchanged** |
| TRVM | untouched |

## The change (data, not a branch)

`V2_PROFILES` — a frozen table keyed by `profile_id`, each row tagged `derivation: "lowered" | "static"`:

- `forge.world.core.v1` — `lowered`: declares nothing of its own; `assertV2World` derives the V1 artifact through
  `v2WorldAsV1 → graphToIr` exactly as before. Its `rulepack_id` is read from `V2_RELATION_SOURCE_FAMILIES["2.0"]` (which
  stays the ir_version's *default* profile) and its domain is asked of the kernel's `profileDefaultDomain`, so the tables
  cannot drift.
- `graphonomous.semantic.v0` — `static`: `rulepack_id`, `policies`, `domain: "semantic"`, signature `{orientation:
  directed, texture: solid, arity: 2, endpoint_roles: [source, target]}`, 21 roles each with ports `["node"]`, and 31
  kinds → explicit `[source_role, target_role]` pairs (92 pairs; `*` = any; `SUPERSEDES` same-kind only;
  `STATE_TRANSITION_OF: [[EVIDENCE_STATE_TRANSITION, CLAIM]]`). Declared kinds are `Object.keys(endpoints)`, so a kind
  cannot exist without its constraint. `v2WorldOfStaticProfile(artifact, profile)` reads the row and never asks which row
  it is reading: derived `{semantic_policies: {rulepack_id}, objects}` — objects sorted identity-first `(object_id,
  role)`, `ports` from the role, duplicate ids refused, every terminal checked against the object set and the role's
  ports, signature/kind/pair checked. A static profile implies **no runtime**: no `schemas`, no `state_schema_ref`, no
  admit/film/numeric policies (D-017); a stated one is `WRL_V2_WORLD_MISMATCH`; `downgradeV2ToV1`, `formatNamedWorld`
  and `deriveRuntimeProjection` refuse a static world with `WRL_UNSUPPORTED_FEATURE` (a seal is not a run).
- **GAP-W9 closed at the world gate:** every relation's `revision.policy` must be in the profile's declared `policies`
  (`WRL_UNDECLARED_POLICY`). Validation only — no accepted revision's bytes or id move.
- `canonicalizeV2Artifact`, `serializeV2Artifact`, `v2WorldIdOfArtifact`, `deriveV2Relations`, `expandSeed`: unchanged and
  now work for the static row (real `sem-`, kernel `rel-`/`rev-`). `validateAllocation` NOT widened (D-038). No
  `if (profile_id === …)` anywhere (conformance check 21j greps for it).
- New codes: `WRL_UNDECLARED_POLICY`, `WRL_UNDECLARED_ROLE`, `WRL_UNDECLARED_KIND`, `WRL_UNDECLARED_PORT`,
  `WRL_UNDECLARED_ENDPOINT_PAIR`, `WRL_PROFILE_SIGNATURE_MISMATCH` (18 → 24; old ⊂ new). Exports 47 → 52, none removed.

Alternatives rejected (recorded in the module header, `relation-v2.js:204-349`): keying by `ir_version` (forces every
profile to be a new encoding); a `deriveWorld` function per row (code per profile — a branch in a costume); deriving
`schemas`/`state_schema_ref`/full `semantic_policies` for a static row from defaults (a no-op runtime claim sealed into
identity); widening `validateAllocation` to `gsem-`; a separate served data module. Prior art: `research/R11_STATIC_PROFILE_PRIOR_ART.md`
(JSON Schema `$vocabulary` refuse-if-unknown; OCI `artifactType` / in-toto `predicateType` inside the hashed bytes; JWT
`alg` as the named "hashed but never validated" failure; Sigstore/SRI "recompute, never trust the stated copy").

## Owning-layer test run

- **Before (tests added, code at `1f4c5fd`)** — `WRL-P0/failing-before.txt`: `891 passed, 9 failed`. The graphonomous
  seal → `WRL_UNSUPPORTED_PROFILE`; the GAP-W9 case: a forge world with `policy: "anything.at.all"` **sealed** to
  `sem-b9b0c08987e28696c0cba7179de31288e3bfce7f5e3a971e6b785b0a67f8cdab` (the bug, visible).
- **After** — `WRL-P0/after.txt`: **`900 passed, 0 failed (70 annotated doc blocks of 115 swept, 26/26 capabilities cited)`**
  (baseline `WRL-P0/baseline.txt`: 890/0). Re-run by the Graphonomous session at `b072db0`: 900/0.
- **Identity non-regression** — `WRL-P0/bytediff.txt` (pinned `git show 1f4c5fd:` copies vs live): V1 DEMO/STARTER `sem-`
  and pinned constants SAME; `migrateV1ToV2` bytes, `sem-` and full `rel-`/`rev-` lists SAME; the forge named specimen
  bytes + `sem-` SAME; all 5 projection vectors old == new == pinned wire; 13 pre-existing exports value-identical.
  Verdict line: `NO BYTE OR ID MOVED`. Same script: GAP-W9 pinned → `sem-b9b0c089…`, repaired → `WRL_UNDECLARED_POLICY`.
- **Profile row vs Graphonomous declaration** — `WRL-P0/reconcile.txt`: all 8 facets of `V2_PROFILES["graphonomous.semantic.v0"]`
  agree with `WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json` (D-037 pairs form).

## Re-run of the exposing case

`WRL-P0/reproducer-output.json`: the minimized world seals to
`sem-282c71b69c1c637f1e386424e83986fbc323237177190573e08da4e724d95bc2` (870 canonical bytes); relation
`rel:WITNESSES:receipt:sha256:abc:claim:crosswalk:E-48` → `rel-b1180b9bb63ff2deb88f51b71098906193e82cee38db54e4506ac9576c69ac97`,
`rev-8da1d819f998fe57d1ac5f55668404b0a9e3fa00f8bd5d0a5c43f3a178c6ad21`, `kernel_agrees: true` (re-derived through
`relationIdFromAllocation(namedInitialAllocation(sem, name))` and `relationRevisionId`). The full G0-C worlds are sealed
in Phase C (see STATUS.md / EVIDENCE.md).

## Not closed by this receipt

`OBJECT_ID_RE = /^\w+$/` restates the kernel's private `IDENT_RE` for objects (documented in the module) rather than
adding a kernel export. No `spec.html` pending-register row: there is no stated D8 rule number for static profiles and
the harness refuses a row naming an unstated rule — a spec-text follow-up for the WRL owner, not a code gap.
