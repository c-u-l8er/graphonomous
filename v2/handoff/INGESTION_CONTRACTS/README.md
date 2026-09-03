# INGESTION CONTRACTS

One contract per authoritative source adapter. A contract states: the source and how it is pinned; the records it
yields and their logical ids; the field → node/relation mapping; the roots against which references resolve; the faults it
can emit; and its determinism obligations. Adapters are separate from normalized semantics (brief §12): a contract
maps source fields onto the normalized record model defined in `../G0_G1_SPEC.md`; it never invents a fact.

| Contract | Source | State |
|---|---|---|
| `crosswalk-v2.6.md` | `invariant-r10/package-v2.6/CROSS_REGISTRY_CLAIM_MAP.json` + `evidence_state.json` | DESIGNED (this round) |
| `factory-ledger.md` | `~/.invariant-factory/canonical.git#invariant-canonical:CLAIM_LEDGER.json` + `mosaic/*` | DESIGNED (census pending R7A) |
| `trvm-grid.md` | `TRVM/governance/invariant-grid.json#law_registry` + `LAWS.md` | DESIGNED (census pending R7B) |
| `cells.md` | `opensentience.org/_invariants/data/cells.json` | DESIGNED |
| `computedriven.md` | `computedriven/{docs,receipts,git}` | PROPOSED |
| `adjudications.md` | GPT rulings (`inputs*.md`), Travis rulings, factory receipts — ADVISORY/ruling/factory with section anchors | DESIGNED |
