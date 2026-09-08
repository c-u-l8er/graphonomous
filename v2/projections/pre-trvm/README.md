# pre-trvm — the receipts minted before the TRVM governance adapter was registered

These are the `GRAPHONOMOUS-PROJECTION-v0` **and** `GRAPHONOMOUS-PROJECTION-v1` certificates of the four projections,
exactly as they stood when GPT Adjudication v6 accepted them, preserved before `adapters/trvm.mjs` was added to
`lib/project.mjs`'s `ADAPTERS` table.

**This directory is the demonstration of D-072's law-4b residue, and it is not a fixture.** Registering a fourth
adapter — so that a snapshot *can* name it — required one row in `lib/project.mjs`. `lib/project.mjs` is inside
`codeId(PROJECTOR_MODULES)`, so `chain_ids.projector.code` moved, and with it every `vclaim-` in this tree. Nothing
else moved: not a source byte, not a projection root, not a snapshot commitment, not an aggregate, not a schema
closure, not an adapter contract, and not the TRVM pin.

The v0 certificates here are the ones GPT froze as golden in v6 §0. They remain **exactly reproducible under their
pinned coordinates** (D-060): what changed is the projector, not the projection.

`test/trvm.test.mjs` measures the transition and names the one coordinate that moved.
