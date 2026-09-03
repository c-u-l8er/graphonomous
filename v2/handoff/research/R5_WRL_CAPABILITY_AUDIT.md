# R5 — WRL capability audit for Graphonomous G0

**What was audited.** `/home/travis/ProjectAmp2/WRL` at `1f4c5fd4cf50ce65e3939fe1981efb9bb3363aba` (HEAD, 2026-08-28, "The shared nav moves 0.8.2 to 0.12.0 …"; working tree clean). The three modules that matter are older than HEAD and untouched by it: `wrl.js` (2026-07-25), `relation-identity.js` (07-26), `relation-v2.js` (07-27). Python spine cross-read at `/home/travis/ProjectAmp2/TRVM/forge/wrl_canonical.py` and `wrl_ir.py`; scope statement `/home/travis/ProjectAmp2/TRVM/FORGE_SEMANTIC_IR_v1.md`.

**Conformance observed.** `node test/conformance.mjs` → `890 passed, 0 failed (70 annotated doc blocks of 115 swept, 26/26 capabilities cited)`, 0.27 s wall, Node v25.2.1. This equals the state recorded in `WRL/PACKET_README.md:30` and `WRL/HANDOFF_D8_PATH_B.md:1475-1476` (`128 rows · 110 model · executable · model debt 0`).

**Method.** Read-only; nothing under `WRL/` or `TRVM/` was modified. Every claim is a file:line or the output of one of three scratch probes (`gpr0/wrl-scratch/q1_surface.mjs`, `q2_v2.mjs`, `q3_canon.mjs`), reproduced verbatim where load-bearing.

**Verdict.** WRL today is one frozen circuit profile: five typeable roles, two edge kinds, and no code path that declares a new role, kind, profile, attribute or texture. Beneath that closed surface is a general, executable *relation model* (Semantic IR 2.0): `{identity_seed, revision}` with `domain / kind / endpoints[{terminal, role}] / orientation / texture / attributes / policy`, and `rel-`/`rev-` ids derived by pure functions that accept any domain, any kind, n-ary endpoints and nested attributes. One choke point closes it — the V2 world gate projects every relation to a V1 edge and hands it to the frozen validator — so a G0 `evidence.SUPPORTS` hashes in the kernel and is refused at the seal with `WRL_UNSUPPORTED_FEATURE`. The canonicalizer is generic and reusable. The ledger (§D8.3/§D9) and `ProfileSchemaV1` (§D6.1) have zero code in WRL or TRVM.

---

## 1. Q1 — the writable surface today

### 1.1 What can be spelled and sealed to a `sem-`

| Thing | Members | Where it is hard-coded |
|---|---|---|
| Profile | exactly one: `forge.world.core.v1` | `wrl.js:55`; refused otherwise at `wrl.js:920-923` (`validateGraph`); Python `wrl_canonical.py:37, 599-602, 1010-1013` |
| Surface roles (5) | `pulser→Pulser`, `relay→Relay`, `door→Door`, `spinner→Spinner`, `orb→Orb` | `ROLE_TOKEN` `wrl.js:536-537` (module-private), `SURFACE_ROLE_IDS` `:74` |
| Registry-only role (1) | `Mailbox` — in the IR, unwritable in source, `formatCore` refuses to emit it | `ROLE_IDS` `:64`, `UNWRITABLE_ROLE_IDS` `:75-76`, `formatCore` `:1334-1344`; spec §14b `spec.html:611-649` |
| Ports (frozen per role) | Pulser `{out:sig_out}`, Relay `{out:sig_out,in:sig_in}`, Door `{in:sig_in}`, Spinner `{out:socket,in:sig_in}`, Orb `{in:pose}`, Mailbox `{}` | `PORTS` `wrl.js:79-86`; a `{…}` group is *checked against* this, not defined by it (`validatePortProjection` `:726-734`) |
| Edge kinds (2) | `--sig-->` → `SignalWire` (`sig_out→sig_in`), `--socket-->` → `SocketControl` (`socket→pose`) | `EDGE_TAG` `:538`, `EDGE_KINDS` `:66`, `EDGE_PORTS` `:88-91` |
| Config keys | Pulser: `mode, period, phase, epoch` (+ sugar `every K`, `every K, phase P`, `once at E`); Spinner: `w, n, rotor` (dotted 4 lanes or named `identity/reverse_x/reverse_y/reverse_z/quarter_turn_z`), `configurable` (flag or `=true/false`); Relay/Door/Orb: **none**; Mailbox (unwritable): `w, cap` | `CONFIG_GRAMMAR` `wrl.js:601-608`, `ROLE_CONFIG_SCHEMA` `:93-102`, rotor tables `:221-264`, `CLOCK_SUGAR_FORMS` `:266` |
| Textures | only `--` (solid). `~~`, `==`, `!!` are refused at parse | `wrl.js:859-863`; tiers table `reference.html:591-594` |
| Fan-in law | at most one edge per input port (`WRL_CONTROLLER_CONFLICT`) | `wrl.js:990-1005` |
| Identifiers | `[A-Za-z0-9_]+`, no `__`; `-` is not an identifier char; `#` is never a comment | `wrl.js:915, 952-955`; probe below |

The spec's own summary agrees: "Five roles, two edge kinds, one grounded texture. That is the whole language you can type today." (`WRL/docs/spec/README.md:66-67`).

### 1.2 Is there any code mechanism to declare a new profile, role or kind? **No.**

- `validateProfileHeader` (`wrl.js:680-716`) accepts any `profile <id>` token syntactically; `validateGraph` refuses every id but the constant (`wrl.js:920-923`). No registry keyed by profile id, no loader, no schema type exists.
- The only profile-keyed table anywhere is `PROFILE_DEFAULT_DOMAIN = { "forge.world.core.v1": "signal" }` (`relation-identity.js:232-234`) — one frozen row, a placeholder "so that a second profile cannot arrive without stating its default". The admission tuples (`relation-identity.js:201-210`, `relation-v2.js:177-182`) each list one profile and one rulepack.
- `grep -rn 'ProfileSchemaV1|profile_schema|RelationSignature' --include=*.js --include=*.py WRL TRVM/forge` → **zero hits in code** (prose only). Python agrees: "The entire executable v1 role registry is these five (closed)", "New built-in roles are additive v1.x" (`FORGE_SEMANTIC_IR_v1.md:42, 75`); `ROLE_IDS` `wrl_canonical.py:49`; unknown fields `WRL_UNKNOWN_ARTIFACT_FIELD` (`:483-495`).

### 1.3 Probe: what a G0 spelling gets today (`q1_surface.mjs`, verbatim)

```
role claim                 => WRL_UNSUPPORTED_FEATURE @line 2: role 'claim' not in the frozen v1 surface registry [pulser, relay, door, spinner, orb]
role claim w/ ports        => WRL_UNSUPPORTED_FEATURE @line 2: role 'claim' not in the frozen v1 surface registry [pulser, relay, door, spinner, orb]
edge tag supports          => WRL_UNSUPPORTED_FEATURE @line 4: edge tag 'supports' (only sig|socket in IR v1)
edge tag SUPPORTS uc       => WRL_UNSUPPORTED_FEATURE @line 4: edge tag 'SUPPORTS' (only sig|socket in IR v1)
new profile id             => WRL_UNSUPPORTED_FEATURE @line null: unknown profile 'graphonomous.g0.v1'; this compiler only serves forge.world.core.v1
relay config key           => WRL_UNKNOWN_CONFIG_KEY @line 2: Relay has no config key 'evidence_state'; it accepts nothing
attributed edge            => WRL_UNSUPPORTED_FEATURE @line 4: bad edge notation '[p0] --sig(weight=1)--> [r0]'
qualified kind             => WRL_UNSUPPORTED_FEATURE @line 4: bad edge notation '[p0] --evidence.supports--> [r0]'
async texture ~~           => WRL_UNSUPPORTED_FEATURE @line 4: route texture in '[p0] ~~sig~~> [r0]': async ~~ / fault !! / verified == are transition classes, not IR v1 edges
ports-free relay {}        => WRL_PORT_SIGNATURE @line 2: Relay ports [] do not match the frozen signature [sig_in, sig_out]
relay no brace group       => sem-fea8cc9151434f7537fdf29940a9ecd5674dc5b8bfa63c9f7eef86a0d384028b
empty world                => sem-b5bdc908d2ce549a46fc8ae95d39c34e1deb245e282075730e5436097433fae6
ir 2.0 through V1 spine    => WRL_UNSUPPORTED_FEATURE @line 2: unrecognized WRL notation 'ir 2.0'
id with dash               => WRL_UNSUPPORTED_FEATURE @line 2: unrecognized WRL notation '[relay:claim-1]{sig_in, sig_out}'
```

Role and edge-tag refusals come from the parser (`wrl.js:868-872`, `:842-845`); the profile refusal comes from `validateGraph` and so carries no line. The two spellings that *did* seal matter: a declaration without a brace group is legal (ports come from the role table), and the empty world seals — so an objects-only G0 world would be representable if roles existed. `CODES` has 22 entries, 18 browser-raisable (`wrl.js:112-147`); the relation modules add 20 + 18 codes outside `W.CODES` (`relation-identity.js:125-166`, `relation-v2.js:126-163`).

---

## 2. Q2 — Semantic IR V2 (`relation-v2.js`)

### 2.1 Shape

A V2 artifact is the V1 artifact with `ir_version:"2.0"` and `relations` in place of `edges`; the two keys are mutually exclusive in both directions (`WRL_LEGACY_EDGES_IN_V2` `relation-v2.js:466-473`; `WRL_RELATIONS_IN_V1` `relation-identity.js:310-316`). `profile_id` does **not** move (`relation-v2.js:55-70`; spec D8.9 `spec.html:3150-3165`).

A relation record is exactly `{ identity_seed, revision }` (`V2_RELATION_FIELDS` `relation-v2.js:358`); storing `world_id`, `relation_id` or `revision_id` is refused by name (`DERIVED_NEVER_STORED` `:366-370`, probe: `WRL_BAD_V2_ARTIFACT | fieldPath=relations[].relation_id`).

**Seed variants** (`V2_INITIAL_SEED_VARIANTS` `:213-214`; fields computed from the kernel's `ALLOCATION_FIELDS` `relation-identity.js:712-716` minus `world_id`, `:231-235`):

| variant | seed fields | who may write it |
|---|---|---|
| `named-initial` | `{relation_name}` | an author (`V2_AUTHORABLE_SEED_VARIANTS` `:249-250`); the only surface spelling is `[name]: [a] --sig--> [b]` (`:1447, 1474-1492`) |
| `legacy-edge` | `{kind, src, dst}` | the V1→V2 migration only (`assertImportableSeed` `:827-838`); an author is refused `WRL_UNWRITABLE_SEED` |
| `granted` | — not a seed; runtime-only (§D8.4) | refused in initial bytes: probe `WRL_UNWRITABLE_SEED` |

**Revision fields** (kernel `REVISION_FIELDS` `relation-identity.js:342-343`): `domain, kind, endpoints, orientation, texture?, attributes, policy`. Endpoint = `{ terminal: {object_id, port}, role }` with `role ∈ source|target|peer|terminal` (`:351`), `orientation ∈ directed|symmetric|acausal` (`:353`), texture `∈ solid|async|verified|fault` (`:422`), texture required for directed / forbidden for acausal (`:449-453, 640-651`), terminals unique per relation (`:595-605`), endpoints sorted by role-enumeration-then-terminal (`:672-689`). Any field outside the seven is refused (`:540-544`), and the seven backpointer names are refused as `WRL_REVISION_BACKPOINTER` (`:459-461, 531-538`).

### 2.2 How the three ids derive (`spec.html:3091-3093`; code `relation-v2.js:685-735`)

```
canonicalize → world_id = "sem-" + sha256(bytes) → expandSeed(world_id, seed) = allocation
            → relation_id = "rel-" + sha256(serializeArtifact({tag:"WRL_RELATION", ...allocation}))   relation-identity.js:899-903
            → revision_id = "rev-" + sha256(serializeArtifact(canonicalizeRelationRevision(rev)))     relation-identity.js:692-695
```

The preimages, as emitted by the probe for the named starter world:

```
rel- preimage: {"relation_name":"clock_feed","tag":"WRL_RELATION","variant":"named-initial","world_id":"sem-b285cdd1…12dd66"}
rev- preimage: {"attributes":{},"domain":"signal","endpoints":[{"role":"source","terminal":{"object_id":"p0","port":"sig_out"}},{"role":"target","terminal":{"object_id":"r0","port":"sig_in"}}],"kind":"SignalWire","orientation":"directed","policy":"forge.world.core.rules.v1","texture":"solid"}
```

For G0: `rel-` is world-scoped — editing any relation moves the `sem-` and therefore every `rel-` (D8.10 cl.5, `spec.html:3235-3243`) — while `rev-` is world-independent (the `rev-9e4c536c…` above is also the pinned V1 fixture's first edge in `test/projection-vectors.json`). A claimed world id is checked, never used (`relation-v2.js:754-759`).

### 2.3 Byte-for-byte: the starter world as a named V2 world

Source (`ir 2.0` header is mandatory and second; `relation-v2.js:1383-1423`, spec D8.15 `spec.html:3587-3607`):

```
profile forge.world.core.v1
ir 2.0

[pulser:p0](every 2){sig_out}
[relay:r0]{sig_in, sig_out}
[spinner:sp](w=16, n=8, rotor=quarter_turn_z, configurable){sig_in, socket}
[orb:ob]{pose}

[clock_feed]: [p0] --sig--> [r0]
[drive]: [r0] --sig--> [sp]
[pose_out]: [sp] --socket--> [ob]
```

`admitWorldSource` → `family: v2`, `semanticWorldId = sem-b285cdd12b3a7b923842cb6ec159238c8299ddfb0ef3153e5ddb17e12d12dd66`; the 2,055 canonical bytes:

```
{"ir_version":"2.0","objects":[{"object_id":"ob","ports":{"in":["pose"]},"role":"Orb","state_schema_ref":"state.orb.v1","static_config":{}},{"object_id":"p0","ports":{"out":["sig_out"]},"role":"Pulser","state_schema_ref":"state.pulser.v1","static_config":{"clock":["periodic",2,0]}},{"object_id":"r0","ports":{"in":["sig_in"],"out":["sig_out"]},"role":"Relay","state_schema_ref":"state.relay.v1","static_config":{}},{"object_id":"sp","ports":{"in":["sig_in"],"out":["socket"]},"role":"Spinner","state_schema_ref":"state.spinner.v1","static_config":{"configurable":true,"n":8,"rotor":[181,0,0,181],"w":16}}],"profile_id":"forge.world.core.v1","relations":[{"identity_seed":{"relation_name":"clock_feed","variant":"named-initial"},"revision":{"attributes":{},"domain":"signal","endpoints":[{"role":"source","terminal":{"object_id":"p0","port":"sig_out"}},{"role":"target","terminal":{"object_id":"r0","port":"sig_in"}}],"kind":"SignalWire","orientation":"directed","policy":"forge.world.core.rules.v1","texture":"solid"}},{"identity_seed":{"relation_name":"drive","variant":"named-initial"},"revision":{"attributes":{},"domain":"signal","endpoints":[{"role":"source","terminal":{"object_id":"r0","port":"sig_out"}},{"role":"target","terminal":{"object_id":"sp","port":"sig_in"}}],"kind":"SignalWire","orientation":"directed","policy":"forge.world.core.rules.v1","texture":"solid"}},{"identity_seed":{"relation_name":"pose_out","variant":"named-initial"},"revision":{"attributes":{},"domain":"signal","endpoints":[{"role":"source","terminal":{"object_id":"sp","port":"socket"}},{"role":"target","terminal":{"object_id":"ob","port":"pose"}}],"kind":"SocketControl","orientation":"directed","policy":"forge.world.core.rules.v1","texture":"solid"}}],"schemas":{"epoch_input_schema":"EpochInputV1","observable_schema":"EpochResultV1","runtime_state_schema":"RuntimeStateV1"},"semantic_policies":{"admit_policy_id":"admit_candidate_min_firstreceipt_v1","film_schema_id":"film.v0.7","numeric_policy_ids":["POLICY_FORGE"],"rulepack_id":"forge.world.core.rules.v1"}}
```

Derived: `clock_feed → rel-0ec8f21e… / rev-9e4c536c…`; `drive → rel-c04e574b… / rev-c6fe685a…`; `pose_out → rel-0840df86… / rev-4db6858e…`. The execution view is byte-identical to the V1 starter world (`execution_view_id = sem-67e954cf…60ae`, `coincident: false`). `migrateV1ToV2(starter)` yields `legacy-edge` seeds and a different world, `sem-d0c8cb88…30d216`; `downgradeV2ToV1(·,"1.0")` is byte-exact against the V1 bytes (probe: `true`). Note `attributes:{}` is emitted, not elided — V2 does not carry §D8.8's elision rule.

### 2.4 Are relation attributes implemented? **In the bytes and the kernel, yes; through the seal, no.**

`attributes` is a required record field, hashed into `rev-`, and the kernel accepts any nested string/int/bool/list/object value (probe: `attributes: {tags:["a","b"], loc:{file:"x", line:3}}` → ACCEPTED; a float `0.5` → `WRL_NUMERIC_RANGE` from the serializer). But `v2WorldAsV1` (`relation-v2.js:536-568`) projects every relation through `projectRelationRevisionToV1Edge`, which refuses any non-empty attributes (`relation-identity.js:931-935`), any domain but `signal` (`:940-944`), any kind outside `EDGE_PORTS` (`:918-922`), any non-directed orientation (`:923-926`), any arity ≠ 2 (`:927-930`), any texture but `solid` (`:952-956`). The module's own header names this the profile limit and the fork point: "A wider profile arrives with its own projection, and this function is where the fork goes" (`relation-v2.js:529-534`).

**Mutation probes on the sealed V2 starter artifact** (`q2_v2.mjs §d`, through `serializeV2Artifact` → `assertV2Artifact` → `assertV2World`):

| mutation | result |
|---|---|
| `revision.kind = "supports"` | `WRL_UNSUPPORTED_FEATURE` fieldPath=`kind` — *relation kind 'supports' has no V1 edge form* |
| `revision.domain = "evidence"` | `WRL_UNSUPPORTED_FEATURE` fieldPath=`domain` — *a V1 edge encodes the signal domain; a evidence relation has no V1 form* |
| `revision.attributes = {evidence_state:"open"}` | `WRL_UNSUPPORTED_FEATURE` fieldPath=`attributes` — *a V1 edge carries no attributes …* |
| `revision.texture = "async"` | `WRL_UNSUPPORTED_FEATURE` fieldPath=`texture` |
| orientation `symmetric` / two `peer`s | `WRL_UNSUPPORTED_FEATURE` fieldPath=`orientation` — *a V1 edge is directed* |
| third endpoint (2 targets) | `WRL_UNSUPPORTED_FEATURE` fieldPath=`endpoints` — *a V1 edge has exactly two endpoints; this relation has 3* |
| `revision.provenance = {…}` | `WRL_BAD_RELATION_REVISION` fieldPath=`provenance` — *unknown field(s) provenance* |
| `revision.predecessor = "rev-0"` | `WRL_REVISION_BACKPOINTER` |
| `object.role = "Claim"` | `WRL_UNSUPPORTED_FEATURE` fieldPath=`role` — *role 'Claim' not in the frozen v1 registry* (the spine's own code, via `graphToIr`) |
| `profile_id = "graphonomous.g0.v1"` | `WRL_UNSUPPORTED_PROFILE` |
| `granted` seed | `WRL_UNWRITABLE_SEED` |
| duplicated relation | `WRL_CONTROLLER_CONFLICT` (the profile's fan-in law, in either encoding) |
| extra unwired `Relay` object | **ACCEPTED** (objects need no relations) |
| `revision.policy = "graphonomous.g0.rules.v0"` | **ACCEPTED** — sealed to a new `sem-` |

The last row needs a ruling (G9 below): `policy` is checked only as a non-empty string (`relation-identity.js:546-551`), never against the artifact's rulepack, yet hashed into `rev-`. It is the one free-text slot that survives the gate, and the wrong place to smuggle G0 meaning (`spec.html:1086-1089`).

### 2.5 The kernel is open; only the gate is closed (`q2_v2.mjs §e`)

Called directly, `relation-identity.js` hashes a G0 relation without complaint:

```
validateRelationRevision(G0 SUPPORTS)        => ACCEPTED
rev- for a G0 SUPPORTS revision: rev-c29c2cfe4333195effd3bf205be1a83c1c4df5728f665b6684c1803c73315467
canonical rev bytes: {"attributes":{"evidence_state":"open","scope":"computedriven/edge","source_loc":"STACK_GAP_REGISTER.md:12"},"domain":"evidence","endpoints":[{"role":"source","terminal":{"object_id":"receipt_42","port":"asserts"}},{"role":"target","terminal":{"object_id":"claim_7","port":"subject"}}],"kind":"SUPPORTS","orientation":"directed","policy":"graphonomous.g0.rules.v0","texture":"solid"}
rev- for a 2-source hyperarc:  rev-f2f02de487c1517a7255b5e9d882c6fd60c9d4ad6b9d93d3ab2bcc256896b84d
rel- from namedInitialAllocation(sem-000…0,'supports_1'): rel-08309201456206086314aa04fba3b97e9c2e9426889a80d7c2f2bde5197f6e99
kernel: projectRelationRevisionToV1Edge(G0)  => WRL_UNSUPPORTED_FEATURE | fieldPath=kind
```

The register records this as law: `the-revision-model-is-family-neutral` (D8.9, `spec.html:4711`). An adapter can use WRL's revision canon and id arithmetic for G0 records today; it cannot obtain a `sem-` for a G0 world, so any `rel-` it mints is scoped to a `world_id` WRL did not issue.

---

## 3. Q3 — the canonical-bytes discipline

### 3.1 The rules, as implemented

`serializeArtifact` is `canonicalJson` (`wrl.js:1196-1215`): recursive; keys sorted by JS default string sort (UTF-16 code units); `,`/`:` separators, no whitespace; BigInt as its own decimal digits; any finite non-safe-integer `number` throws `WRL_NUMERIC_RANGE`; all else via `JSON.stringify`. It reproduces Python's `json.dumps(_plain(obj), sort_keys=True, separators=(",", ":"))` (`wrl_canonical.py:962-977`) under the stated precondition "an ASCII string, an integer, a boolean, or a list/object of those" (`wrl.js:13-17`). Spec text: §11 (`spec.html:509-522`) and the artifact table (`reference.html:362-397`). `null` occurs in practice and both spines emit it.

### 3.2 Probe (`q3_canon.mjs`), JS vs Python on the same inputs

| input | `serializeArtifact` (JS) | `json.dumps(sort_keys, compact)` (Py 3.13) | agree? |
|---|---|---|---|
| `{b:1,a:[3,{z:true,y:null}],c:"x"}` | `{"a":[3,{"y":null,"z":true}],"b":1,"c":"x"}` | same | yes |
| `{n: 2^63−1}` / `2^64−1` (BigInt / int) | exact digits | exact digits | yes |
| `{n: 9007199254740992}` (Number) | **throws** `WRL_NUMERIC_RANGE` | `{"n":9007199254740992}` | JS refuses |
| `{f:1.5}` | **throws** `WRL_NUMERIC_RANGE` | `{"f":1.5}` | JS refuses |
| `{x:NaN}` / `{x:Infinity}` | `{"x":null}` (silent) | `{"x":NaN}` (invalid JSON; `allow_nan=False` raises) | **no** |
| `{x:-0}` | `{"x":0}` | `{"x":-0.0}` | no (float anyway) |
| `{x:undefined}` / `[1,undefined,2]` | `{"x":undefined}` / `[1,,2]` — **invalid JSON, no throw** | n/a | hazard |
| `{d:new Date(0)}`, `{m:new Map()}`, `{f:()=>1}` | `{"d":{}}`, `{"m":{}}`, `{"f":undefined}` | n/a | hazard |
| `{s:"é", u:"☃", ctl:"\n"}` | `{"ctl":"\n","s":"é","u":"☃"}` | `{"ctl":"\n","s":"é","u":"☃"}` (default `ensure_ascii=True`) | **no** |
| `{del: U+007F}` | the literal DEL byte | `""` — even with `ensure_ascii=False` | **no** |
| keys `é ü z Z _ 1 a` | `1 Z _ a z é ü` | same order (escaped) | order yes, bytes no |
| `{a:{},b:[]}` | `{"a":{},"b":[]}` | same | yes |

### 3.3 RFC 8785 (JCS) compatibility

Under the artifact restriction (ASCII strings, safe integers, booleans, null, arrays, objects) the JS output is byte-identical to JCS: JCS sorts by UTF-16 code units (so does `Array.prototype.sort` on strings), uses `JSON.stringify` string escaping, and forbids whitespace. Three divergences sit exactly at the restriction's edge:

1. **Integers above 2^53.** JCS serializes numbers as IEEE-754 doubles; a 64-bit rotor lane would be rounded. WRL emits exact digits (`wrl.js:1191-1197`), and the C.4.1 exact reader exists because a general JSON reader rounds them (`relation-v2.js:2023-2072`; negative vector `an-unsafe-integer-rounded`). WRL's canon is JCS-compatible only within ±(2^53−1), which `strictInt` enforces for every scalar except rotor lanes (`wrl.js:189-205`).
2. **Non-ASCII and U+007F.** JS/JCS emit them literally; the Python spine escapes them. "ASCII strings only" is load-bearing for JS↔Python parity, not a simplification.
3. **NaN/Infinity/undefined/exotic objects** are unguarded in JS: `null`, an invalid `undefined` token, or `{}` come out without a throw. Harmless for pre-validated artifacts; a real hazard for reuse.

### 3.4 Is `serializeArtifact` reusable for arbitrary records? **Yes — it is already used that way in-repo.**

It is not coupled to the artifact schema: the kernel canonicalizes terminals, allocations and seeds with it (`relation-identity.js:394, 410, 831, 902, 1016`) and the wire record too (`relation-v2.js:2235-2241`). Graphonomous can reuse it for normalized evidence records that are pre-validated to the closed value domain (ASCII or pre-escaped strings, safe ints or BigInt, no floats, no `undefined`, plain objects). The missing half is the reader: `parseExactJson` — refuses duplicate keys, whitespace and non-integral numbers, then re-serializes to prove canonical form (`relation-v2.js:2075-2199`) — is **module-private**, reachable only via `verifyRuntimeProjection`. Exporting it is the smallest change that makes the canon reusable end-to-end.

---

## 4. Q4 — the grow-only ledger and provenance: specified only

### 4.1 What the spec says

- **D8.3**: a `RelationRevision` carries no provenance; "how a revision came to be proposed is carried by the ledger event" (`spec.html:2311-2319`); the homes table (`:2322-2329`) puts *offered* evidence on the event and *checker* evidence on the acceptance receipt.
- **Ledger facts** (`:2193-2206`): `RelationAttached { allocation, revision_id, provenance, offered_evidence }`, `RelationRevised { relation_id, expected_prior_revision, next_revision, … }`, `RelationRetired { relation_id, expected_prior_revision, … }`, and period-0 `InitialRelationDeclared { allocation, revision_id }`.
- **D8.2**: one home for lifecycle; `current_revision(relation_id, ledger_prefix)` is a fold (`:2255-2262`).
- **D9**: eight operations (`:4059-4068`); "the ledger grows; the active view does not" — `active_topology(sealed_artifact, ledger_prefix, period)` (`:4093-4109`); eight obligations per operation (`:4111-4126`); classification before acceptance (`:4150-4157`); what D9 owes (`:4954-4962`). Draft rules D9.1–D9.5 sit at `:4333, 4200, 4438, 4262, 4533`.

### 4.2 What the code has

`grep -rn 'offered_evidence|IdentityCreated|RelationAttached|RelationRevised|RelationRetired|attachRelation|reviseRelation|retireRelation' --include=*.js --include=*.py WRL TRVM/forge` → **zero hits**. Executable pieces that touch the lifecycle boundary, exhaustively:

| executable | what it is | where |
|---|---|---|
| backpointer refusal | a revision naming its predecessor is `WRL_REVISION_BACKPOINTER` | `relation-identity.js:459-461, 531-538` |
| provenance-out-of-value | `provenance` in a revision is an unknown field, refused | `:540-544` (probe above) |
| period-0 declaration | `deriveRelations`/`deriveV2Relations` produce `{allocation, relation_id, revision, revision_id}` per relation — the note calls them "InitialRelationDeclared facts for period 0" but no typed record exists | `relation-identity.js:1047-1085`, `relation-v2.js:750-783` |
| `RelationImported` facts | the one ledger-shaped record: `{from_world, from_relation, to_world, to_relation}`; who/when/authority deliberately absent "because §D8.3 puts provenance on the ledger EVENT" — an envelope that does not exist | `:1089-1098, 1200-1245` |
| adoption | naming migrated relations, atomically, by re-sealing (moves every `rel-`) — a rename, not a revision | `relation-v2.js:1106-1250` |

Nothing attaches, revises or retires a relation; nothing supersedes without re-sealing; there is no event record, no event id, no fold, no active view.

### 4.3 The register rows that say so (`spec.html`, machine-readable `data-pending-*` rows, read by `test/conformance.mjs:6036-6182`)

128 rows: 110 `model·executable`, 6 `surface·executable`, 1 `surface·awaiting`, 7 `runtime·awaiting`, 4 `film·awaiting`. Every D9 row is awaiting:

```
4781 | unpinned-reference-is-refused      | D9.1 | film    | awaiting
4782 | birth-key-survives-rescheduling     | D9.2 | runtime | awaiting
4783 | evidence-does-not-fork-structure    | D9.2 | runtime | awaiting   ("same schedule, different offered_evidence → one structural candidate, two proposal envelopes")
4784 | pack-rehydrates-byte-identically    | D9.3 | film    | awaiting
4785 | missing-object-is-never-a-film      | D9.3 | film    | awaiting
4786 | schedule-carries-no-meaning         | D9.4 | runtime | awaiting
4787 | re-execution-claim-needs-the-code   | D9.5 | film    | awaiting
```

plus the grant/birth rows of D8.4/D8.6 (`:4664, 4670-4672`). The one executable D8.3 row — `provenance-does-not-move-revision-id` (`:4662`) — tests only that provenance is **absent from the value**; no row tests an event carrying it, and no row names RelationAttached/Revised/Retired at all, so the operations table has no falsifier yet. The docs agree: "§D8.4, §D8.6 and all of §D9 do not [run]" (`README.md:265`); "I have not opened grants, dynamic topology, or D9" (`HANDOFF_D8_PATH_B.md:1482-1483`).

---

## 5. Q5 — ProfileSchemaV1 (§D6.1)

**Not implemented anywhere.** Capability row `profile-mechanism | sketched | unshipped | step 3 | §D6.1` (`reference.html:717`); `attributed-relations`/`resolved-terminals` step 4 (`:718-719`), `dynamic-topology` step 8 (`:729`), `domain-profiles` step 11 (`:740`). Code: none (§1.2). D6.1 is deliberately data-only so step 3 needs no expression notation: "Everything in that list is data. It canonicalises and hashes by §11's existing rules" (`spec.html:1240-1242`).

### 5.1 What a minimal G0 semantic profile needs from D6.1 (`spec.html:1219-1238`)

| D6.1 item | G0 need | required? |
|---|---|---|
| 1 primitive & enumerated types | `evidence_state` enum (e.g. `open/supported/falsified/closed/superseded`), identifier, string (source locator), int | **required** |
| 2 units & dimensional relations | none in G0 (no metered quantities) | optional |
| 3 relation signatures (domain, kind, orientation, arity, roles) | domain `evidence` (or `g0`); kinds `IMPLEMENTS, REDUCES_TO, SUPPORTS, FALSIFIES, SUPERSEDES, SCOPED_BY, CLOSES, PRODUCED_BY`; all `directed`; arity 2, roles `source/target` (SUPPORTS/FALSIFIES could be n-ary with several sources — the kernel already allows it) | **required** |
| 4 endpoint-role constraints (which object roles may occupy which endpoint role of which kind) | e.g. `FALSIFIES: source∈{FALSIFIER,EXPERIMENT,RECEIPT}, target∈{CLAIM,LAW,COROLLARY}`; `SCOPED_BY: target∈{PROFILE}`; `PRODUCED_BY: source∈{ARTIFACT,RECEIPT}, target∈{EXPERIMENT,MECHANISM}` | **required** |
| 5 bounded-resource annotations | none | not needed |
| 6 finite resolution tables | possibly later, for folding many SUPPORTS/FALSIFIES into one claim status (a table over the enum) — a derivation, G1 not G0 | optional |
| 7 built-in validators (range, unit, cardinality, uniqueness, non-negativity) | uniqueness of relation names (already enforced by seed uniqueness), cardinality (e.g. SUPERSEDES: ≤1 successor per statement) | partly required |
| 8 canonical defaults | one serialization for an omitted `evidence_state` (elide vs `"open"`) | **required** |

**Two things D6.1's list omits that G0 needs.** (a) A *role declaration* item: D6 prose says a profile fixes "which roles exist" (`:1166-1169`), but the eight items start at types and relation signatures; roles, their port sets and per-role config keys (today `ROLE_TOKEN/PORTS/CONFIG_GRAMMAR`) are not schema data. (b) *Object attributes*: a CLAIM's own fields live in `static_config`, whose key grammar is closed per role (`wrl.js:601-628`); D6.1 speaks only of relation attributes. Both are spec-text additions, not just code.

**Runtime coupling.** Every artifact must carry `semantic_policies` (rulepack, admit policy, film schema, numeric policies) and `schemas` (RuntimeStateV1, EpochInputV1, EpochResultV1), derived from the role set (`wrl.js:1132-1148, 1170-1182`) and gated as a tuple. A semantic graph has none of these to declare; a "static/inert" profile kind is unspecified anywhere in §D6.

---

## 6. Q6 — classified gap list for `STACK_GAP_REGISTER.md`

Classes: SPEC_GAP (specified in Part II, not built) · IMPLEMENTATION_BUG · MISSING_PRIMITIVE (not even specified) · INTEROP_GAP · PERFORMANCE_GAP · NOT_A_STACK_PROBLEM.

| # | G0 need | Class | Evidence | Smallest justified fix / adapter (not implemented here) |
|---|---|---|---|---|
| G1 | Declare semantic entity kinds (CLAIM, LAW, RECEIPT…) | **SPEC_GAP** (+ a spec-text hole) | roles hard-coded `wrl.js:64, 74, 79-86, 536-537, 601-608`; refusal `WRL_UNSUPPORTED_FEATURE role 'claim' not in the frozen v1 surface registry`; Python `wrl_canonical.py:49`, `FORGE_SEMANTIC_IR_v1.md:42,75`; capability `profile-mechanism` sketched/unshipped `reference.html:717`; D6.1 list has no role item `spec.html:1219-1238` vs `:1166-1169` | Make the five registries a `PROFILES[profile_id]` data table (`ProfileSchemaV1` record: roles+ports+config keys, relation signatures, endpoint constraints, enums, defaults) with `forge.world.core.v1` as row one so both pinned `sem-` ids are unmoved; add "role declarations" to D6.1. Interim adapter: none inside WRL — G0 kinds must live outside it. |
| G2 | Declare relation kinds with roles | **SPEC_GAP** | kernel accepts any domain/kind (`relation-identity.js:546-551`, probe `evidence.SUPPORTS` → `rev-c29c2cfe…`); world gate refuses (`:918-922`; probe `relation kind 'supports' has no V1 edge form`); fork point named at `relation-v2.js:529-534`; D8.14 `spec.html:3542-3564` | Profile-declared relation signatures (D6.1 items 3–4) plus a per-profile projection in `v2WorldAsV1`. No encoding change: V2 already stores `domain`/`kind`/roles. |
| G3 | Relation attributes with typed values (evidence state, scope, source location) | **SPEC_GAP** (field exists, type system does not) | `attributes:{}` in every V2 record (bytes above); kernel accepts nested values; gate refuses non-empty (`relation-identity.js:931-935`); "An attribute type system" owed `spec.html:3976`; capability `attributed-relations` sketched/unshipped `reference.html:718` | D6.1 items 1, 7, 8 (enums, validators, canonical defaults) and lift the attributes clause in the profile projection. Value domain is already fixed: ASCII strings, safe ints/BigInt, bools, nested — no floats (`WRL_NUMERIC_RANGE`). |
| G4 | Relation-level provenance / offered evidence | **SPEC_GAP** with a ruling: provenance is *not* in the value | D8.3 `spec.html:2311-2329`; event shapes `:2193-2206`; code refuses `provenance` in a revision (`relation-identity.js:540-544`); zero code for any event record (grep); `RelationImported` note `:1093-1096` | Model-layer only: a canonical `LedgerEvent {op, args, proposer, provenance, offered_evidence}` record with an `evt-` id (D9's "canonical event identity" obligation `:4120`) — needs no runtime. Interim: G0 keeps provenance in its own event records keyed by `rel-`/`rev-`, never inside the revision (this is what D8.3 mandates anyway). |
| G5 | Statement/relation supersession without deletion (RelationRevised/Retired; grow-only ledger; `current_revision` fold) | **SPEC_GAP** | D9 ops table `spec.html:4059-4068`; ledger-grows `:4093-4109`; all seven D9 rows awaiting `:4781-4787`; D9 owes `:4954-4962`; `README.md:265`; `HANDOFF_D8_PATH_B.md:1482-1483`; only lifecycle-shaped code is adoption (a rename by re-seal) | Two distinct things: SUPERSEDES *as a G0 relation kind* is G2. Revising a relation while keeping its `rel-` is D9 op 5: the `rel-`/`rev-` split already makes `(rel, rev₁)→(rel, rev₂)` representable, so the smallest slice is a model-layer `RelationRevised {relation_id, expected_prior_revision, next_revision}` record plus the D8.2 fold, no grants/runtime required for period-0-named relations. Interim: G0 holds the succession in its own ledger of `(rel-, rev-)` pairs. |
| G6 | A profile that is NOT a circuit world | **SPEC_GAP** + **MISSING_PRIMITIVE** | profile constant checked `wrl.js:920-923`, `wrl_canonical.py:599-602, 1010-1013`; tuple gates `relation-identity.js:201-210`, `relation-v2.js:177-182`; mandatory runtime policies/schemas derived from roles `wrl.js:1132-1182`; no "static profile" anywhere in §D6 | Specify a `static` profile kind whose artifact carries a no-op rulepack and omits admit/film/runtime-state policies (or names inert ones), and make `semanticSurfaceForRoles`/`schemasForRoles` profile-driven. Until then a G0 world would have to *claim* `film.v0.7` and `admit_candidate_min_firstreceipt_v1` it cannot honour — a false statement in the identity. |
| G7 | Ports-free objects as endpoints; object-level attributes | **MISSING_PRIMITIVE** (small; adapter exists) | "a terminal identifies a port, not an object" `spec.html:1571-1573`; `validateTerminal` requires a non-empty `port` (`relation-identity.js:399-403`); the only ports-free role, Mailbox, is by design never wired (`wrl_canonical.py:48`); per-role config keys closed (`wrl.js:601-628`) | Adapter with zero WRL change: every G0 role declares one nominal port (e.g. `{node}`), so terminals read `{object_id:"claim_7", port:"node"}` at the cost of an inert field in every `rev-` preimage. Otherwise specify an object-level terminal variant. Object attributes ride G1's per-role config declarations. |
| G8 | Canonicalizer reuse | **NOT_A_STACK_PROBLEM** (core) + **INTEROP_GAP** (edges) + **IMPLEMENTATION_BUG** (guards) | generic, exported, reused in-repo (`wrl.js:1196-1215`; `relation-identity.js:394,410,831,902`; `relation-v2.js:2235`); BigInt >2^53 diverges from RFC 8785; Python escapes non-ASCII/DEL, JS does not (probe §3.2); NaN→`null`, `undefined`→invalid token, Date/Map→`{}` silently; `parseExactJson` private (`relation-v2.js:2075`) | Export `parseExactJson` (or a `canonicalBytes()` that throws on `undefined`/NaN/non-plain objects); G0 pins "ASCII-only strings, integers only" in its normalization rule, or pre-escapes non-ASCII before hashing; do not rely on BigInt records being JCS-comparable. |
| G9 | `revision.policy` unvalidated against the artifact rulepack yet hashed into `rev-` | **IMPLEMENTATION_BUG** (low; needs a ruling) | probe: `policy = "graphonomous.g0.rules.v0"` ACCEPTED and sealed; `relation-identity.js:546-551`; contrast the admission argument `:189-193` | Either check `revision.policy ∈ profile.rulepacks` at the world gate, or rule it free explicitly. Do not use it as a G0 attribute slot. |
| G10 | Performance at G0 scale | **PERFORMANCE_GAP: none measured** | suite 0.27 s; every `canonicalizeV2Artifact` call re-derives and re-validates the whole world (`relation-v2.js:648-678` → `589-623` → `536-568`), and `adoptLegacyRelations`/`deriveV2Relations` call it repeatedly | Not a gap for thousands of relations; unmeasured beyond. Measure before claiming either way. |

**Observation, not a G0 gap.** The spine's exported registries are mutable (`Object.isFrozen(W.ROLE_IDS) === false`), unlike the deep-frozen relation vocabularies (`relation-identity.js:97-118`); not exploitable to mint a G0 world (`ROLE_TOKEN` is private), but the hazard the kernel's header records fixing (`:34-37`).

### What G0 can do with WRL today

1. Reuse `serializeArtifact` + SHA-256 as its canonical-bytes discipline, under the closed value domain.
2. Reuse `canonicalizeRelationRevision`/`relationRevisionId` for `rev-` ids of G0 relations (domain, kind, n-ary roles, textures, nested attributes all hash today) and `relationIdFromAllocation` for `rel-` ids — **with a G0-supplied `world_id`**, since WRL will not seal a G0 world.
3. Adopt the D8 rulings as design constraints now: provenance on the event, not the value (D8.3); one home for lifecycle (D8.2); stable name vs content-addressed value (D8.1); world-scoped relation ids (D8.5).

It cannot type a G0 entity or relation kind, seal a G0 world to a `sem-`, pass a typed attribute through the gate, or record a supersession WRL will read back. Each is a named row above — a gap to record, not to hide.

---

*Probe scripts and raw outputs: `/tmp/claude-1000/-home-travis-ProjectAmp2/ac8f93a5-7380-4895-ae54-fd98459289cc/scratchpad/gpr0/wrl-scratch/{q1_surface,q2_v2,q3_canon}.mjs` (run with `node <file>`; Node ≥ 18).*
