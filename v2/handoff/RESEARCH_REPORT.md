# RESEARCH REPORT — G-PR0 (2026-09-02)

The brief's research agenda file was not delivered (D-004); this report answers the questions the brief lists in §11
and the four the brief's own text raises (WEK's role, the ontology, identity/provenance, the first dataset). Every
answer names the report that carries the evidence; the reports are kept verbatim under `research/` with their probe
scripts (`research/probes/`) and census data (`research/census/`). Nine agents ran: four online-research lanes
(R1–R4), two repo-grounded stack audits (R5 WRL, R6 TRVM), two source censuses (R7A the invariant registries, R7B
the implementation registries), and one probe of the served Graphonomous v0.4 memory (R8). R4 (visualization) landed after the
freeze and is folded in by decision D-015 without changing a frozen contract.

## 1. The brief's §11 questions

| # | Question | Answer | Evidence |
|---|---|---|---|
| 1 | property graph vs RDF-like vs custom internal graph representation | **Custom, taking three concepts**: edges are records with ids, properties and declared identity keys (property-graph edge identity); statement id ≠ assertion id (RDF 1.2's proposition/occurrence split); nanopub-style envelope with forward-pointer supersession. No RDF datasets, no GQL/Cypher, no DBMS. | R1 §1, §3, §4, comparison table; spec §2, §4 |
| 2 | can WRL itself be the canonical semantic serialization of the projection | **Not sealable today; kernel-native now.** WRL's relation kernel hashes G0 relations (`rev-`/`rel-`) unchanged; the V2 world gate and `validateGraph` refuse a non-circuit profile; `ProfileSchemaV1` and §D9 have zero code. The semantic world is a V2-shaped artifact under a G0 profile with a `gsem-` id; a static profile kind is proposed to WRL. | R5 §1–§6; spec §7; D-009; GAP-W1…W10 |
| 3 | how statement-level provenance is represented | one relation, many assertions, each assertion pinned to a source location at a blob OID; provenance on the assertion/event, never in the relation value (WRL D8.3's ruling) | R1 §1–§3; R5 §4; spec §4.3–4.5, §5 |
| 4 | how derived facts carry proof/derivation identity | `{rule_sem_id, premises[], inputs: [root-…], evaluator}` with content-bound rule ids (the `programSemId` discipline); explanation objects `{id, rule, conclusion, premises, bindings, depth}`; TRVM-issued receipts only for numeric rules until a `prim` catalog exists | R6 §1–§2; R3 §5; spec §8.4, §10.3; D-007 |
| 5 | do Datalog-like rules belong in Graphonomous, WRL or TRVM | **TRVM by design intent, the projector by capability**: the frozen derive core has no quantifier, equality or conditional (by ruling); WRL has no rule notation; G0 evaluates rules as data in the `prim` program shape and labels the record `trvm_derivation: false` | R6 §2; R3 §1; D-007, D-011; GAP-T1…T4 |
| 6 | representing unknown/negative knowledge and failed derivations | typed `unknown{reason}` (FHIR pattern); scoped `NOT_FOUND{registry, snapshot, adapter}`; sources' OPEN tokens verbatim; negation stratified over observed facts; "why not" answered by a positive derivation | R1 §7; R3 §5; spec §5.5, §13 |
| 7 | event/history model vs current-state projection | git is the transaction-time log; domain supersession is data (`SUPERSEDES`, `RETRACTS` as positive records); the current view is a rule; no bitemporal store | R1 §6; R3 §2; spec §4.7, §13 |
| 8 | physical persistence engine vs rebuildable indexes | directory of canonical JSON + TRVM CAS; SQLite throwaway index; browser loads JSON | R3 §6; R2 §6; R6 §3; spec §9; D-013 |
| 9 | graph query surface | six typed functions in one ESM module (`node`, `neighbors`, `path`, `facts`, `explain`, `as_of`); no Cypher/SPARQL/GraphQL | R3 §4; spec §10.1 |
| 10 | graph visualization/layout library | Cytoscape.js 3.34.2 (cdnjs ESM) + cytoscape-dagre for sub-graphs + ELK layered for deterministic whole-graph layering from a digest-keyed cache; Graphviz WASM (`@viz-js/viz` 3.30.0) as fallback/export; Sigma 3 past ~5k nodes; fcose is not reproducible (no seed). Measured at 500/1,500 and 2,000/10,000: layout, not rendering, is the constraint (dagre > 240 s at the upper bound; ELK 12.3 s; `dot` 11–14 s) | R4 §1–§6, appendix; D-015; spec §11 |
| 11 | content-addressed evidence object format | RFC 8785 restricted profile implemented by TRVM `canonicalBytes`; `sha256:` hash form; in-toto Statement shape for receipts; ResourceDescriptor + DigestSet for artifacts; RFC 9162 leaf prefix; manifest of sorted `(lid, hash)` | R2 §1, §3, §6, rules 1–18; R6 §4; fixture `canon-divergence-2026-09-02.md`; spec §6; D-006, D-012 |
| 12 | interop/export formats as adapters | PROV-O / PROV-JSON, OpenLineage, DSSE + JSONL bundles, CIDv1 (`json-jcs`), SLSA — all derivable from stored bytes without re-hashing; none native | R1 §2; R2 §2–§5 |
| 13 | minimum role of WEK in G0/G1 | a source of law statements only (4 crosswalk records under `wek-w-laws`); WEK has no code and its frozen inputs are not in the tree | R7B B4; GAP-K1 |

## 2. What the audits found that the brief could not have known

- **WRL's gate is closed and its kernel is open.** Ten classified gaps, nine of them SPEC_GAP or small MISSING_PRIMITIVE;
  one IMPLEMENTATION_BUG (`revision.policy` unvalidated yet hashed). The smallest justified fix is a `PROFILES` data
  table plus a static profile kind — a spec-text change to a frozen family, hence proposed rather than made (R5 §6).
- **TRVM offers three things G0 can use unchanged and one it cannot.** `canonicalBytes`, `cas.mjs`, `verifiedClaimSemId`
  round-trip Graphonomous records today (measured); the derive core cannot express a deciding rule, and the `prim`
  catalog is declared, not built. Thirteen rows in the register, five candidate `prim` entries (R6 §2.2, §6).
- **Three canonicalizers in-house agree only on the intersection domain** (safe ints, ASCII/UTF-8 strings, bool, null);
  outside it they diverge on floats, `1e-7`, `-0`, non-ASCII, astral key order, lone surrogates, NaN (R6 §4, R5 §3.2,
  R2 §1). One real registry file already trips it (`1.0`, fixture). Hence spec §6.2.
- **The registries are four disjoint id spaces with three typed bridges** (`semantic_map` P/C → S;
  `implementation_binding` → cells; three crosswalk records → factory claims). Everything else that reads like a
  relation is free text; the census gives the resolution rates (R7A §6).
- **No registry has MECHANISM records**; mechanisms exist as prose columns, code symbols inside `source_ids`, and
  `pub` items in `cd-core/src/*.rs` (R7A q5, R7B B1).
- **"TESTED with no executed receipt" is undecidable from data for 48 of 56 records** because receipts are bare strings
  (R7A q6) — so A6 has an explicit third bucket rather than a guess.
- **The tree moves under a census.** invariant-r10 advanced two commits (v2.7), super's worktree changed between reads,
  a computedriven battery wrote receipts, and a promotion receipt's bytes changed — while every package file stayed
  byte-identical. Pins are OIDs, receipts carry the OID they resolved under (D-003, D-008, Q-14).
- **The served Graphonomous v0.4 graph is empty** and answers with `retrieval_confidence: 0` without abstaining (R8);
  there is no prior context in that store to build on.

## 3. Reference pattern vs adopt (consolidated)

| Adopt as concept | Reference pattern only | Leave |
|---|---|---|
| proposition/occurrence split (RDF 1.2 reifiers); edge identity + properties (openCypher/GQL); nanopub envelope + forward-pointer supersession + retraction-as-record; PROV names as field names with `plan` = program id; derivation DAG `{rule, premises}` with semirings read on demand; Datomic's retraction datom; JCS restricted profile; in-toto Statement/RD/DigestSet; RFC 9162 leaf prefix; sorted-manifest root; JSON Schema 2020-12 + JSON Pointer + position maps; JTMS justification shape; Soufflé's (rule, height) annotation; stratified negation | RDF 1.2 syntax; PROV-Constraints and full qualification; GQL DDL / PG-Schema (STRICT as a validation mode only); Soufflé/Nemo proof trees; Datomic/XTDB bitemporality; SCITT/COSE receipts/Rekor; RDFC-1.0 (the blank-node case we avoid by design); GSN shapes, SEI confidence-map defeaters ("Unless …"), PROV-O shape conventions, GUAC click-to-fetch (R4 §4) | RDF datasets as storage; OWL reasoning; unstratified negation; DAG-JSON/DAG-CBOR (contradict JCS on `1.0` and key order); a Datalog engine dependency; a second event log; Elixir as a G0 host until OTP 29 |

## 4. Findings that changed the spec (running list)

1. Five of six registries canonicalize identically in Node and Python; the sixth diverges on one `1.0` → §6.2 bans native floats.
2. The frozen TRVM derive core cannot express a deciding rule; only `sub(len(scope …), 1)` binds → D-007, GAP-T1…T4.
3. TRVM's CAS and certificate accept Graphonomous-shaped records unchanged → D-006, §8.2–8.3.
4. WRL's kernel hashes G0 relations but nothing seals a G0 world → D-009, §7, GAP-W1…W7.
5. `derivation_links` mixes ids and prose; four name a retired record → `UNRESOLVED_LINK`, never a guessed edge.
6. Receipts are pinned by relative path into a shared tree; one changed under the census → receipts carry the OID they resolved under (Q-14).
7. Identifiers collide across five sources → lids carry `(source, namespace)` (§3.3).
8. Three ledger states exist; the served page was built from a historical one → the ref is the source, the divergence a G1 diagnostic (Q-15).
9. The served v0.4 memory is empty → no prior context; recorded (R8), not a G0 input.

## 5. Sources

Primary sources with access dates are listed at the end of each `research/R*.md`; the census scripts and their
JSON outputs are under `research/census/`; the stack probes under `research/probes/{trvm,wrl}/` and the two
canonicalization scripts under `research/probes/`.
