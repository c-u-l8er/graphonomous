# R3 — Store & Query for Graphonomous G0

Research date 2026-09-02; every URL was accessed that day. Versions and activity come from the
npm/PyPI/GitHub APIs, not READMEs. "Reference pattern" = copy the idea; "adopt" = take the
dependency. Claims that are my inference rather than sourced fact are marked *(inference)*.

## Executive summary

1. **Build, don't adopt.** A ~300-line stratified, semi-naive evaluator in dependency-free ESM
   (mirrored in Python) that records a derivation per derived fact is the right tool for
   200–2,000 nodes / ≤10k edges. Every candidate engine fails at least one hard requirement:
   no provenance (CozoDB, Datascript, Datalevin, Datahike, Logica, pyDatalog), no shipped
   Node/Python/browser artifact (Soufflé, Nemo), or dormant/archived (CozoDB, DDlog).
2. **Reference patterns to copy:** Soufflé's per-tuple (rule, minimal-height) annotation with lazy
   proof-tree reconstruction; Nemo's `--trace` proof trees in ASCII/JSON; the JTMS justification
   (conclusion, in-list, out-list) as the shape of an explanation.
3. **Fact log:** Datomic's `[e a v tx op]` is the smallest history-keeping model, but G0's log is
   git. As-of = rebuild at a commit; domain supersession = `SUPERSEDES` edges plus a `current`
   rule. Bitemporal storage is not needed yet.
4. **Digest:** stable ids put G0 in RDFC-1.0's trivial case. Use JCS (RFC 8785) records,
   byte-wise sorting, git-style typed headers, and a two-level Merkle root.
5. **Determinism rules, all reproduced locally today:** no floats in identity fields; no default
   `sort()`/`localeCompare`; no ids from Map/array order; never iterate a Python `set`; sort by
   UTF-8 bytes (JS UTF-16 and Python code-point order disagree on astral characters); never hash
   a `.sqlite` file.
6. **Query surface:** five typed functions over materialized rule results, one ESM module shared by
   CLI and browser. Not Cypher/GQL, not SPARQL (1.2 Query is still a Working Draft), not GraphQL
   (fixed-depth selections cannot express closure). SQLite recursive CTEs are a fine throwaway
   index, not the API.
7. **Explanation object:** `{id, rule, conclusion, premises[], bindings, depth}` where a premise is a
   fact key or `{absent: pattern}`; content-addressed; verified by a checker that shares no code
   with the evaluator.
8. **SQLite is an index, not the store.** The store of record is a directory of canonical JSON plus a
   manifest; `node:sqlite` (RC), Python `sqlite3`, `exqlite` build the index; the browser loads the
   JSON. FTS5/`sqlite-vec` are not needed yet.
9. **Incremental (DDlog, Feldera/DBSP) is explicitly out of scope** until a rebuild stops being seconds.
10. **Own the tie-break.** No engine documents which proof it keeps among equal-height alternatives
    *(inference)*; the digest requirement means G0 must define this itself.

## 1. Datalog engines: adopt or write a small one?

| Engine | Verified status (2026-09-02) | Provenance | Node / Python / browser |
|---|---|---|---|
| **Soufflé** (C++, UPL-1.0) | Release 2.5, 2025-03-24; repo pushed 2026-07-13 [S1] | `-t explain`/`-t explore`: minimal-height proof trees rebuilt lazily from a per-tuple (rule, height) annotation; `explainnegation` needs user guidance [S2]; 1.27× average overhead [S3] | Python = SWIG binding built from source, one compiled wrapper per `.dl` [S4]; Emscripten build was a 2.4 contribution [S1]; npm `souffle` is an unrelated 2019 package |
| **Nemo** (Rust, Apache-2.0/MIT) | v0.10.1, 2026-08-01; pushed 2026-08-28; 286 stars; "should still be considered unstable" [N1] | `nmo rules.rls --trace "p(1,3);q(3)"` prints proof trees; `--trace-all-idb-facts`, `--trace-output`, JSON `--trace-tree`/`--trace-node` in the CLI source [N2][N3]; traces reconstructed backwards, "adds no cost to reasoning", JSON output [N4] | `nemo-python` (maturin, experimental, not on PyPI) and `nemo-wasm` (wasm-pack, experimental, not on npm) [N5]; the Python API doc page is empty |
| **CozoDB** (Rust, MPL-2.0) | Last release v0.7.6 2023-12-11; last commit 2024-12-04; community fork silent since 2024-12 [C1][C2] | None | `cozo-node`, `cozo-lib-wasm`, `pycozo`, all pinned at 0.7.6 |
| **Datascript** (EPL-1.0) | npm 1.8.1, 2026-08-15 [D1] | None (query engine) | JS/browser yes; no history by default |
| **Datalevin** (EPL-2.0) | 1.0.2, 2026-08-11; PyPI `datalevin`, npm `datalevin-node` (native LMDB) [D2] | None | No browser; "when data are deleted, they are gone" |
| **Datahike** (EPL-1.0) | npm 0.8.1865, 2026-09-01; JS/Python APIs beta [D3] | None | Datomic-compatible history, IndexedDB backend |
| **Logica** (Apache-2.0) | PyPI 1.3.14…, 2025-09-26; pushed 2026-08-23 [L1] | None | Compiles to SQL (DuckDB/SQLite/Postgres/BigQuery); recursion = fixed-depth unrolling or a Python-driven iterate-to-fixpoint pipeline [L2] |
| **pyDatalog** (LGPL) | 0.22.4, 2026-06-13; maintainer "restarted support … in June 2026" [P1] | None | Python only |
| **datalog-ts** (MIT) | npm 0.6.6 2024-01; pushed 2024-12-31; tree has `traceTree.ts`, `trace.tsx` [J1] | Trace UI (research) | TS |
| **percival** (MIT) | pushed 2023-02-16; Rust→WASM compiler emitting JS run in workers [J2] | None | Browser notebook |
| **datalogJS** (InstantDB) | 100 lines: triples, pattern matching, indexes; no rules/recursion/negation [J3] | None | Pattern for the query half only |
| **DDlog** (MIT) | Archived 2026-07-13, last push 2023-07-07 [F1] | None | Its authors founded Feldera [F2] |
| **Feldera/DBSP** (MIT) | v0.342.0 2026-09-02; SQL not Datalog; a service (Docker, pipeline manager, Python SDK), not an embeddable library [F3] | None | Incremental — not a G0 need |

**Recommendation: build.** (i) The stated rules need one negative stratum and semi-naive
iteration — ~300 lines that a 50-line independent checker can confirm. (ii) "Every derived fact
carries its rule and premises" is native to a hand-built loop and bolted on everywhere else.
(iii) The identical-digest requirement needs control over iteration and tie-break order, which no
engine documents. (iv) Only a dependency-free module runs unchanged as CLI, library and static
page. Revisit Nemo if the rule set grows past a few dozen rules or ~10⁶ facts.

## 2. Fact-log designs and the smallest history-keeping model

**Datomic:** a datom is `[e a v tx op]`; retraction appends `op=false`; nothing is overwritten.
`as-of(t)` ignores transactions after `t`; `since(t)` shows only later additions; `history` includes
retractions and exposes `op` [DM1][DM2]. The log is "all transaction data in historic order" as
`{:t, :data}` entries; indexes are the consolidated current state [DM3]. Current view = fold of
the log; as-of = fold of a prefix.

**XTDB v2** (GA 2025-06-12, MPL-2.0): four columns `_valid_from/_valid_to/_system_from/_system_to`
(closed-open); SQL:2011 `FOR VALID_TIME AS OF …`, `FOR SYSTEM_TIME AS OF …`, `… ALL`,
`SETTING DEFAULT VALID_TIME AS OF …`; defaults are valid-time "as of now" and system-time
"as best known" [X1][X2]. **CozoDB** puts validity in the trailing key column as
`(timestamp, asserted?)` and queries with `@ 'NOW'` / `@ ts` [C3]. **EAV on SQLite:** Mentat
(Rust, Apache-2.0) did this and was archived 2018-09-12 [M1]; Datascript has the same
EAVT/AEVT/AVET index set without history; Datahike adds history over it [D1][D3].

**Smallest model:** one append-only relation `facts(e, a, v, tx, op)`. Current = assertions with
no later retraction of the same `(e,a,v)`; as-of(T) = the same restricted to `tx ≤ T`:

```sql
SELECT e,a,v FROM facts f WHERE f.op=1 AND f.tx<=:T AND NOT EXISTS (
  SELECT 1 FROM facts g WHERE g.e=f.e AND g.a=f.a AND g.v=f.v AND g.op=0 AND g.tx>f.tx AND g.tx<=:T);
```

**G0 has two histories; do not merge them.** *Storage history* ("when did the graph learn
this?") is git: as-of means check out a commit and rebuild; the manifest records the input commit
— no `tx` column. *Domain supersession* ("S5-v2 supersedes S5-v1") is data:
`SUPERSEDES` edges from the registries, and the clean current view is a rule,
`current(X) :- claim(X), not superseded(X)`, with `superseded` closed transitively. Superseded
nodes stay in the projection, flagged, so "why is X not current" has a derivation like any other
fact. Bitemporal machinery: not needed yet *(inference)*.

## 3. Deterministic canonical identity

**Precedents.** Git hashes `type size\0content`; tree entries are sorted, so a tree hash depends
only on entry names, modes and child hashes — never traversal order or timestamps [G1]. RDFC-1.0
(W3C Recommendation 2024-05-21) is hard only because of blank nodes (n-degree hashing, datasets
"constructed to prevent this algorithm from terminating"); without blank nodes the canonical form
is sorted N-Quads [R1]. G0 has stable ids: the trivial case.
JCS (RFC 8785): sort keys by UTF-16 code units, ECMAScript number formatting, no NaN/Infinity,
no whitespace [R2].

**Hazards, reproduced locally today (Node v25.2.1, Python 3.13.14):**

- JS object keys serialize integer-like keys first, ascending, then insertion order:
  `{b,a,"10","2","-1","1.5"}` → `{"2","10","b","a","-1","1.5"}` [JS1]. Map/Set iterate in
  insertion order — deterministic only if the insertion order is [JS2].
- `JSON.stringify`: `undefined`/functions vanish in objects but become `null` in arrays;
  `NaN`/`Infinity` → `null`; `-0` → `"0"`; BigInt throws; Map/Set → `{}` [JS1].
- Default `sort()` compares as strings by UTF-16 code unit: `[1,30,4,21,100000].sort()` →
  `[1,100000,21,30,4]` [JS3]; `localeCompare` gave `[a,B,c]` where code-unit order gives `[B,a,c]`.
- String order: JS `<` is UTF-16 code-unit order [JS4], Python is code-point order [PY1];
  `"😀" < "｡"` is `true` in JS and `False` in Python.
- Numbers differ between languages even though both are shortest-round-trip (Python since 3.1
  [PY2]): `100` vs `100.0`, `1e-7` vs `1e-07`, `-0`→`0` vs `-0.0`, `123456789012345680000` vs
  `1.2345678901234568e+20`.
- Python: dict order is a language guarantee since 3.7 [PY3]; `set` order changes per process
  under hash randomization — three runs gave three orders [PY4]; `json.dumps` defaults to
  separators `(', ', ': ')`, `ensure_ascii=True` (`é`→`é`) and `allow_nan=True`, which emits
  non-JSON `NaN` [PY5].
- Erlang/Elixir: map iteration order is undefined; use OTP 26 `maps:iterator/2` (`ordered`) or
  OTP 27 `json:encode_key_value_list/2` for explicit key order [E1][E2].

**Rules for G0:**

1. A canonical record is the JCS bytes of an object holding only strings, safe integers,
   booleans, null, arrays and nested objects. Identity fields never hold floats; scores travel as
   decimal strings.
2. Sort records by their canonical UTF-8 bytes (`Buffer.compare` / Python `bytes`), which is
   identical across languages and sidesteps the UTF-16/code-point split; additionally restrict
   ids to `[A-Za-z0-9._:/-]`.
3. Per-kind digest `sha256("g0-<kind> <count>\0" + lines.join("\n"))`; root = digest of the sorted
   `(kind, digest)` pairs. Per-record hashes make diffs cheap.
4. Nothing run-dependent inside the digested bytes: no timestamps, hostnames, tool versions,
   adapter order, run ids. They live in the manifest outside the digest scope.
5. Never mint an id from an array index, Map order or counter; ids come from the registry or from
   content hashes.
6. Reject NaN/±Infinity/undefined before serializing; never hash the `.sqlite` file (§6).
7. CI rebuilds with shuffled file order and reversed adapter order and asserts an identical root.

Libraries: npm `canonicalize` 4.0.0 [LIB1], PyPI `rfc8785` 0.1.4 [LIB2], hex `jcs` 0.2.0 [LIB3];
with the restricted value set, 30 lines of your own is equally defensible.

## 4. Query surfaces

| Surface | Fit for explanation queries | Verdict |
|---|---|---|
| (a) Typed traversal API — `node(id)`, `neighbors(id, kind, dir)`, `path(a, b, kinds)`, `explain(factKey)`, `facts(kind)` | Explanations come free: derived facts already carry derivations | **Adopt** as the only public surface |
| (b) Datalog rules | The derivation layer; users see rule ids and results, not a parser | Adopt internally |
| (c) Cypher/GQL — ISO/IEC 39075:2024 (April 2024); openCypher now "evolves towards" GQL [Q1][Q2] | No embeddable JS/Python implementation with provenance; a parser costs more than the evaluator | No |
| (d) SPARQL — 1.2 Query is a Working Draft dated 2026-08-27 [Q3] | Property paths give reachability, not proofs; needs a triple store | No |
| (e) GraphQL — September 2025 edition [Q4] | Fixed-depth selection sets; closure needs a resolver that is (a) in disguise | No |
| (f) SQL over SQLite — recursive CTEs, `UNION` dedups and terminates on cycles, `ORDER BY` in the recursive part selects BFS/DFS [SQ1] | Good for audits and as an index; derivation trees must be smuggled as path strings | Throwaway index (§6) |

The four example questions map directly: *"why is S6 not a primitive?"* →
`explain("not_primitive/S6")`, a `REDUCES_TO` chain; *"which TESTED claims have no executed
receipt?"* → `facts("unsupported")`, each with its `{absent: …}` premise; *"what supports S5?"* →
`neighbors("S5", "SUPPORTS", "in")` plus `explain` on derived support; *"where did this relation
come from?"* → the base fact's `source {file, jsonPointer, commit}`. One ESM module; the CLI
wraps it with JSON in/out; the static page imports the same file.

## 5. Explanations as first-class objects

Soufflé stores `(rule, minimal height)` per tuple and builds trees on demand; non-existence needs
`explainnegation` [S2]. Nemo reconstructs a trace by re-applying rules backwards from the fact, at
no cost to forward reasoning, and emits JSON [N3][N4]. **Provenance semirings** (Green, Karvounarakis, Tannen 2007): facts carry elements of
`(K,+,×)` — `+` for alternative derivations, `×` for joint use; `N[X]` polynomials are universal,
why-provenance and lineage are homomorphic images; Datalog needs ω-continuous semirings because
recursive programs have infinitely many derivation trees [PS1]. Bourgaux et al.
(KR 2022) show absorptive semirings (PosBool, why-provenance) keep this finite and single out
minimal-depth proof trees (Zhao, Subotić, Scholz) as the practical restriction [PS2]. **JTMS**
(Doyle 1979): a node is IN iff it has a valid support-list justification — every in-list node IN,
every out-list node OUT — with well-founded support; retracting a justification propagates [T1].
**ATMS** (de Kleer 1986): each node carries a label of minimal consistent environments
(assumption sets) — a "consistent, sound, complete and minimal label" [T2][T3].

**Mapping to G0.** A derivation *is* a JTMS justification: positive premises are the in-list;
negation-as-failure premises ("no executed receipt") the out-list. Rebuilding from scratch under
stratified negation needs no retraction propagation — but record the out-list explicitly so an
UNSUPPORTED explanation names what was absent at that snapshot. ATMS labels are overkill: G0 has
one context per snapshot *(inference)*.

**Minimal structure:**

```json
{ "id": "sha256(JCS({rule, conclusion, premises}))",
  "rule": "R-unsupported-tested@1",
  "conclusion": "unsupported/claim:S5",
  "premises": ["claim/S5", "status/claim:S5/TESTED", {"absent": "has_exec_receipt/claim:S5"}],
  "bindings": {"C": "claim:S5"},
  "depth": 2 }
```

Base facts carry `source: {file, jsonPointer, commit}` instead of `rule`, depth 0. Keep distinct
derivations up to a small cap per fact (why-provenance as a set of justifications), always
including the minimal-depth one, ordered by canonical bytes so the UI's first tree is
deterministic. **Checker** (~50 lines, no shared code): substitute `bindings`
into the rule, confirm each positive premise is a fact, each `absent` premise has no match in the
lower strata, and the instantiated head equals `conclusion`; walk premises to rebuild the tree.

## 6. SQLite as the physical index

Availability: `node:sqlite` is Stability 1.2 Release Candidate, unflagged since 22.13/23.4, with
`:memory:` and opt-in extensions [DB1]; Python `sqlite3` is stdlib, `serialize()/deserialize()`
since 3.11 [DB2]; Elixir `exqlite` 0.40.0 (2026-08-24, MIT) [DB3].
Browser: official `@sqlite.org/sqlite-wasm` 3.53.0-build1 (2026-04-21) with OPFS/kvvfs [DB4][DB5];
`sql.js` 1.14.2 (MIT, in-memory, export as `Uint8Array`) [DB6]; `wa-sqlite` (MIT, JS-written
VFSes over IndexedDB/OPFS, async builds) [DB7]. FTS5 has been in the amalgamation since 3.9.0 and
supports external-content tables [DB8]; `sqlite-vec` v0.1.9 is pre-v1 [DB9]. Determinism: without
`ORDER BY` "the order in which the rows are returned is undefined" [DB10]; rowids "might change"
unless aliased by `INTEGER PRIMARY KEY` — VACUUM renumbers [DB11]; deleted content lingers on
freelist pages unless `secure_delete` [DB12], so the file bytes are not a digest surface.

**Recommendation.** The projection is a directory: `nodes/`, `edges/`, `derivations/` as canonical
JSON (one file per kind) plus `manifest.json` (input commit, rule-set version, per-kind digests,
root). SQLite is an index built from those files, keyed by logical ids as
`TEXT PRIMARY KEY`, always queried with `ORDER BY`, deleted and rebuilt freely. Pros: joins and
recursive CTEs for audits, one file for a reviewer. Cons: a second representation to keep honest,
and nothing at 10k edges that a sorted array and two Maps cannot answer in microseconds. The browser page loads the
JSON (a few hundred KB) into the same ESM module; no SQLite-in-browser yet. FTS5 and `sqlite-vec`:
not needed until there is a text or embedding query G0 must answer.

## Decision table

| Option | Maturity (2026-09) | Node / Python / browser | Derivation tracking | Determinism story | Recommendation |
|---|---|---|---|---|---|
| Hand-built stratified evaluator (ESM + Python port) | You own it; ~300 lines + 50-line checker | Yes / yes / yes (same file) | Native, per fact | Fully under your control; tested by shuffle-rebuild | **Adopt (build)** |
| Soufflé 2.5 | Mature, active; C++ | SWIG-from-source / same / demo-grade WASM | Best-in-class proof trees | Set semantics; tie-break undocumented | Reference pattern |
| Nemo 0.10.1 | Active, self-declared unstable | wasm-pack / maturin / yes (nemo-web) — no published artifacts | Traces, JSON | Undocumented | Reference pattern; fallback engine |
| CozoDB 0.7.6 | Dormant since 2024-12 | 0.7.6 bindings everywhere | None | n/a | Reject |
| Datascript 1.8.1 | Active | Yes / no / yes | None | n/a | Reject |
| Datalevin 1.0.2 | Active | Native / native / no | None | n/a | Reject |
| Datahike 0.8.x | Active | Beta / beta / IndexedDB | None | n/a | History-model reference |
| Logica 1.3.x | Active | No / yes / no | None | SQL-engine dependent | Reject |
| pyDatalog 0.22.4 | Revived 2026-06 | No / yes / no | None | n/a | Reject |
| datalog-ts / percival / datalogJS | Research or dormant | TS / no / yes | Trace UI (datalog-ts) | n/a | Code-reading references |
| DDlog | Archived 2026-07-13 | — | None | n/a | Reject |
| Feldera/DBSP | Active service | SDK / SDK / no | None | n/a | Not needed (incremental) |
| SQLite recursive CTE | Ubiquitous | node:sqlite RC / stdlib / WASM | Path strings only | Requires ORDER BY discipline | Throwaway index |

## Sketch: minimal evaluator and explanation structure

G0's rules in the evaluator's internal form:

```
has_exec_receipt(C) :- receipt(R, C), executed(R, "true").
unsupported(C)      :- claim(C), status(C, "TESTED"), not has_exec_receipt(C).   // stratum 1
reduces_to(A, B)    :- edge(A, "REDUCES_TO", B).
reduces_to(A, C)    :- reduces_to(A, B), edge(B, "REDUCES_TO", C).
not_primitive(S)    :- reduces_to(S, _).
superseded(X)       :- edge(_, "SUPERSEDES", X).
superseded(X)       :- superseded(Y), edge(X, "SUPERSEDES", Y).                    // closure
current(X)          :- claim(X), not superseded(X).                                 // stratum 1
```

```js
// g0/datalog.mjs — stratified, semi-naive, derivation-recording; zero dependencies.
export function evaluate(rules, baseFacts, { maxAlt = 4 } = {}) {
  const db = new Map();                 // rel -> Map<factKey, {args, derivs: []}>
  for (const f of baseFacts) add(db, f.rel, f.args, { source: f.source, depth: 0 });
  for (const stratum of stratify(rules)) {            // throws on a cycle through negation
    let delta = snapshot(db, stratum.rels);
    while (delta.size) {
      const next = new Map();
      for (const rule of stratum.rules) {             // rules pre-sorted by id
        rule.body.forEach((atom, i) => {              // semi-naive: atom i binds from delta
          if (atom.neg) return;
          for (const b of join(rule, i, db, delta)) {
            if (rule.body.some(a => a.neg && matches(db, a, b))) continue;
            const head = inst(rule.head, b);
            const premises = rule.body.map(a => a.neg ? { absent: key(inst(a, b)) } : key(inst(a, b)));
            const depth = 1 + Math.max(0, ...premises.filter(p => typeof p === "string").map(p => depthOf(db, p)));
            const d = { rule: rule.id, conclusion: key(head), premises, bindings: b, depth };
            d.id = sha256(jcs({ rule: d.rule, conclusion: d.conclusion, premises: d.premises }));
            if (add(db, head.rel, head.args, d, maxAlt)) put(next, head); // new fact -> next delta
          }
        });
      }
      delta = next;
    }
  }
  return finalize(db);   // {facts:[...], derivations:[...]} sorted by canonical bytes
}
```

Determinism rests on four choices: `snapshot`/`join` iterate arrays sorted by canonical key,
never Map order; `add` keeps at most `maxAlt` derivations per fact sorted by `(depth, bytes)`, so
the minimal-depth proof is first and ties break by bytes; negative atoms reference only lower
strata (enforced by `stratify`), so `matches` is stable within a stratum; `finalize` emits sorted
arrays whose JCS lines feed the §3 digests. The Python port is the same shape using `bytes`
comparison and `sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False`.
`explain(factKey)` is a pure function over `derivations`: take the first derivation, recurse into
string premises, render `{absent}` as leaves — Soufflé's lazy reconstruction with Nemo's output
shape, without either dependency.

## Sources (accessed 2026-09-02)

- S1 https://github.com/souffle-lang/souffle/releases · https://souffle-lang.github.io/news
- S2 https://souffle-lang.github.io/provenance
- S3 https://arxiv.org/abs/1907.05045
- S4 https://souffle-lang.github.io/swig
- N1 https://github.com/knowsys/nemo · https://github.com/knowsys/nemo/releases
- N2 https://raw.githubusercontent.com/knowsys/nemo/main/nemo-cli/src/cli.rs
- N3 https://github.com/knowsys/nemo-doc/blob/main/src/content/docs/installation/cli.md
- N4 https://proceedings.kr.org/2024/70/kr2024-0070-ivliev-et-al.pdf · https://imld.de/cnt/uploads/2024-XLoKR-EvonNemo.pdf
- N5 https://github.com/knowsys/nemo/tree/main/nemo-python · https://github.com/knowsys/nemo/tree/main/nemo-wasm
- C1 https://github.com/cozodb/cozo · https://github.com/cozodb/cozo/releases
- C2 https://github.com/cozo-community
- C3 https://docs.cozodb.org/en/latest/timetravel.html
- D1 https://github.com/tonsky/datascript · https://github.com/tonsky/datascript/blob/master/CHANGELOG.md
- D2 https://github.com/juji-io/datalevin · https://raw.githubusercontent.com/juji-io/datalevin/master/CHANGELOG.md
- D3 https://github.com/replikativ/datahike
- L1 https://logica.dev/ · https://github.com/EvgSkv/logica
- L2 https://ceur-ws.org/Vol-3801/short5.pdf
- P1 https://pypi.org/project/pyDatalog/
- J1 https://github.com/vilterp/datalog-ts
- J2 https://github.com/ekzhang/percival
- J3 https://www.instantdb.com/essays/datalogjs · https://github.com/stopachka/datalogJS
- F1 https://github.com/vmware-archive/differential-datalog
- F2 https://www.feldera.com/blog/Announcing-Feldera-the-company
- F3 https://github.com/feldera/feldera
- DM1 https://docs.datomic.com/whatis/data-model.html
- DM2 https://docs.datomic.com/reference/filters.html
- DM3 https://docs.datomic.com/reference/log.html
- X1 https://github.com/xtdb/xtdb · https://github.com/xtdb/xtdb/releases/tag/v2.0.0
- X2 https://docs.xtdb.com/concepts/key-concepts.html · https://docs.xtdb.com/reference/main/sql/queries.html
- M1 https://github.com/mozilla/mentat
- G1 https://git-scm.com/book/en/v2/Git-Internals-Git-Objects
- R1 https://www.w3.org/TR/rdf-canon/
- R2 https://www.rfc-editor.org/rfc/rfc8785
- JS1 https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify
- JS2 https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Map
- JS3 https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/sort
- JS4 https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Less_than
- PY1 https://docs.python.org/3/reference/expressions.html#value-comparisons
- PY2 https://docs.python.org/3/whatsnew/3.1.html
- PY3 https://docs.python.org/3/whatsnew/3.7.html
- PY4 https://docs.python.org/3/using/cmdline.html#envvar-PYTHONHASHSEED
- PY5 https://docs.python.org/3/library/json.html
- E1 https://www.erlang.org/doc/apps/stdlib/maps.html
- E2 https://www.erlang.org/doc/apps/stdlib/json.html
- LIB1 https://www.npmjs.com/package/canonicalize
- LIB2 https://github.com/trailofbits/rfc8785.py · https://pypi.org/project/rfc8785/
- LIB3 https://github.com/pzingg/jcs · https://hex.pm/packages/jcs
- Q1 https://www.iso.org/standard/76120.html
- Q2 https://opencypher.org/
- Q3 https://www.w3.org/TR/sparql12-query/
- Q4 https://github.com/graphql/graphql-spec/releases
- SQ1 https://sqlite.org/lang_with.html
- PS1 https://web.cs.ucdavis.edu/~green/papers/pods07.pdf
- PS2 https://proceedings.kr.org/2022/10/kr2022-0010-bourgaux-et-al.pdf
- T1 Doyle, "A truth maintenance system", AI 12 (1979) 231–272, https://doi.org/10.1016/0004-3702(79)90008-0
- T2 de Kleer, "An assumption-based TMS", AI 28 (1986) 127–162, https://doi.org/10.1016/0004-3702(86)90080-9
- T3 Reiter & de Kleer, AAAI-87, https://cdn.aaai.org/AAAI/1987/AAAI87-033.pdf
- DB1 https://nodejs.org/api/sqlite.html
- DB2 https://docs.python.org/3/library/sqlite3.html
- DB3 https://hex.pm/packages/exqlite
- DB4 https://sqlite.org/wasm/doc/trunk/index.md
- DB5 https://www.npmjs.com/package/@sqlite.org/sqlite-wasm
- DB6 https://github.com/sql-js/sql.js
- DB7 https://github.com/rhashimoto/wa-sqlite
- DB8 https://www.sqlite.org/fts5.html
- DB9 https://github.com/asg017/sqlite-vec
- DB10 https://www.sqlite.org/lang_select.html
- DB11 https://www.sqlite.org/rowidtable.html
- DB12 https://www.sqlite.org/pragma.html#pragma_secure_delete
- Local experiments: Node v25.2.1 and Python 3.13.14, 2026-09-02 (JSON formatting, string order,
  `PYTHONHASHSEED` runs); registry data via registry.npmjs.org, pypi.org/pypi/*/json, api.github.com.
