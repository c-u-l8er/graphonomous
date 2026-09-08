# R16 — required schema closure: prior art, and what this tree actually looks like

**For:** `GRAPHONOMOUS-PROJECTION-v1` (GPT Adjudication v6 §6 → D-068), Phase C0's research/decision note.
**Rule followed:** classify ADOPT / ADAPT / REJECT; import no framework; measure this tree before designing for it.
**Measured here 2026-09-03**, in `graphonomous/v2`, and re-verified by hand after the research pass.

## 0. Three measurements that decide most of the design

**(a) The JSON Schema reference graph has NO edges.** Every `$ref` in all twelve `schemas/*.schema.json` is a local
pointer (`#/$defs/…`). `schemas/build_schemas.mjs` inlines `common.schema.json`'s `$defs` **into every generated
document**, so the shared vocabulary is duplicated content, not a referenced resource.

```
$ grep -o '"\$ref": *"[^"]*"' schemas/*.schema.json | grep -v '"#'
(no output)
```

**A `$ref`-derived closure therefore returns `{self}` for every schema and discriminates nothing.** Any design that
tries to derive the closure from the schema documents alone fails here. The discriminating edge is not schema→schema;
it is **projection contract → active adapters → record kinds → schemas**.

**(b) Every schema already carries a logical `$id`**, `https://graphonomous.com/g0/schemas/<name>.schema.json`, and
`$schema: …/2020-12/schema`. Nothing has to be authored to get a path-independent logical identity.

**(c) `schema_set_id` over-declares today, and one of the twelve is loaded by no runtime code at all.** Measured:

| loader | schemas compiled |
|---|---|
| `lib/project.mjs:23` | `node relation assertion source_location fault snapshot adapter_run manifest` (8) |
| `lib/rules.mjs:14` | `rules` |
| `lib/evaluation.mjs:28` | `derived_fact evaluation` |
| **nothing at runtime** | **`common.schema.json`** — it is an input to `schemas/build_schemas.mjs`, and its `$defs` are already inside the bytes of all twelve outputs |

`schemaSetId()` (`lib/certificate.mjs:118`) binds all twelve regardless, keyed on **basename**. So each of the four
frozen projections carries a `schema_set_id` over four files its pipeline never loaded — and a rename of a file it did
load would move the id even though the schema resource is unchanged.

## 1. Protobuf `FileDescriptorSet` / protoc / Buf — **ADAPT the digest shape and the named-root discipline; REJECT the format**

`FileDescriptorProto.dependency` lists **direct imports only**; the transitive closure is not a field, it is produced
by the tool. `protoc --descriptor_set_out --include_imports` "also includes all dependencies of the input files in the
set, so that the set is self-contained."

The honest observation: **protoc does not solve workspace contamination — the invocation does.**
`protoc --include_imports foo.proto` is stable against unrelated files because *a root was named*. `protoc *.proto`
reproduces this tree's exact disease.

Buf adds the identity layer. Its `b5` module digest is two-stage: a files digest over a **sorted manifest of
(path, digest)**, then a second hash over that digest followed by the **dependency digests, sorted inside the digest
function**; and "the name of the Module and any of its dependencies has no effect on the Digest." `buf.lock` records
the digest of every direct and transitive dependency and fails loudly on mismatch.

**Adopt exactly three things:** (i) the closure is rooted at an explicitly named target set, never a directory glob —
this is the whole fix; (ii) hash a sorted list of `(identity, digest)` pairs, with the sort performed *inside* the hash
function so traversal order is structurally irrelevant (law 6); (iii) the two-stage
`H(members ‖ sorted contract inputs)` shape, which satisfies law 5 without contaminating the member list.
**Reject** the binary format (a runtime dependency, buying nothing over `canonicalBytesG0`) and BSR commits (a server).

- <https://raw.githubusercontent.com/protocolbuffers/protobuf/main/src/google/protobuf/descriptor.proto>
- <https://buf.build/docs/reference/images/> · <https://github.com/bufbuild/buf/blob/main/private/bufpkg/bufmodule/digest.go>

## 2. JSON Schema `$id` / `$ref` / bundling / catalogs

**`$id` as logical identity — ADOPT.** 2020-12 core: `$id` "identifies a schema resource with its canonical URI", and
implementations "build an internal local index of schema URIs defined in `$id`", making physical location irrelevant
after load. Already present in all twelve files (measurement (b)).

The decisive clause for law 7:

> "A schema MAY (and likely will) have multiple URIs, but there is no way for a URI to identify more than one schema.
> When multiple schemas try to identify as the same URI, validators SHOULD raise an error condition."

**`$ref`-derived closure — REJECT as the primary mechanism, ADOPT as a completeness sweep.** It is *vacuous* here
today (measurement (a)), but it must still be implemented so that the day a real cross-document `$ref` is written it is
pulled into the closure rather than silently omitted. That is protoc's `--include_imports` model.

**Bundling / Compound Schema Documents — REJECT.** Bundling produces a *rewritten* document; hashing it makes identity
depend on a bundler's serialisation choices — a new determinism surface for no gain. Note the generator already
performs an inlining that resembles bundling but is not: it copies `common.$defs` into each file **without** preserving
`common`'s `$id` as an embedded resource, so the shared vocabulary is anonymous duplication.

**Catalogs — REJECT.** Discovery/tooling conveniences; no digest, no closure semantics.

- <https://json-schema.org/draft/2020-12/draft-bhutton-json-schema-01> · <https://json-schema.org/blog/posts/bundling-json-schema-compound-documents>

## 3. Content-addressed manifests — OCI and Nix

**OCI — ADAPT the descriptor, REJECT the manifest.** A descriptor is `mediaType` + `digest` + `size`; the manifest
names its layers and nothing else, so a registry's other blobs are invisible to it. Adopt `(name, digest)` as the pair
that constitutes a versioned reference — the smallest answer to "logical identity distinct from path", and one that
in-toto's ResourceDescriptor arrives at independently. Do **not** adopt ordered members: OCI layers are ordered because
a filesystem overlay has stack semantics; a schema closure has none, so order must be *canonicalised away*, not
preserved.

**Nix — ADOPT the principle, REJECT the machinery.** A derivation collects `inputSrcs`/`inputDrvs` explicitly and is
itself content-addressed through a canonical serialisation. The load-bearing property: **unrelated files in a source
tree do not affect the derivation hash — only referenced inputs do.** That is precisely the invariant D-068 asks for,
and Nix achieves it the same way protoc does: by refusing to infer inputs from the tree. Reject store/realisation
machinery; reject fixed-output derivations specifically — they are the escape hatch that lets an impure fetch declare
its own hash, the opposite of what is wanted.

- <https://github.com/opencontainers/image-spec/blob/main/manifest.md> · <https://nix.dev/manual/nix/2.28/store/derivation/>

## 4. Registries and attestations

**Confluent Schema Registry — REJECT**, on three disqualifiers: the schema ID is **assigned by a server**, so a
verifier cannot re-derive it (the one property required); `subject/version` is a mutable indirection; and it is a
network service against a zero-dependency rule. The one idea worth keeping is nominal — a reference is
`(reference name, pinned target)`, i.e. an adapter names a *logical* schema, not a file — and `$id` supplies that free.

**Avro schema resolution — REJECT.** Reader/writer resolution is about tolerating version differences in data. It is
orthogonal, and importing it would undermine the certificate: the point is that a schema change **moves** the id.

**in-toto / SLSA — the most on-point prior art, and ADOPT the layout/link split.** in-toto separates **link** metadata
(what a step *reports* it consumed and produced) from a **layout** signed by the project owner (what a step is
*allowed* to consume), with artifact rules `MATCH / ALLOW / REQUIRE / DISALLOW`; verification applies the layout's
rules to the link's reported artifacts, never the reverse. That is the exact shape of the answer here:

> the artifact says **what it did** (its own `adapter_run` records); a **local, versioned, pinned contract** says what
> that *implies* about required schemas. The artifact selects a point in the contract space; it never supplies the
> space.

**Graphonomous already implements half of this**: `adapterContractId(runs)` (`lib/certificate.mjs:122`) reads the
projection's own `adapter_run` records, refuses any adapter URI not under `adapters/`, then hashes **the files from the
local tree**. The new closure should be built the same way. Reject DSSE/Sigstore signing — there is no second party, so
a signature would only be the codebase agreeing with itself.

- <https://github.com/in-toto/attestation/blob/main/spec/v1/statement.md> · <https://github.com/in-toto/docs/blob/v0.9/in-toto-spec.md>

## 5. The anti-pattern: preventing UNDER-declaration — where the prior art is weakest

**SLSA is not sufficient, and it says so.** `resolvedDependencies` is "an unordered collection of artifacts needed at
build time", and the spec states outright: **"Completeness is best effort, at least through SLSA Build L3."** SLSA's
real mechanism is a trust substitution — the *builder* is trusted, the build is not. It relocates the question to
"do you trust this builder." For a certificate whose entire claim is reconstruction identity, best-effort completeness
is not an acceptable guarantee. **ADAPT the framing only** ("the harness is trusted, the run is not");
**REJECT `resolvedDependencies` as a model.**

**Hermetic builds are the only mechanism that actually closes it — ADOPT, reduced to one function.** Bazel's execroot
"contains only declared inputs", so an undeclared input is a *build failure*, not an audit finding. No sandbox is
needed here. What is needed is that the projector be unable to **name** a schema outside its declared closure: replace
the module-level `Object.fromEntries([...names...])` at `lib/project.mjs:23` with an accessor that takes a logical
`$id`, checks membership in the resolved closure, and throws otherwise. Under-declaration then becomes a `throw`.

**The honest limit, to be written into the scope record rather than papered over:** this works because producer and
verifier share a tree and the verifier re-runs the projection. A verifier that only *reads* a bundle cannot observe
what the producer actually loaded; it can only recompute the closure the contract implies and check the certificate
matches.

- <https://slsa.dev/spec/v1.0/provenance> · <https://bazel.build/basics/hermeticity>

## 6. Direct answers to C0's four questions

**Q1 — smallest logical, versioned identity distinct from filename.** `$id` for the logical name, the content digest
for the version: the pair `("https://graphonomous.com/g0/schemas/node.schema.json", "sha256:…")`. Author nothing.
**Do not put a version string in the URI** — it is a second source of truth that can disagree with the bytes and that a
human must remember to bump; a digest cannot be forgotten. One consequence to accept deliberately: keying on `$id`
rather than basename makes the closure **path-independent**, so moving a schema file no longer moves the id. That is
correct, and it is a behaviour change from today that belongs in the change record.

**Q2 — is `$id` + `$ref` traversal enough, or is a declared `requires` list needed? BOTH; neither alone.**

| approach | failure mode |
|---|---|
| `$ref` traversal alone | **Vacuous here** — yields `{self}` for all twelve. It also cannot express the real edge: "this adapter emits `relation` records" is not a `$ref`. |
| declared `requires` alone | **Drifts silently** the moment someone adds a `$ref` and forgets the list; and it is *weakenable by editing* unless the list is inside a pinned code identity. |
| **declared roots + transitive `$ref` sweep** | roots come from the contract (expressive enough for the real edge); the sweep guarantees no reachable resource is dropped when refs eventually appear. |

Enforcement comes from neither — it comes from the hermetic accessor of §5.

**A residual imprecision that cannot be fixed at v1 and must be recorded.** Because `build_schemas.mjs` inlines
`common.$defs` into all twelve documents, the closure is only as fine-grained as the *files*. Adding one field to a
shared `$def` and rebuilding changes the bytes of all twelve, so every projection whose closure touches any schema
re-mints — even one that never uses the changed def. Law 2 (unrelated new *file*) holds; the analogous "unrelated
*def* changed" case does not, and cannot without abandoning the inlining for genuine cross-file `$ref`s. That is a
defensible v2 move. **Do not attempt it in v1.**

**Corollary — `common.schema.json` is excluded from the closure.** Nothing loads it at runtime and its content is
already fully present in the bytes of every generated schema; including it double-counts and makes the certificate
depend on a build tool.

**Q3 — hashing so reorder HOLDS and duplicates REFUSE.** Three rules, in order:

1. **Refuse duplicate logical identity at INDEX time, not hash time.** Build `Map<$id, {path, digest}>`; a second file
   claiming an existing `$id` refuses **even if the bytes are identical** — two files that agree today can diverge
   tomorrow, and at that moment the closure becomes order-dependent. A `.schema.json` with no `$id` also refuses: it is
   unaddressable.
2. **Never accumulate the closure in a `Set` keyed on digest** — that would silently dedupe exactly the case law 7
   wants refused. Accumulate in a `Map` keyed on `$id`; a re-insert with a differing digest refuses.
3. **Sort inside the hash function**, by `$id`, then `canonicalBytesG0` + `H`. Assert strictly increasing `$id`
   immediately before hashing, so a duplicate reaching the hasher crashes rather than quietly collapsing.

Hash **the member pairs only** — not file paths, not concatenated bytes.

**A required sharpening of law 5, made explicit rather than fudged.** D-068 law 5 asks that activating an adapter move
"adapter contract + schema closure + certificate". If the newly activated adapter emits only record kinds already in
the closure, **the schema closure genuinely does not move, and should not** — no schema dependency changed. Restate:

> activating an adapter MUST move `projection_contract_id`, and therefore the certificate; it moves
> `schema_closure_id` **iff** it introduces a schema not already required.

Any design that forces the schema closure to move here would have to smuggle the adapter list into the schema member
set, which makes `schema_closure_id` stop meaning "the schemas required".

**Q4 — making "verifier-derived, not artifact-supplied" concrete when producer and verifier share a codebase.** There
is no cryptographic boundary and claiming one would be an overclaim. There is a **code-path boundary**, enforceable if
four things hold:

1. **The closure function's inputs are typed.** It may read only (a) files in the local checkout and (b) a *selector* —
   the adapter URIs the projection's own `adapter_run` records name. It must be structurally unable to read the bundle:
   don't give it the parameter.
2. **The selector is artifact-supplied, and that is correct** — link/link, layout/local. This is in-toto's split, and
   `adapterContractId` already does it.
3. **A bundle-supplied closure is compared, never consumed.** The bundle may carry one for diagnostics; the checker
   recomputes, compares, refuses on mismatch — the pattern already at `lib/certificate.mjs:312`. This is the concrete
   content of law 8: *not "the artifact may not speak", but "the artifact's words are compared against, never
   substituted for, the derivation."*
4. **The contract and the deriving code must be inside a pinned code identity, or the whole thing is circular.**
   Measured: `PROJECTOR_MODULES` (`lib/certificate.mjs:69`) hashes seven files and `CHECKER_IMPORTS` hashes only
   `lib/canon.mjs` — **neither contains `lib/certificate.mjs` itself, and neither would contain a new contract file.**
   Without adding them, someone could edit the contract to shrink a closure and nothing in the certificate would move,
   which defeats the entire mechanism.

The honest statement of what is achieved: *the closure is derived from versioned local artifacts that are themselves
inside the certificate's code-identity chain, and the bundle can only select among them, never widen or narrow the
space.* Someone with write access to the tree can still change everything — but not **without moving a code id**. That
is the same strength `adapter_contract_id` already claims.

## 7. Recommended design (zero dependencies, no new hashing primitive)

**A. one new versioned contract file** — data, not code, and pinned. Its `record_kinds` mirrors `RECORD_KINDS`
(`lib/certificate.mjs:71`) and the `per_kind` lists in the frozen manifests; `adapters` states what each adapter
*emits*; `conditional` covers `rules` and the evaluation pair. **There is deliberately no `active` flag** — activeness
is not a property of the tree, it is the selector the artifact supplies, which is what makes law 4 hold without a flag
anyone could flip.

**B. `schemaIndex()`** — `Map<$id, {path, digest}>` over `schemas/*.schema.json`; refuse a missing `$id`, refuse a
duplicate `$id` even byte-identical. **Law 7 lands here, not in the hasher.**

**C. `requiredSchemaClosure(index, contract, selector)`** — roots from the selector's adapters → emitted kinds →
schemas, plus `structural`, plus the conditional sets; then a transitive external-`$ref` sweep; then sort by `$id` and
assert strict increase. Returns `[[$id, digest], …]`. **Law 6 lands here.**

```
schema_closure_id      = "gschema-" + H(canon( members ))
projection_contract_id = "gpcon-"   + H(canon([ contract_version, sorted(activeAdapters), schema_closure_id ]))
```

**D. the hermetic accessor** — replace `lib/project.mjs:23` with a gate that resolves a validator by logical `$id` and
refuses any `$id` outside `members`. Record the *used* set and refuse if `used ⊄ members`.

**E. certificate binding** — `claim.schema_closure_id` (+ `claim.projection_contract_id`), recomputed and compared by
the checker, extending the existing `gproj-schema-set-mismatch` path.

**F. pin the new surfaces** — add the contract file and the closure module to the projector/checker code identity, or
the mechanism is decorative (Q4.4). And note `lib/schema.mjs:10` keeps a `KNOWN` keyword allowlist that **throws** on
any unrecognised keyword; a new per-schema declaration keyword would have to be added there. The design above needs
none, because the contract file carries the declarations — a point in its favour.

### The eleven laws against this design

| law | holds because |
|---|---|
| 1 same projection + closure → same certificate | `members` is a pure function of (contract, selector, schema bytes) |
| 2 unrelated new schema → **HOLDS** | it enters the index but is neither a root nor `$ref`-reachable, so never a member |
| 3 required schema changes → **MOVES** | its digest is a member |
| 4 new **inactive** adapter + schemas → **HOLDS** | roots derive from adapters actually run; an unrun adapter contributes no kinds |
| 5 activate it → **MOVES** | `projection_contract_id` moves unconditionally; `schema_closure_id` iff a new schema appears *(§6 Q3 sharpening)* |
| 6 reorder traversal → **HOLDS** | sort by `$id` inside the closure function |
| 7 duplicate/ambiguous `$id` → **REFUSED** | index-time refusal even on identical bytes; `Map`-not-`Set`; terminal strict-order assert |
| 8 artifact list cannot weaken | the closure function never receives the bundle; a supplied list is compared, never consumed |
| 9 v0 goldens reproduce | v0's `schemaSetId()` is untouched and keyed on protocol id |
| 10 v0 and v1 coexist | different protocol ids ⇒ different `verifiedClaimSemId` preimages |
| 11 all four projections certify under v1 | to be measured, not assumed |

### What this design does NOT solve — for the scope record

- **def-granularity precision** (§6 Q2 residual);
- **read-only verification of the *used* set** — a verifier that does not re-run the projection cannot observe what the
  producer loaded;
- **no cryptographic trust boundary** — producer and verifier are one codebase; the guarantee is "the closure cannot
  change without moving a pinned code id", which is exactly what `IMPLEMENTED_SCOPE` (`lib/certificate.mjs:61`) exists
  to state in refusable values.
