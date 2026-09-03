# R6 — TRVM derive audit for Graphonomous G0

**Subject.** What TRVM offers *today* that a deterministic, content-addressed Graphonomous G0 can use for real, testable participation — and what it cannot.
**TRVM revision.** `fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873`, branch `merge/governance-plane` (HEAD commit "Governance rounds 16 to 18: the derive protocol and the lowering check"). Grid `invariant-grid 1.69.0`, dated 2026-08-18 (`governance/invariant-grid.json`). `derive_protocol.mjs` is **v0.15.0**.
**Method.** Read-only. Three probe scripts under `scratchpad/gpr0/trvm-scratch/` (`probe_a_core.mjs`, `probe_b_canon.mjs`, `probe_c_cas.mjs`) import TRVM modules without touching the tree. I ran `governance/derive_battery.mjs` (it writes nothing) — **DERIVE-BATTERY: PASS — 45/45**. I did **not** run `derive_realm_battery.mjs` (it rewrites `derive_worker.mjs` at lines 524/527) nor any Makefile target. `governance/README.md`: **NOT FOUND**.

---

## 0. Verdict in five lines

1. **Usable now, for real:** `canonicalBytes` (RFC 8785-measured), `artifactRoot`/`resolveArtifact` (a byte-exact CAS with seven named refusal outcomes), `ownCanonical`/`grammar` (ingress hygiene), and `verifiedClaimSemId` (a claim-qualified identity). A Graphonomous record and a projection manifest round-trip through the CAS unchanged (probe C).
2. **Usable now, but thin:** the derivation authority produces a genuine, replayable, footprint-carrying receipt — for **numeric** facts only (`add/sub/mul/len` over reads). Graphonomous can derive counts, not verdicts.
3. **Not expressible:** any rule with quantification, equality, or boolean logic. The frozen core has no `eq`, `and`, `if`, `forall`, `get` — by ruling, not oversight (`CORE_SPEC.extension`, `derive_protocol.mjs:435-438`). The extension path (`{op:"prim"}`) is declared and **not built** (`derivation_language.not_built`).
4. **IC reduction:** no realistic G0 role; defer to G2+ (§5).
5. **Canonicalizers:** TRVM, WRL-JS and Forge-Python are **three separate implementations** that agree only on the intersection domain (ASCII strings, safe integers, booleans, null); they diverge on floats, BigInt, non-ASCII, NaN and lone surrogates (§4, measured).

---

## 1. TRVM-DERIVE-CORE-v1 (Q1)

### 1.1 The grammar, verbatim

`derive_protocol.mjs:389-439` freezes `CORE_SPEC`. Ops (`:413-423`):

```js
const: { fields: ["value"],    returns: "the literal, which must be a canonical value" },
input: { fields: ["name"],     reads: "canonical_inputs ONLY — never read_grants" },
read:  { fields: ["resource"], reads: "read_grants.exact; appends [resource, version] to the footprint" },
scope: { fields: ["query"],    reads: "read_grants.predicates; appends [query, digest] to the footprint" },
cite:  { fields: ["name"],     reads: 'read_grants.exact under the key "warrant:" + name; returns .value.value' },
add/sub/mul: { fields: ["a","b"] }   len: { fields: ["a"], returns: "array length; a non-array operand is refused" }
```

- **Value domain** (`:392-394`): `null | boolean | finite number | string | canonical array | canonical plain object`; Map/Set/Date/class instances/handles refused.
- **Arithmetic** (`:395-397`, enforced `:455-461`): IEEE-754 binary64, **no coercion** (`"2"+"3"` → `program-type: add of non-number`), overflow refused at the operation (`program-arith-non-finite`). **Signed zero** identified with +0 (`:398-402`; probe: `mul(-1,0)` → JS `-0`, canonical bytes `0`).
- **Evaluation order** (`:403-405`): depth-first, `a` before `b` — deterministic but *not* semantic identity.
- **Footprint-as-set** (`:406-412`, `:913-923`): `read_footprint` is sorted+deduplicated; access order with repeats lives in `read_trace` outside the semantic projection. A result whose footprint is not the canonical set of its trace is refused, not normalized (`result-footprint-not-canonical-set`, `:800-810`).
- **Totality** (`:433-434`): "no recursion, no unbounded loop, no general function. Every program terminates in a number of steps bounded by its own node count."
- **Refusal vocabulary** (`:427-432`): `program-malformed-node | program-unknown-op | program-node-fields | program-name-not-a-string | program-const-not-canonical | program-input-missing | program-type | program-arith-non-finite | read-not-granted | scope-not-granted`.
- **Grammar closure** (`:424-426`, enforced `:466-489`): a node's key set must be **exactly** `{op} ∪ fields`; unknown ops, missing and extra fields all refuse at bind time, so "an id is never issued for a program outside the language."

### 1.2 Canonicalization and identities

```js
// derive_protocol.mjs:440
export const CORE_SEM_ID = "core-" + H("TRVM-DERIVE-CORE-SPEC-v1|" + canonicalBytes(CORE_SPEC));
// :492-496
export function programSemId(ast) {
  const v = validateProgram(ast); if (!v.ok) throw new Error(v.reason);
  return "psem-" + H("TRVM-PROGRAM-v2|" + CORE_SEM_ID + "|" + canonicalBytes(ast));
}
```

Measured (probe A): `CORE_SEM_ID = core-0930d6f10070a8e7867b99cbaf6297234fe6fbc174ed25a72388dac9944f3afe`; `programSemId({add (read fb) (input bias)}) = psem-fa4ca55b12ba…` — the same id the round-16 ledger records at §68 (`round-11-ledger.md:208`). Key order in the AST does not move the id (canonical). `core_sem_id` is a content hash of the spec record, not the label — ledger §65 (`:202`): "a bare name is precisely the caller-selected identity the primitive ruling already refuses for `componentReachability`." `ProgramRegistry.bind` severs the AST through `ownCanonical` before hashing (`:504-517`); `verify(id)` recomputes and refuses `program-id-mismatch` (`:527-532`).

### 1.3 Read grants vs. read footprints

- **Grant** = a bounded canonical world slice, keyed by resource: `{exact: {r: {value, version}}, predicates: {q: digest}}`, `grant_id = H("TRVM-GRANT-v1|" + canonicalBytes(read_grants))` (`:627-629`). `checkGrants` (`:631-654`) requires exactly those two tables; `version` may be number or string (`:648`) — a Graphonomous registry revision or content hash fits. The authority resolves the snapshot **once** on its own side via `resolveGrants(reader, want)` (`:661-671`); the reader never crosses the boundary.
- **Footprint** = what the evaluator actually consumed, recorded on access (`:886-902`). `input` addresses `canonical_inputs` only; `read/scope/cite` address `read_grants` only (W-1 repair, `:29-60`).
- **Law** `derivation.grant-footprint-separation@1` (PROPERTY-TESTED, canonical): "The authority validates the footprint as a SUBSET of the grant, at the granted versions and scope digests, on its own evidence and BEFORE any re-derivation."

### 1.4 What a derivation receipt contains

There is no object called "receipt"; the unit of evidence is the **DeriveResult**, produced by `deriveLocallyOwned` (`:951-960`) or by the worker (`derive_worker.mjs:56-60`). Fields (`:711-713`):

```
request_id · program_sem_id · grant_id
semantic_result   { value, witness{op,reads,scopes}, support[], read_footprint{exact[[r,ver]],predicates[[q,digest]]} }
execution_evidence{ implementation_id, read_trace{exact,predicates} }
```

Probe A's actual output for `add(read fb)(input bias)` with `fb=5, bias=2`: `value: 7`, `witness {op:"add", reads:1, scopes:0}`, `support ["fb"]`, `read_footprint.exact [["fb",1]]`, `implementation_id "impl-js-derive-v0.15.0"`. The **semantic projection** — `[request_id, program_sem_id, grant_id, semantic_result]` (`:718`) — is what cross-implementation agreement compares; `execution_evidence` is excluded from comparison and *not* from checking (`derivation.execution-evidence@1`).

The request that binds it: `request_id = "req-" + H("TRVM-REQUEST-v1|" + intent_id + "|" + canonicalBytes(body))` (`:1247`); issuance keeps `request_sem_id = H(canonical request)` (`:1135-1137`, `:1255`).

### 1.5 Re-derivation and replay — built and tested

| check | where | what it does |
|---|---|---|
| `footprintWithinGrant(fp, grants)` | `:825-843` | every claimed read is in the snapshot at the granted version; scope digests equal — fires before any re-derivation |
| `validateForeignResultOwned` | `:975-1003` | schema → containment → **re-derives locally** and compares `canonicalBytes(semanticProjection)` → `foreign-result-divergence`; then trace conformance as a separate verdict |
| `validateFootprintFresh(liveReader, fp)` | `:1058-1074` | temporal: `stale-read: fb granted@1 live@2`, `stale-scope` |
| `DerivationAuthority.accept(req,res)` | `:1395-1483` | issuance → validation → provenance lookup (host observation table) → freshness; returns `{validated, fresh_at_check}` and **never `committable`** (`:1381-1392`) |
| replay determinism | probe A | same request derived twice → byte-identical result (`replay byte-identical = true`); a lie (`value:999`) → `foreign-result-divergence` |

The World side has its own replay jail: `jailedView` (`trvm_world.mjs:313-333`) refuses `undeclared-read`, `footprint-version-mismatch`, `undeclared-scope`, `scope-digest-mismatch`.

**Not claimed by TRVM itself** (`:277-280`, `realm_roadmap.three_separate_scopes`): host confinement, determinism of a long-lived evaluator, TOCTOU-free artifact identity. No signature/MAC — "added when, and only when, the grant crosses a real trust boundary, is persisted and replayed later…" (`:1099-1102`). The issuance and observation tables are in-process `Map`s (`:1156`, `:1175`): **a DeriveResult is not persisted or content-addressed anywhere in the tree.**

### 1.6 `prim` — declared, not built

Grid `derivation_language` (quoted exactly):

> `"not_built": "no prim op exists. The core is frozen; the primitive CATALOG is not, and a prim extension bumps the core version and therefore every program id, deliberately."`
> `"frozen": "TRVM-DERIVE-CORE-v1 is FROZEN as of round 16 — grammar, value domain, arithmetic, signed zero, evaluation order, footprint-as-set, totality and refusal vocabulary — with a content-bound core_sem_id load-bearing inside every program_sem_id. See law:derivation.core-semantics@1."`
> `"first_primitive": "component reachability, and it is chosen because it is materially harder than arithmetic: graph traversal, data-dependent reads, support, adjacency footprints and the phantom-scope case all appear in it at once…"`
> `"primitive_identity": "primitive_sem_id must be content-bound, not a name. H(primitive language/version + canonical input/output contract + semantic specification identity + conformance-vector identity)."`

Confirmed by code: `validateProgram({op:"prim",…})` → `program-unknown-op: prim` (probe A). `realm_roadmap.order[9]` lists "the first named semantic primitive (component reachability)" after native film emission and cross-replay, both still open (`film_planes.trvm_calculus_film.status`: "NO native runtime emits films yet"). Law entries: `derivation.core-semantics@1` **REGRESSION-LOCKED**; `derivation.serialized-boundary@3`, `grant-footprint-separation@1`, `execution-evidence@1`, `footprint-freshness@1`, `grant-issuance@1`, `acceptance-authority@1`, `implementation-provenance@4` all **PROPERTY-TESTED** and canonical; `derivation.environment-confinement@1` **FALSIFIED** by design (the closure API it replaced). No law named `derivation.primitive-identity` exists — **NOT FOUND**; the primitive rule lives only in `derivation_language` prose. Note also that `TRVM/LAWS.md` (Series I binding laws, Series II distribution laws) contains **no** derivation law; the derive laws live exclusively in the grid registry.

---

## 2. Can a Graphonomous rule be written in the frozen core? (Q2)

Rule: *for each record with class TESTED, require ≥1 receipt with `executed=true`; else emit `UNSUPPORTED(record)`.*

### 2.1 The attempt, and exactly where it fails

I wrote each sub-expression in the core's JSON shape and ran `validateProgram` (probe A §4):

```
forall over a set              → program-unknown-op: forall at $
string equality (class=TESTED) → program-unknown-op: eq at $
boolean and                    → program-unknown-op: and at $
if/else (emit UNSUPPORTED)     → program-unknown-op: if at $
field projection (rec.class)   → program-unknown-op: get at $
count filtered (executed=true) → program-unknown-op: count_where at $
prim (the extension route)     → program-unknown-op: prim at $
read with an extra field       → program-node-fields at $: [as,op,resource] wanted [op,resource]
len(scope(receipts))-1         → ok   psem-f74f6852…   (the ONLY fragment that binds)
```

The one program that binds is `sub(len(scope "receipts-of:rec-1"), const 1)`. Evaluated: zero receipts → `-1`; one receipt with `executed:false` → `0`. Two failures are visible in that output:

1. **No verdict op.** `-1` is a number. Nothing in the core turns it into `UNSUPPORTED`; there is no comparison, no boolean, no conditional. The verdict has to be computed by whoever reads the result — i.e. outside the identified program, so it is not covered by `program_sem_id`.
2. **No filter.** `len` counted the unexecuted receipt. Filtering `executed=true` would have to happen inside the World's registered scope query (`trvm_world.mjs:268 registerQuery`), whose function body is *not* part of any identity: `scopeEval` hashes only `qname` and the result (`:277`). The rule's semantics would live in an un-identified JS function on the authority side — precisely the closure-authority shape the whole v0.15 lineage exists to remove.

A third obstacle is TRVM-World-specific: with TRVM's own `World`, `scope(q)` returns a **digest string**, not the member list (`trvm_world.mjs:269-278`, `trackedView` `:306`), so even `len(scope …)` refuses `program-type: len of non-array` there. `checkGrants` (`:637-641`) does not constrain what a predicate's value is, so a *Graphonomous-supplied* reader may legally return the member list under the "digest" slot — probe A §3 shows `len(scope)` = 3 in that configuration — but the grid's vocabulary calls that slot a digest, and this should be recorded as a documented reinterpretation, not assumed.

So the rule cannot be expressed as-is. The core is total and *first-order over numbers*; the Graphonomous rule is a bounded quantifier over records with equality on strings and booleans.

### 2.2 The smallest missing primitives — candidate `prim` catalog entries (NOT implemented)

Per `derivation_language.primitive_identity`, each `primitive_sem_id` = H(language/version | canonical I/O contract | semantic spec identity | conformance-vector identity). Minimal set that closes the rule, each total over a finite grant snapshot:

| candidate | args → returns | why it is minimal |
|---|---|---|
| `eq.canonical/1` | `(a, b)` → boolean; `canonicalBytes(a) === canonicalBytes(b)` | equality is already defined by the canonical domain (`-0 ≡ 0` etc.); no new semantics, one comparison |
| `get.field/1` | `(obj, key: string)` → value or refusal `prim-get-missing` | `read` returns whole values; without projection every field must be its own resource |
| `set.count_where/1` | `(items: array, key: string, expected: value)` → number | one bounded pass; subsumes `len` when `key` is absent |
| `set.all/1` | `(items: array, key, expected)` → boolean | the quantifier; bounded by `items.length` so totality holds |
| `if.value/1` | `(cond: boolean, then: value, else: value)` → value | needed to *emit* `UNSUPPORTED(record)` rather than a number; both branches evaluated (total, no short-circuit semantics to freeze) |

Any `prim` bump moves `core_sem_id` and every `program_sem_id` — intended (`CORE_SPEC.extension`). Alternative without touching TRVM: Graphonomous evaluates the rule itself and records `{rule_sem_id: H(rule text), inputs: [artifact roots], verdict}` in the CAS. That is a **provenance record**, not a TRVM derivation receipt, and the brief's "no decorative TRVM use" means it must be labeled as such.

---

## 3. CAS and certificate (Q3)

### 3.1 What the CAS stores and how it is keyed

`cas.mjs` v0.3.0. Identity: `root-` + SHA-256(`"TRVM-ARTIFACT-ROOT-v2|"` ++ canonical UTF-8 bytes) (`:99-100`, `:128-135`). Root grammar `/^root-[0-9a-f]{64}$/` checked before any path is built (`:117`, `:230-235`). Stores: `directoryStore(dir)` (`<root>.json` holding canonical bytes, `:150-169`), `memoryStore` (`:173-194`), `putArtifact` (producer-only, `:200-206`). Ceiling 8 MiB, applied to bytes before parse (`:125`, `:249`). Resolution (`:225-299`): fatal UTF-8 decode → strict parse → re-canonicalise → **require raw === canonical** → re-derive root → compare. Outcomes: `ok, bad-root-syntax, unresolvable, too-large, invalid-utf8, malformed, non-canonical-wire, root-mismatch` (`:213-215`). `ok` means exactly three things (`:219-224`) and never "accepted".

**Generality — measured (probe C):** a Graphonomous record `{kind:"graphonomous.record", id:"S6", class:"TESTED", claims:[…], receipts:[{executed:true,…}], projected_from:{…}}` → `root-bd9d4c80…`, resolves `ok`, 223 bytes; key reorder → same root; pretty-printed bytes under the honest root → `non-canonical-wire`; a duplicate-key forgery → `non-canonical-wire`; `../proof_bundle` → `bad-root-syntax`. A projection manifest `{kind:"graphonomous.projection", registry_rev, records:[roots…]}` → `root-f986414a…`, resolves `ok`. **Nothing in `cas.mjs` is TRVM-specific**; the five shipped artifacts in `governance/cas/` happen to carry `protocol: TRVM-NESTED-COMPOSITION-v2 / TRVM-BOUNDED-PROOF-v1 / TRVM-BOUNDED-DOMAIN-PROOF-v1`, but the store never reads `protocol`. Limits: JSON-only (no binary blobs), local directory/memory only (no network store), `WIRE_LIMITS` is policy.

### 3.2 What a certificate binds

```js
// certificate.mjs:60-68
verifiedClaimSemId({ protocol, claim_sem_id, aggregate_id, chain_ids })
  → "vclaim-" + H("TRVM-VERIFIED-CLAIM-v1|" + canonicalBytes({certificate_protocol, protocol, claim_sem_id, aggregate_id, chain_ids}))
```

All four required; absence throws `certificate-incomplete: <field>` (probe: `missing chain_ids → certificate-incomplete: chain_ids`). Properties (`:31-35`, spec `TRVM-VERIFIED-CLAIM-v1.md §3`): moves on claim/evidence/chain change, holds on prose edits. **It is not a warrant** (`:37-44`): no registry, signature, or verdict in the preimage; "Whoever cites it must still run the child's own checker." Which field holds a child's `claim_sem_id` is the *citer's* protocol knowledge (`:46-49`, `certificateOf(bundle, claim_field)` `:75-82`).

**Generality:** the id function is protocol-agnostic — probe C minted `vclaim-722d4380…` over a `GRAPHONOMOUS-PROJECTION-v0` claim. The **checker side is not**: `nest_check.mjs:152-155` `IMPLEMENTED_CHILD_PROTOCOLS` knows exactly `TRVM-BOUNDED-PROOF-v1` and `TRVM-BOUNDED-DOMAIN-PROOF-v1` (plus itself), and refuses others (`:584-588`). `live_dag.mjs` asserts *relations, not values* — semantic ids equal the frozen corpus, complete roots may differ (`:24-34`) — a discipline Graphonomous should copy for projection roots (a projection root binds registry bytes; a claim id should not). Useful reusable ingredients: `schema.mjs` `ownSnapshot` (`:64-66`) and `grammar(record,{required,optional})` exact-key-set check (`:77-95`; probe: an extra `verdict` field is reported `unknown`).

---

## 4. Canonical bytes: one rule, three implementations (Q4)

**TRVM** `canonicalBytes` (`derive_protocol.mjs:308-351`): sorted keys (`Object.keys(v).sort()` — JS default sort is UTF-16 code-unit order, which RFC 8785 requires), compact separators, `JSON.stringify` for numbers/strings, refuses non-finite numbers, cycles, non-plain objects, **lone surrogates** (`:298-321`), BigInt (`not-canonical: bigint`). Measured against RFC 8785 vectors and the pinned upstream JCS `outhex/` corpus (`jcs_vectors.mjs:1-50`); the ~10⁸-value number corpus is declared open (`round-11-ledger.md §611`).

**WRL** `canonicalJson` (`WRL/wrl.js:1196-1210`), called by `serializeArtifact` (`:1213-1215`): sorted keys, compact, **BigInt emitted as decimal digits**, and **refuses any finite number that is not a safe integer** (`WRL_NUMERIC_RANGE`). The header states the target: "`json.dumps(obj, sort_keys=True, separators=(",", ":"))`, and every value in a sealed artifact is an ASCII string, an integer, a boolean, or a list/object of those" (`:13-15`).

**Forge Python** `serialize_artifact` (`forge/wrl_canonical.py:972-977`): `json.dumps(_plain(artifact), sort_keys=True, separators=(",", ":")).encode()`; `_plain` (`:962-969`) only flattens tuples. Default `ensure_ascii=True`, `allow_nan=True`.

**Shared canonicalizer?** No. There are two separate copies inside TRVM alone — `derive_protocol.mjs:323` and `observed_execution_host.mjs:94` (different source text, identical output on my probe; `cas.mjs:109` aliases the first) — plus a third in `trvm_world.mjs:181`, plus `cj = JSON.stringify` (unsorted!) used for World scope digests (`trvm_world.mjs:170`, `:277`). WRL and Forge each have their own. Nothing imports across repos.

**Measured divergences (probe B):**

| value | TRVM `canonicalBytes` | WRL `serializeArtifact` | Python `json.dumps` (default) |
|---|---|---|---|
| `{b:1,a:2}` / nested | `{"a":2,"b":1}` | same | same |
| `1.5`, `0.1` | `1.5`, `0.1` | **REFUSED** `WRL_NUMERIC_RANGE` | `1.5`, `0.1` |
| `1e21` | `1e+21` | REFUSED | `1e+21` |
| `1e-7` | `1e-7` | REFUSED | **`1e-07`** |
| `-0` | `0` | `0` | `0` (int) / **`-0.0`** (float) |
| `2^53`, `2^60` (Number) | emitted (`1152921504606847000`, lossy) | REFUSED | same lossy digits |
| BigInt `2^60` | **REFUSED** `not-canonical: bigint` | `1152921504606846976` | `1152921504606846976` |
| `"é"`, `\x7f`, `\x80` | raw UTF-8 | raw UTF-8 | **`é`, ``, ``** (escaped; matches only with `ensure_ascii=False`) |
| keys `😂` vs `דּ` | `😂` first (code unit) | `😂` first | escaped: **`דּ` first** (default); `דּ` first with `ensure_ascii=False` (**code point** order) |
| lone surrogate `\uD800` | **REFUSED** | `"\ud800"` emitted | `"\ud800"` emitted |
| `NaN` | **REFUSED** | `null` | **`NaN`** (invalid JSON) |

So: on WRL's *intended* domain (ASCII strings, safe ints, bools, null) all three agree byte-for-byte, and `wrl.js` states its Python ground-truth ids reproduce (`:19-23`). Outside it they are not the same rule: TRVM is RFC 8785; WRL is a stricter integer-only subset that also *widens* to BigInt; Python is neither (escapes, `-0.0`, `1e-07`, `NaN`, code-point key order under `ensure_ascii=False`). The World's scope digest uses unsorted `JSON.stringify`, so the *same* set enumerated in a different order hashes differently — a real hazard if Graphonomous ever feeds sets into `scope`.

---

## 5. The interaction-calculus reducer — any G0 role? (Q5)

Honest answer: **no realistic G0 role; defer to G2+.** Evidence:

- The reducer is a packed-word WASM/C interaction-net runtime whose thesis is coordination-free *reduction* (`README.md:1-27`); its own findings file frames the contribution as canonical identity for *computations* (`FINDINGS.md:9-14`), not for records.
- The only bridge from the derive language to the calculus is `lowering.mjs`, and `IMPLEMENTED_LOWERED_OPS = ["const","add","input","sub","mul"]` (`:921`); `lower()` refuses `read/scope/cite` with `lower-reads-undecided` (`:2299`) and `len` is "unencoded" (ledger §611). Refinement holds only over "canonical, fully bound input environments" and "the representable target fragment" — non-negative naturals (`REFINEMENT_SCOPE`, `:1134-1160`). A Graphonomous fact contains strings, sets and booleans; none of it reaches the calculus.
- Even for arithmetic the calculus buys nothing G0 needs: identical results with a second, slower execution witnessed by a film. The grid's own ruling keeps the derivation relation and the calculus film as **two transition systems** and refuses to let progress on one be reported as the other (`film_planes.ruling`).
- What G2+ *could* use: the structural-identity/CvRDT layer (`compmem_ic.py`, `semilattice.py`) as a model for merging content-addressed graph replicas — a design reference, not a runtime dependency.

---

## 6. Gap register for `STACK_GAP_REGISTER.md` (Q6)

TRVM `fd0df4c` on `merge/governance-plane`, grid 1.69.0.

| # | Graphonomous need | class | evidence | smallest fix |
|---|---|---|---|---|
| G-1 | Rule evaluation over sets (∀/∃/filter) | **MISSING_PRIMITIVE** (by ruling) | `CORE_SPEC.ops` `derive_protocol.mjs:413-423`; `totality` `:433-434`; probe `program-unknown-op: forall`; `derivation_language.not_built` | catalog entries `set.count_where/1` + `set.all/1` (§2.2); until then compute in the projector and store a provenance record, labeled as such |
| G-2 | String/enum comparison | **MISSING_PRIMITIVE** | no `eq` in ops; probe `program-unknown-op: eq` | `eq.canonical/1` — one `canonicalBytes` equality, total |
| G-3 | Boolean logic + conditional emission | **MISSING_PRIMITIVE** | no boolean-consuming op; `extension` forbids `if` in core `:435-438`; probe `and`/`if` refused | `if.value/1` (both branches evaluated) — no `and/or` needed if the rule is a single quantifier |
| G-4 | Graph traversal primitive (reachability, `REDUCES_TO` closure) | **SPEC_GAP** + MISSING_PRIMITIVE | declared first primitive, "Declared; not built" (`round-11-ledger.md:179`); `realm_roadmap.order[9]` behind two open milestones | nothing smaller than building it; G0 must not wait — traverse in the projector, cite input roots |
| G-5 | Derivation receipts for graph facts | **INTEROP_GAP** | DeriveResult is a real receipt (`:711-713`, probe §1.4) but in-memory only (`#issued`/`#executions` Maps `:1156`,`:1175`), no MAC (`:1099-1102`), never CAS-stored; value language can't hold the fact (G-1..3) | `receipt_root = artifactRoot({request_sem_id, semanticProjection})` — one line using existing `requestSemId` `:1135` + `cas.putArtifact`; TRVM-side, not yet written |
| G-6 | Field access on records | **MISSING_PRIMITIVE** (work-around exists) | `read` returns whole value; probe `program-unknown-op: get` | expose per-field resources (`"rec-1.class"`) from the Graphonomous reader — resource names are free strings (`checkGrants :642-650`); or `get.field/1` |
| G-7 | Set enumeration via `scope` | **SPEC_GAP** (vocabulary) | World returns a digest (`trvm_world.mjs:277`,`:306`); `checkGrants` doesn't constrain it (`:637-641`); digest uses unsorted `JSON.stringify` (`:170`) | rule in `derivation_language`/grid that a predicate value may be a canonical list; and sort before hashing in the World |
| G-8 | CAS for normalized records | **NOT_A_STACK_PROBLEM** | probe C: record + manifest round-trip `ok`; forgeries refused; store never reads `protocol` | use `cas.mjs` as-is; note JSON-only, local-only, 8 MiB policy ceiling (`:125`) |
| G-9 | Projection-root certificate | **INTEROP_GAP** | `verifiedClaimSemId` mints for any protocol (probe `vclaim-722d…`), but only three child protocols are checkable (`nest_check.mjs:152-155`, `:584-588`); "not a warrant" (`certificate.mjs:37-44`) | Graphonomous ships `GRAPHONOMOUS-PROJECTION-v0` + its own checker naming the claim field; copy `live_dag.mjs`'s relations-not-values gate |
| G-10 | One canonicalizer across TRVM/WRL/Forge/Graphonomous | **INTEROP_GAP** | three implementations, measured divergences §4; two copies inside TRVM (`derive_protocol.mjs:323`, `observed_execution_host.mjs:94`) | adopt TRVM `canonicalBytes` as the rule; restrict Graphonomous records to safe-integer/ASCII-or-UTF-8 domain; Python emitters must pass `ensure_ascii=False`, refuse floats/NaN, and sort by UTF-16 code unit |
| G-11 | "TESTED with no executed receipt" diagnostic | **MISSING_PRIMITIVE** | composition of G-1, G-2, G-6; only `len(scope)-1` binds today (probe) | same as G-1..G-3 |
| G-12 | Diagnostic-grade performance | **not measurable** | no Graphonomous-scale workload exists; battery fixtures are 1–3 resources | do not record a PERFORMANCE_GAP without a measurement |

**What is real and testable today, in one sentence:** Graphonomous G0 can adopt TRVM's canonical bytes, its byte-exact CAS, its ingress-ownership and exact-grammar checks, and its claim-qualified certificate identity — all measured here on Graphonomous-shaped data — and can issue genuine, replayable, footprint-bound derivation receipts for **numeric** facts; every rule that decides something is outside the frozen core until a `prim` catalog exists, and the interaction-calculus reducer has no G0 role.

---

### Appendix — probe files (scratch, outside the repo)

- `trvm-scratch/probe_a_core.mjs` — core ids, receipt shape, accept/replay, the Graphonomous rule attempt, type discipline.
- `trvm-scratch/probe_b_canon.mjs` — TRVM vs WRL vs Python canonicalizers on 17 edge values.
- `trvm-scratch/probe_c_cas.mjs` — CAS round-trip, forgeries, projection manifest, `verifiedClaimSemId`, `grammar`.
- `governance/derive_battery.mjs` run at HEAD: `DERIVE-BATTERY: PASS — 45/45`, exit 0. Realm battery and Makefile gates **not run** (they write into the tree).
