# Ingestion contract — the periodic table cells (`opensentience.org/_invariants/data/cells.json`)

**State:** DESIGNED 2026-09-02 (no code).

## Pin
| | value |
|---|---|
| repository | `opensentience.org/` HEAD `2c0f523` at snapshot; file `_invariants/data/cells.json` (`version: 0.8`, 46 cells), `axes.json`, `copy.json` |
| authority | AUTHORITATIVE for the cells' authored fields; the served `invariants.html` is a GENERATED artifact and is never read |

## Records yielded
| Source element | Kind | Logical id | Notes |
|---|---|---|---|
| document | `REGISTRY` | `registry:cells@0.8` | status vocabulary observed at contract time (`proved`, `shipped`, …) |
| `cells[i]` | `CELL` | `cell:<num>` (`01`…`46`, with `27a`-style suffixes if present) | `symbol`, `label`, `status`, `kind[]` (primary = first), `kind_source`, `kind_why`, `protocol`, `protocol_group{label,name,meta}`, `authority`, `source`, `proof`, `tier` verbatim |
| `proof` (`/proofs/kappa.html`) | `WITNESS` (`kind: page`) | `witness:cells:<path>` | a page witness ranks below an executable one — the register rule the build already applies |
| `witnesses` (structured field on some cells) | `WITNESS` | `witness:cells:<path>` | runnability is derived by the build, not authored; G0 copies the derived `runnable` flag only from `mosaic/derived/` as a DERIVED attribute |
| register A/B/C/D (`axes.json#registers[].rule`) | **derived**, not observed | — | G0 re-derives the register from the ledger join (`implementation_binding: cell:NN` at a settled status, or `tier` set) as a `derived` attribute with the rule as data; it must agree with the served page's build or a `CONTRADICTION` fault is raised |
| `kind` vocabulary | read from `mosaic/occupancy.json#kind_vocabulary.declared` via the factory adapter | — | never copied |

## Faults
`KIND_OUTSIDE_VOCABULARY` · `DANGLING_PROOF_PAGE` · `CONTRADICTION(register-derivation)`.
