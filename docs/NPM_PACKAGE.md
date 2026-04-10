# graphonomous — NPM Package Specification

**Package**: `graphonomous`
**Version**: `0.4.0` (current) → `0.4.1` (four-package alignment bump)
**Language**: TypeScript (MCP wrapper) + Elixir (engine, vendored escript)
**License**: Apache-2.0
**Registry**: https://www.npmjs.com/package/graphonomous
**Repository**: `AmpersandBoxDesign/graphonomous` (monorepo subdir)

## Purpose

`graphonomous` is the MCP server for the continual learning engine. It
exposes the 5 Graphonomous loop-phase machines (`retrieve`, `route`, `act`,
`learn`, `consolidate`) over stdio and persists knowledge in an embedded
SQLite + sqlite-vec database.

This package already ships at v0.4.0 and serves as the **template** for
the other three packages in the four-package MCP stack. A v0.4.1 bump is
required to:

1. Update the package description to name the 5-machine surface (no more
   "28 tools" wording — the v1 tool surface is now legacy).
2. Update the README to reference the four-package install story.
3. Publish a `graphonomous.continual_learning.pulse.json` manifest so
   `os-prism` can benchmark against a canonical PULSE manifest.
4. Register itself with a running `os-pulse` instance at startup if one
   is configured (optional).

No Elixir code changes are required. The existing vendored escript at
`graphonomous/npm/vendor/` and the existing postinstall script continue
to work.

## Install

```bash
npx -y graphonomous --db ~/.graphonomous/knowledge.db
```

Or in `.mcp.json`:

```jsonc
{
  "mcpServers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db"]
    }
  }
}
```

## MCP Surface — 5 Loop-Phase Machines

| Machine       | Phase           | Actions |
|---------------|-----------------|---------|
| `retrieve`    | "What do I know?" | `context`, `episodic`, `procedural`, `coverage`, `trace_evidence`, `frontier` |
| `route`       | "What should I do?" | `topology`, `deliberate`, `attention_survey`, `attention_cycle`, `review_goal` |
| `act`         | "Do it"         | `store_node`, `store_edge`, `delete_node`, `manage_edge`, `manage_goal`, `belief_revise`, `forget_node`, `forget_policy`, `gdpr_erase` |
| `learn`       | "Did it work?"  | `from_outcome`, `from_feedback`, `detect_novelty`, `from_interaction`, `contradictions` |
| `consolidate` | "Clean up"      | `run`, `stats`, `query`, `traverse` |

The v1 tool surface (29 individual tools) remains available for backward
compatibility but is deprecated. New integrations should use the 5 machines.

## v0.4.1 Checklist

- [ ] Bump `mix.exs` version to `0.4.1`
- [ ] Bump `npm/package.json` version to `0.4.1`
- [ ] Update `npm/package.json` description to the 5-machine framing (**done**)
- [ ] Update `npm/README.md` to reference four-package install block
- [ ] Add `graphonomous.continual_learning.pulse.json` alongside the existing
      `PULSE/manifests/graphonomous.continual_learning.json` so the manifest
      is shipped as part of the npm package's `files` array
- [ ] Add optional `--pulse-registry <url>` CLI flag to auto-register the
      manifest with a running `os-pulse` instance at startup
- [ ] Rebuild platform escripts and upload to GitHub Releases under tag
      `graphonomous-v0.4.1`
- [ ] `npm publish --access public`

## Why graphonomous ships last

1. Already shipping and stable at v0.4.0 — no urgency for the actual code.
2. Depends on `os-pulse` being live so the auto-registration feature can be
   dogfooded.
3. Depends on `os-prism` being live so Phase 5 (dogfood benchmark) can
   actually run against graphonomous end-to-end.
4. Doc and version bump only — lowest-risk release in the sequence.

## Reference

- `graphonomous/docs/spec/README.md` — full engine spec (v0.4)
- `graphonomous/docs/skills/SKILLS.md` — ampersand-plugins skills pack
- `PULSE/manifests/graphonomous.continual_learning.json` — canonical PULSE manifest
