# R11 — Prior art for static, data-declared profiles participating in a content address

Scope: WRL admits one built-in profile (roles/ports/relation kinds/endpoint constraints/policy
vocabulary) hashed into `sem-<sha256>` world ids and per-relation ids. Need: additional profiles
declared as data, no app-level branching into the compiler, existing profile's bytes/ids unchanged,
and a `policy` string validated against the active profile's declared vocabulary before it is
hashed. Below: prior art read directly, one source per row, with a one-line takeaway.

## 1. Profile/schema as data that participates in a content address

**IPLD Schemas + ADLs**
https://ipld.io/docs/schemas/features/indicating-adls/ ,
https://ipld.io/docs/advanced-data-layouts/intro/
An IPLD Schema declares an Advanced Data Layout (ADL) with the `advanced` keyword (e.g. `type
MyString string representation advanced ROT13`); the ADL gives an abstract node a "synthesized"
view distinct from its serialized "substrate" bytes. The schema/ADL choice is metadata that tells
tooling how to *interpret* stored bytes — it is not itself hashed into the block's CID, which is
computed from the codec-encoded Data Model bytes only. Two parties can therefore disagree about
which schema applies to a given CID and both be "valid" against the raw bytes.
*Takeaway:* keeping the profile purely as an out-of-band interpretation layer (as IPLD does) means
the profile itself is unauthenticated — the opposite of what WRL wants; WRL should instead make the
profile id (or its hash) a first-class input to the content address, not sidecar metadata.

**JSON-LD contexts vs. RDF Dataset Canonicalization (URDNA2015 / RDFC-1.0)**
https://w3c.github.io/rdf-canon/spec/ , https://json-ld.github.io/rdf-dataset-canonicalization/spec/
URDNA2015 (renamed RDFC-1.0 in the W3C spec) canonicalizes an RDF *dataset* — blank nodes get
deterministic labels derived from graph structure plus lexicographic ordering — so that hashing or
signing is stable across serializations. The `@context` that maps JSON keys to IRIs is resolved
*before* canonicalization: expansion to full IRIs happens first, and it is the expanded graph (not
the context document) that gets canonicalized and hashed. The vocabulary (context) therefore
determines what the identity-bearing graph *is*, but the context document's own bytes are not part
of the canonical form being hashed — only its effect (which IRIs the terms expand to) is.
*Takeaway:* a vocabulary can legitimately influence identity through its *effect* on the canonical
form (expansion) without the vocabulary document's bytes being hashed directly — but only if term
resolution is deterministic and pinned (JSON-LD's failure mode when contexts are mutable/remote is
exactly what WRL should avoid: pin the profile by content, not by mutable reference).

**JCS — RFC 8785, JSON Canonicalization Scheme**
https://datatracker.ietf.org/doc/rfc8785/ , https://www.rfc-editor.org/info/rfc8785/
JCS defines a canonical JSON serialization (I-JSON subset, ECMAScript number/string
serialization, lexicographic property-name sorting) so that hashing/signing JSON is reproducible
regardless of producer. It canonicalizes *structure only* — it has no concept of a schema,
vocabulary, or profile; any two JSON documents with the same canonical bytes hash the same, and
JCS gives no mechanism to bind a "which rules applied" tag into that canonical form.
*Takeaway:* WRL's JSON-canonical-bytes step is JCS-shaped; JCS itself proves nothing about whether
the byte-level canonicalization scheme is sufficient to also carry profile identity — that has to
be added deliberately (e.g. a `profile` field inside the canonicalized document), which is exactly
what WRL is trying to design correctly.

**in-toto Attestation Framework / ITE-6 — `predicateType`**
https://github.com/in-toto/attestation/blob/main/spec/v1/statement.md ,
https://github.com/in-toto/ITE/blob/master/ITE/6/README.adoc
The Statement layer requires a `predicateType` URI that "unambiguously identif[ies] the types of
the Predicate," alongside a `subject` array of digests. ITE-6 replaced in-toto's single fixed
schema with an open set of predicate types (build provenance, SBOM, vuln scan, etc.), each
identified by a URI that a verifier looks up to know how to interpret the predicate object. The
`predicateType` is itself covered by the DSSE envelope signature (it sits inside the signed
Statement JSON), so it cannot be swapped by an attacker without invalidating the signature — but
nothing in the base spec makes the verifier check the *URI resolves* to a known/allowed value; that
is left to consuming policy.
*Takeaway:* `predicateType` is the closest existing analogue to WRL's "profile id" — a short,
signed/hashed token that names which vocabulary applies to the rest of the payload; but in-toto
explicitly punts vocabulary-membership checking to the policy layer, which is the gap WRL is being
asked to close (validate `policy` against the profile's vocabulary before hashing, not after).

**OCI artifact `artifactType` / media types**
https://github.com/opencontainers/image-spec/blob/v1.1.0-rc2/artifact.md
An OCI artifact manifest requires `mediaType: application/vnd.oci.artifact.manifest.v1+json` and a
`artifactType` field carrying the *referenced* artifact's media type; the manifest's own bytes
(including these type fields) are what gets content-addressed into the manifest digest. Because
the type strings are inside the hashed manifest JSON, they are protected by content addressing
itself, and clients that don't understand a given `artifactType` are expected to skip/ignore rather
than mis-render.
*Takeaway:* putting the profile-id string directly inside the canonicalized bytes (so it is
naturally covered by the hash, no separate authentication needed) is the simplest pattern and maps
directly onto how OCI protects `artifactType` — WRL already does this for `policy`; the missing
piece is validating the string against a *table*, not just hashing it.

**Nanopublications — assertion / provenance / pubinfo + Trusty URIs**
https://arxiv.org/pdf/1401.5775 (Trusty URIs), https://arxiv.org/pdf/1508.04977 (nanopub-java)
A nanopublication is three named RDF graphs — assertion (the atomic claim), provenance (how the
assertion came about), and pubinfo (metadata about the nanopub itself, e.g. author/timestamp) — all
wrapped so a single "trusty URI" hash covers the whole bundle. The three-graph separation exists so
that content that is authored fact (assertion) is distinguishable from content that is
book-keeping about the fact (pubinfo) even though both are hashed into the same identifier.
*Takeaway:* separating "the identity-bearing content" from "metadata about how the content was
produced/validated" while still hashing both is a workable pattern for WRL: the profile id/version
can live in a pubinfo-like slot that is still inside the hashed bytes, distinct from the
relation/policy content itself, so an auditor can tell which came from where.

## 2. Registries of admitted schemas as versioned, frozen data

**CloudEvents Documented Extensions registry**
https://github.com/cloudevents/spec/blob/main/cloudevents/documented-extensions.md
Extension attributes not part of the core CloudEvents spec go through a lightweight registry: an
attribute is added to the documented-extensions file via normal PR review plus support from at
least two Voting member organizations; entries explicitly "have no official standing and might be
changed or removed at any time." Implementations are *not* required to limit themselves to
documented extensions — the registry is descriptive/advisory, not an enforcement gate.
*Takeaway:* a frozen, versioned file of admitted extensions with an explicit "two-reviewer" bar is
a lightweight, low-ceremony way to admit new vocabulary — but CloudEvents' registry does not
actually gate anything at runtime, which is weaker than what WRL needs (WRL must refuse an
undeclared `policy` value, not just document known ones).

**IANA Media Type Registry**
https://www.rfc-editor.org/rfc/rfc6838.txt , https://www.iana.org/assignments/media-types
Media types register into one of four "trees" (Standards/IETF, vendor, personal, experimental)
with different review bars — Expert Review for vendor/personal, Specification Required /IESG for
the standards tree. The registry is the single authoritative table client software consults to
decide whether a `Content-Type` string names something real; a fielded consumer's contract is:
byte interpretation is governed by table lookup on this exact string.
*Takeaway:* WRL's per-app "profile id" is structurally an IANA-media-type-shaped problem — a short
namespaced string that must resolve, via a table lookup, to exactly one admitted structural
contract; the tiered trust levels (IETF vs vendor vs personal) suggest WRL profiles could similarly
be split into "built-in" vs "declared local" tiers without changing how either is validated.

**JSON Schema 2020-12 `$vocabulary` / dialects**
https://json-schema.org/draft/2020-12/release-notes , https://www.learnjsonschema.com/2020-12/core/vocabulary/
A dialect meta-schema declares its required vocabularies via `$vocabulary`; per spec, "if a
vocabulary is marked as required, JSON Schema implementations that do not recognise the given
vocabulary MUST refuse to process schemas described by such dialect." This is a hard refuse-unknown
rule, not merely descriptive — an implementation that doesn't recognize a required vocabulary URI
is spec-mandated to stop rather than guess.
*Takeaway:* this is the strongest precedent for WRL's "refuse unless declared" requirement — model
the profile table the same way: each profile is identified by a URI/id, and an artifact naming an
unrecognized profile id must be rejected outright rather than falling back to a default.

**OCI `artifactType` as a gate on interpretation**
(same source as §1) https://github.com/opencontainers/image-spec/blob/v1.1.0-rc2/artifact.md
Registries and clients use `config.mediaType` / `artifactType` purely as a lookup key to decide how
to render or reject a pushed artifact; unrecognized types are meant to be stored inertly rather
than acted on, i.e. the registry does not need to understand every type to remain correct, only to
key on the string faithfully.
*Takeaway:* a table-driven dispatch keyed on a profile-id string, where the storage/identity layer
never needs to understand a profile's *meaning* — only its declared vocabulary shape — is
compatible with WRL's "don't let the app branch into the compiler" constraint.

## 3. The failure mode: an identity-bearing field that is hashed but never validated

**JWT `alg` confusion (RS256→HS256, `alg: none`)**
https://portswigger.net/web-security/jwt/algorithm-confusion ,
https://workos.com/blog/jwt-algorithm-confusion-attacks
The JWT header's `alg` field is itself covered by the signature (it's base64 inside the signed
input), yet classic JWT libraries decoded `alg` and used *it* to pick the verification routine
before checking whether that routine was the one the server intended — letting an attacker relabel
a token `HS256` and get the server's own RSA public key treated as an HMAC secret, or relabel it
`none` and drop the signature check entirely. The field being "inside the hash/signature" did not
stop it from being an unchecked control input: the vulnerability was trusting a self-declared,
signed field to select *how to validate that same signature*, i.e. validating with a policy chosen
by the untrusted document rather than by the verifier's own fixed expectation.
*Takeaway:* this is the exact shape of the bug the task describes — WRL's `policy` string is
hashed into relation identity (so it's "signed" in the content-address sense) but that says nothing
about whether it's a *legal* value; the JWT lesson is that the fix is not to move the field outside
the hash, but for the verifier to independently enforce "is this value in my allowed set for this
context" using its own table, never trusting presence-in-hash as a proxy for validity.

**JCS + JOSE/JWS (canonicalization does not imply validation)**
https://datatracker.ietf.org/doc/rfc8785/
JCS is explicitly scoped to canonical *serialization* for reproducible hashing/signing; RFC 8785
makes no claim about semantic validity of the canonicalized document's fields. Canonicalization
solves "does the same logical document always hash the same," not "is this field's value one we
recognize."
*Takeaway:* canonicalization (which WRL already does) and validation (which the task requires
adding) are orthogonal concerns — JCS-style prior art confirms there is no shortcut where
canonicalizing correctly substitutes for checking the `policy` string against a vocabulary.

## 4. Stated copy vs. derived copy — must profile-derived fields be recomputed?

**Sigstore client-spec — verifier recomputes the digest, does not trust the subject's stated digest**
https://github.com/sigstore/architecture-docs/blob/main/client-spec.md
Sigstore's verification guidance states: "Verifier SHOULD accept the raw artifact and compute the
message digest to minimize any risk for confusion attacks" — i.e. the verifier is told not to trust
the digest value written into the in-toto Statement's `subject` field, but to hash the actual bytes
itself and check that value is present among the (still author-supplied) subjects. This is a direct
instance of "never trust a stated identity-bearing field — recompute it and compare."
*Takeaway:* directly on point for WRL's `sem-<sha256>` world id and any per-relation id: an id
carried *inside* an artifact (e.g. if a message or export ever restates its own world id or
relation id) must be recomputed by the consumer from the canonical bytes + profile, never taken on
the artifact's word, exactly as Sigstore requires for subject digests.

**Subresource Integrity (SRI)**
https://w3c.github.io/webappsec/specs/subresourceintegrity/
SRI's whole design is the inverse case: the *expected* hash is stated out-of-band (in the `<script
integrity=...>` attribute controlled by the referencing document) and the fetched resource's actual
hash is computed and compared against it — the fetched content never gets to assert its own hash.
*Takeaway:* reinforces the general rule from a different angle — whichever side is less trusted
(the fetched bytes in SRI's case, the artifact's self-description in WRL's case) must never be the
source of the identity value used to check itself; the checking side always computes independently.

## Design alternatives seen in the wild for admitting new profiles/schemas

1. **Frozen table compiled into code** (JSON Schema `$vocabulary` required-vocab set, IANA
   Standards-tree types). *Trade-off:* strongest guarantee of "no app branches into the compiler"
   and easiest to validate against, but every new profile needs a new release of the
   table-owning code — slow to extend, and is exactly the shape WRL is asked to keep for its one
   built-in profile while adding a second admission path alongside it.
2. **Lightweight advisory registry with light-touch review** (CloudEvents documented extensions).
   *Trade-off:* cheap to add entries to, but the registry doesn't itself enforce anything — good
   for humans to check, useless as a runtime gate unless something else consults it strictly.
3. **Schema/profile referenced by its own hash, not by mutable name** (IPLD Schemas/ADLs pattern,
   generalized). *Trade-off:* pins exactly which profile bytes apply, immune to registry drift, but
   (as IPLD shows) the reference itself sits outside the artifact's own hash unless deliberately
   folded in, so it has to be re-added to the canonicalized bytes to actually gate identity.
4. **Vocabulary/type named by URI, looked up and required to match a known table, refuse if
   unknown** (JSON Schema `$vocabulary`, in-toto `predicateType`, OCI `artifactType`). *Trade-off:*
   flexible (URIs can be minted by third parties) and keeps the identity field inside the hash, but
   pushes the entire correctness burden onto "does the verifier actually enforce the refuse-if-
   unknown rule," which is precisely the JWT `alg`-style gap if skipped.
5. **Tiered trust registration trees** (IANA vendor/personal/standards, CloudEvents' "two Voting
   members" bar). *Trade-off:* lets built-in and third-party-declared profiles coexist with
   different admission ceremony without changing the validation mechanism, which maps well onto
   "one built-in profile, additional static profiles declared as data" — but needs an explicit rule
   for what happens when two tiers define colliding names.
