# Pre-G0-F certificate receipts (superseded, preserved — D-054 / G0-F)

The `GRAPHONOMOUS-PROJECTION-v0` certificates minted for the two frozen projections on 2026-09-03 BEFORE the second
adapter existed, copied here byte for byte from `projections/{baseline,historical}/certificate/` before G0-F re-minted them.
The PROJECTIONS did not move (roots `root-da4f3d7a…` / `root-c7f9c759…`, snapshot commitments, evidence aggregates and
adapter contract ids are identical between these bundles and the re-minted ones); what moved is CODE IDENTITY, which the
certificate binds by design (lib/certificate.mjs, "WHAT BINDING MEANS"): `lib/project.mjs` gained the adapter table that runs
`adapters/factory.mjs`, and `schemas/fault.schema.json` gained the codes `STATUS_OUTSIDE_VOCABULARY` and
`SETTLED_WITHOUT_WITNESS`. Checked today against the unchanged directories these bundles refuse with exactly
`gproj-certificate-stale`, `gproj-chain-id-mismatch`, `gproj-schema-set-mismatch` — never `gproj-root-mismatch`,
`gproj-snapshot-commitment-mismatch`, `gproj-adapter-contract-mismatch` or `gproj-count-inconsistent`
(test/factory_certificate.test.mjs "pre-G0-F receipts").

| pin | pre-G0-F VCLAIM | re-minted VCLAIM (2026-09-03, G0-F) |
|---|---|---|
| baseline | `vclaim-897ec409c49c189b769310966b0c85a25df9fc933fafa066d227a6c8aa6017c4` | see `projections/baseline/certificate/VCLAIM` |
| historical | `vclaim-a6ba3b33cbc1732e8bfc79e189d7e6a0ced3669caf8d0c6e884ad08632867a7c` | see `projections/historical/certificate/VCLAIM` |

Why the re-mint was unavoidable rather than a choice: a second adapter cannot run without the projector naming it, and
the projector modules are in the certificate's chain (`PROJECTOR_MODULES`); the two new fault codes are in the schema set
(`schema_set_id`). D-054's "old certificates stay independently checkable after a later snapshot" is measured on the
re-minted bundles: the baseline certificate verifies beside `projections/multi` (same test file, first two tests).
