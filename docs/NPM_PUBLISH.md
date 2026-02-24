# Graphonomous npm Publishing + Maintenance Runbook

This runbook gives you a repeatable process to publish Graphonomous as an npm-installable MCP command, while keeping the Elixir implementation as the source of truth.

---

## 1) Goal

Enable users to run Graphonomous with a familiar Node/npm workflow, e.g.:

- `npx graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback`
- `npm i -g graphonomous`
- then `graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback`

Important: npm is used as a distribution/launcher channel.  
The core runtime is still the Elixir CLI (`Graphonomous.CLI`).

---

## 2) Distribution Model (Recommended)

Use an npm wrapper package that installs/runs a prebuilt Graphonomous binary.

### Why this model
- Best user experience for MCP users (especially editor integrations).
- No requirement for end users to have Elixir/Erlang installed.
- Works well with `npx` and global npm installs.

### Packaging strategy
- Build release binaries per target platform/arch.
- Publish assets on GitHub Releases.
- npm package `postinstall` selects/downloads matching release asset and resolves the runnable command.
- npm package exposes `"bin": { "graphonomous": "bin/graphonomous.js" }`.

---

## 3) Supported Targets (initial)

Start with:
- Linux x64
- Linux arm64
- macOS x64
- macOS arm64

Optional later:
- Windows x64

---

## 4) Versioning Rules

Use SemVer across Elixir app + npm wrapper:
- `mix.exs` version: `X.Y.Z`
- npm `package.json` version: `X.Y.Z`
- Git tag: `vX.Y.Z`
- Release artifact names include same `X.Y.Z`

Do not publish npm with a version that has no matching binary release assets.

---

## 5) One-Time Setup Checklist

## 5.1 npm package scope/name
Choose one:
- Unscoped: `graphonomous`
- Scoped: `@your-org/graphonomous`

Recommendation for broad adoption: `graphonomous` (if available).

## 5.2 npm account and auth
1. Create/login npm account.
2. Run:
   - `npm login`
3. Verify:
   - `npm whoami`

## 5.3 GitHub release permissions
Ensure you can create tags/releases and upload artifacts.

## 5.4 Add GitHub Actions release workflow
Use the repository workflow:

- `.github/workflows/release_npm.yml`

Workflow behavior:
1. Triggers on SemVer tags (`v*.*.*`) and manual dispatch.
2. Builds release assets for:
   - `linux-x64`
   - `linux-arm64`
   - `darwin-x64`
   - `darwin-arm64`
3. Packages assets as:
   - `graphonomous-vX.Y.Z-<target>.tar.gz`
4. Publishes/updates GitHub Release for the pushed tag.
5. Publishes npm package from `npm/` when tag version matches `npm/package.json`.

## 5.5 Required GitHub/npm Secrets

Configure these repository secrets before tag-based release:

- `NPM_TOKEN` (required)
  - npm automation token with publish permission for the target package.
- `GITHUB_TOKEN`
  - provided automatically by GitHub Actions; ensure workflow permissions include `contents: write` (already set in workflow).
- Optional for private release asset testing:
  - `GRAPHONOMOUS_GITHUB_TOKEN` (only needed for private asset download scenarios in installer tests)

Validation checklist:
1. `NPM_TOKEN` is added under repository settings.
2. npm account has access to publish the package name.
3. Workflow permission block includes `contents: write`.
4. Tag and npm version are aligned (`vX.Y.Z` == `npm/package.json` version).

---

## 6) npm Wrapper Layout (Scaffolded)

The npm wrapper scaffold is now present in this repo under `npm/`.

Current structure:
- `npm/package.json`
- `npm/README.md`
- `npm/bin/graphonomous.js`
- `npm/scripts/postinstall.js`
- `npm/scripts/resolve-platform.js`
- `npm/scripts/download-release-asset.js`
- `npm/vendor/.gitkeep`

Implemented behavior:
1. Determine platform/arch.
2. Locate/download matching binary release asset during install.
3. Mark executable (`chmod +x` on unix).
4. Spawn binary with passed-through args and stdio inherited.

---

## 7) Binary Naming Convention

Use deterministic names like:

- `graphonomous-vX.Y.Z-linux-x64.tar.gz`
- `graphonomous-vX.Y.Z-linux-arm64.tar.gz`
- `graphonomous-vX.Y.Z-darwin-x64.tar.gz`
- `graphonomous-vX.Y.Z-darwin-arm64.tar.gz`

Inside each archive (OTP release layout):
- `graphonomous/` (release root directory)
- `graphonomous/bin/graphonomous` (runnable command)
- release runtime directories/files required by BEAM/NIF dependencies

---

## 8) Release Procedure (Every Version)

## 8.1 Prepare release branch
From repo root:
- `git checkout -b release/vX.Y.Z`

## 8.2 Update versions
1. Edit `mix.exs`:
   - `version: "X.Y.Z"`
2. Edit `npm/package.json`:
   - `"version": "X.Y.Z"`

## 8.3 Run quality checks
From `ProjectAmp2/graphonomous`:
- `mix deps.get`
- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`

## 8.4 Build local OTP release sanity check
- `MIX_ENV=prod mix release --overwrite`
- `_build/prod/rel/graphonomous/bin/graphonomous start`

## 8.5 Commit + tag
- `git add .`
- `git commit -m "release: vX.Y.Z"`
- `git tag vX.Y.Z`
- `git push origin release/vX.Y.Z`
- `git push origin vX.Y.Z`

## 8.6 Publish GitHub Release with assets
Primary path (recommended):
- Push tag `vX.Y.Z`; GitHub Actions workflow `.github/workflows/release_npm.yml` creates/updates the release and uploads `dist/*.tar.gz`.

Verification:
- Confirm release exists for `vX.Y.Z`.
- Confirm all expected assets are attached:
  - `graphonomous-vX.Y.Z-linux-x64.tar.gz`
  - `graphonomous-vX.Y.Z-linux-arm64.tar.gz`
  - `graphonomous-vX.Y.Z-darwin-x64.tar.gz`
  - `graphonomous-vX.Y.Z-darwin-arm64.tar.gz`

## 8.7 Smoke test npm package locally before publish
From `npm/`:
- `npm pack`
- In temp dir: `npm i /path/to/graphonomous-X.Y.Z.tgz`
- Run:
  - `npx graphonomous --help`

## 8.8 Publish npm package
Primary path (recommended):
- Let `.github/workflows/release_npm.yml` publish automatically after release asset upload.

Manual fallback:
From `npm/`:
- `npm publish --access public`

Note:
- Workflow enforces tag/version parity:
  - `GITHUB_REF_NAME#v` must equal `npm/package.json` version.

## 8.9 Post-publish verification
Run:
- `npm view graphonomous version`
- `npx graphonomous --help`
- `npx graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback`

---

## 9) Zed MCP Quick Config (npm-installed command)

In Zed settings JSON:

{
  "context_servers": {
    "graphonomous": {
      "command": "graphonomous",
      "args": ["--db", "~/.graphonomous/knowledge.db", "--embedder-backend", "fallback"],
      "env": {
        "GRAPHONOMOUS_EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2"
      }
    }
  }
}

If using `npx` directly (not global install), use:
- `"command": "npx"`
- `"args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db", "--embedder-backend", "fallback"]`

---

## 10) Maintenance Routine (Keep Updated)

For every merged feature/fix that should ship:
1. Update `PROGRESS.md` change log.
2. Update root `README.md` user-facing install/run docs.
3. Update `docs/ZED.md` if MCP editor flow changed.
4. If CLI flags changed:
   - update `Graphonomous.CLI --help` text
   - update npm wrapper docs/examples
5. Cut a new SemVer release (`X.Y.Z`).

Monthly hygiene:
- test `npx graphonomous --help` on macOS + Linux
- verify GitHub release asset links are valid
- verify npm install path still works cleanly

---

## 11) Rollback and Hotfix

If bad npm publish:
1. Do NOT overwrite same version.
2. Publish hotfix version:
   - `X.Y.(Z+1)`
3. Deprecate bad version:
   - `npm deprecate graphonomous@X.Y.Z "Broken release; use X.Y.(Z+1)"`

If binary asset missing for a published npm version:
1. Publish missing GitHub release assets if possible.
2. If install logic still fails, publish patched npm version.

---

## 12) Security Notes

- Never hardcode API keys in package scripts.
- Treat downloaded binaries as trusted only from your official release source.
- Use checksums for release assets and verify at install time.
- Keep dependencies in npm wrapper minimal.

---

## 13) Minimal Command Cheat Sheet

From `ProjectAmp2/graphonomous`:

Release checks:
- `mix deps.get`
- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`
- `MIX_ENV=prod mix release --overwrite`
- `_build/prod/rel/graphonomous/bin/graphonomous start`

Tagging:
- `git tag vX.Y.Z`
- `git push origin vX.Y.Z`

npm (from `ProjectAmp2/graphonomous/npm`):
- `npm pack`
- `npm publish --access public`
- `npm view graphonomous version`
- `npx graphonomous --help`

---

## 14) Current Status Notes

As of now, Graphonomous already supports:
- executable CLI entrypoint (`Graphonomous.CLI`)
- stdio MCP launch path
- docs for bootstrap and Zed integration
- npm wrapper scaffold files committed under `npm/`
- npm packaging dry-run validation (`npm pack --dry-run`) with expected file set

This runbook now reflects an immediate publishing workflow using the already-scaffolded npm wrapper.