# Ingestion contract — TRVM law registry (`governance/invariant-grid.json#law_registry` + `LAWS.md`)

**State:** DESIGNED 2026-09-02 (no code). Census detail pending R7B.

## Pin
| | value |
|---|---|
| repository | `TRVM/` (own git repo), branch `merge/governance-plane`, HEAD `fd0df4c` at snapshot |
| files | `governance/invariant-grid.json` (`version: 1.69.0`, `date: 2026-08-18`; `law_registry.entries` = 138), `LAWS.md`, `LAW_RATIFICATION_2026-07-22.md` |
| caution | the grid in the worktree may differ from the committed blob; the adapter records `git hash-object` of the file it read and flags `WORKTREE_DIFFERS` when it is not the HEAD blob |
| authority | AUTHORITATIVE for TRVM laws; `grid_check` resolves every `law:<id>@<rev>` citation against this registry |

## Records yielded
| Source element | Kind | Logical id | Notes |
|---|---|---|---|
| document | `REGISTRY` | `registry:trvm-grid@1.69.0` | `status_vocabulary` (8: PROVED · PROPERTY-TESTED · REGRESSION-LOCKED · MODEL-CHECKED-FRAGMENT · EMPIRICAL · OPEN · NOT_APPLICABLE · FALSIFIED) |
| `law_registry.entries[i]` | `LAW` | `law:trvm:<id>@<revision>` (the grid's own citation form) | `statement`, `evidence` verbatim; `canonical: true/false` is an attribute; `status` is the evidence state in vocabulary `trvm-grid` |
| `supersedes` / `superseded_by` (`<id>@<rev>`) | `SUPERSEDES` | — | registry-internal pointers; a pointer to an absent entry is `DANGLING_SUPERSESSION` |
| `evidence` prose naming witnesses (`C1: 24,576 edge-additions …`) | attribute only | — | not parsed into WITNESS nodes at G0 (`UNSUPPORTED_SOURCE_FORM: prose-evidence`) |
| `LAWS.md` Series I/II laws by number | `LAW` | `law:trvm:binding-<n>` | tier A/B/RESERVED as `authority_tier`; RESERVED laws are nodes with `citable: false` — present so a citation to them can be flagged |
| `derivation_language`, `hash_policy`, `state_identity`, `artifact_roots` | `POLICY`-like attributes on the registry node | — | read for the G0 contract (spec §8); not graph facts |
| crosswalk records with `source_registry: trvm-law-registry` (8) | `MEMBER_OF` join | — | the crosswalk's `source_ids` cite laws by id; the join is by exact `law:<id>@<rev>` string, else `UNRESOLVED_LINK` |

## Faults
`WORKTREE_DIFFERS` · `DANGLING_SUPERSESSION` · `CITATION_TO_RESERVED_LAW` · `UNKNOWN_TOKEN`.
