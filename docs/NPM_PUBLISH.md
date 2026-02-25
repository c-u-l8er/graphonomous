# Graphonomous npm Publishing + Maintenance Runbook (Manual-First)

This runbook is the **manual release path** for publishing `graphonomous` without relying on long-lived CI publish credentials.

It is designed for the reality that npm credentials/tokens may rotate or expire frequently.

---

## 1) Goal

Publish Graphonomous so users can run:

- `npx graphonomous --help`
- `npm i -g graphonomous`
- `graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback`

while keeping the Elixir implementation as source of truth.

---

## 2) Principles

1. **Manual over automated publish**
   - You run the release and npm publish commands locally.
2. **No dependency on permanent CI tokens**
   - No long-lived npm automation token required.
3. **Version parity is strict**
   - `mix.exs`, `npm/package.json`, git tag, and release assets must all match.
4. **Never overwrite versions**
   - npm versions are immutable once published.

---

## 3) Required Local Tooling

- Elixir `1.17.x`
- Erlang/OTP `27.x`
- Node.js `>= 18`
- npm account with publish permission
- `git`
- `tar` (for packaging release assets)
- Optional: `gh` CLI (otherwise use GitHub web UI)

---

## 4) One-Time Setup

## 4.1 npm auth
- Run `npm login`
- Verify with `npm whoami`

If your org/package requires 2FA, keep your authenticator available during `npm publish`.

## 4.2 Repo/package naming
Package is expected as:
- `graphonomous` (unscoped)  
or
- `@your-org/graphonomous` (scoped)

---

## 5) Release Asset Convention

Release assets are platform-specific `.tar.gz` files:

- `graphonomous-vX.Y.Z-linux-x64.tar.gz`
- `graphonomous-vX.Y.Z-linux-arm64.tar.gz`
- `graphonomous-vX.Y.Z-darwin-x64.tar.gz`
- `graphonomous-vX.Y.Z-darwin-arm64.tar.gz`

Each archive should contain the OTP release root:

- `graphonomous/`
- `graphonomous/bin/graphonomous`
- required runtime dirs/files for BEAM + NIFs

---

## 6) Full Manual Release Procedure (No GitHub Actions Publish Step)

Perform from repo root (`ProjectAmp2/graphonomous`).

## 6.1 Create release branch
    git checkout -b release/vX.Y.Z

## 6.2 Update versions
1. `mix.exs` → `version: "X.Y.Z"`
2. `npm/package.json` → `"version": "X.Y.Z"`

## 6.3 Quality checks
    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test

## 6.4 Build OTP release locally
    MIX_ENV=prod mix release --overwrite

Sanity check command path:
    _build/prod/rel/graphonomous/bin/graphonomous version

CLI sanity check via eval entrypoint:
    _build/prod/rel/graphonomous/bin/graphonomous eval "Graphonomous.CLI.main(System.argv())" --help

## 6.5 Create release assets locally

Example for your current machine target:
    VERSION=X.Y.Z
    TARGET=linux-x64
    mkdir -p dist
    tar -czf "dist/graphonomous-v${VERSION}-${TARGET}.tar.gz" -C "_build/prod/rel" graphonomous

Repeat on each required OS/arch machine to produce all target artifacts:
- linux x64
- linux arm64
- macOS x64
- macOS arm64

## 6.6 Commit + tag
    git add .
    git commit -m "release: vX.Y.Z"
    git tag vX.Y.Z
    git push origin release/vX.Y.Z
    git push origin vX.Y.Z

## 6.7 Create GitHub Release manually

Option A: GitHub Web UI
1. Open Releases → Draft new release
2. Tag: `vX.Y.Z`
3. Title: `vX.Y.Z`
4. Upload all `dist/*.tar.gz` assets
5. Publish release

Option B: `gh` CLI
    gh release create "vX.Y.Z" dist/*.tar.gz --title "vX.Y.Z" --notes "Manual release"

Verify uploaded assets match naming convention exactly.

## 6.8 npm pre-publish smoke test (local)
From `npm/`:
    cd npm
    npm pack --dry-run
    npm pack

In a temporary directory:
    mkdir -p /tmp/graphonomous-npm-smoke
    cd /tmp/graphonomous-npm-smoke
    npm init -y
    npm i /absolute/path/to/ProjectAmp2/graphonomous/npm/graphonomous-X.Y.Z.tgz
    npx graphonomous --help

## 6.9 Publish npm manually (local machine)
From `ProjectAmp2/graphonomous/npm`:
    npm publish --access public

If 2FA is enabled, complete OTP prompt.

## 6.10 Post-publish verification
    npm view graphonomous version
    npx -y graphonomous --help
    npx -y graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback

---

## 7) Zed Config (npm-installed command)

Use in Zed settings JSON:

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

Or one-off via `npx`:

{
  "context_servers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db", "--embedder-backend", "fallback"],
      "env": {}
    }
  }
}

---

## 8) Maintenance Routine

For each shipped change:
1. Update `PROGRESS.md`.
2. Update root `README.md` user docs.
3. Update `docs/ZED.md` if editor setup changed.
4. If CLI args changed, update:
   - `Graphonomous.CLI` help text
   - `npm/README.md`
   - this runbook if needed
5. Cut next SemVer release (`X.Y.Z`).

Monthly:
- Test `npx -y graphonomous --help` on Linux + macOS.
- Verify GitHub release assets are accessible.
- Verify fresh npm install works.

---

## 9) Rollback / Hotfix Policy

If bad npm publish:
1. Do not republish same version.
2. Publish patch increment (`X.Y.(Z+1)`).
3. Deprecate broken version:
    npm deprecate graphonomous@X.Y.Z "Broken release; use X.Y.(Z+1)"

If release assets are missing:
1. Upload missing assets to the existing GitHub release for that version (if possible).
2. If npm installs are already broken, publish fixed patch version.

---

## 10) Security Notes (Manual Flow)

- Do not commit tokens or credentials.
- Use local `npm login` sessions only on trusted machines.
- Keep local environment clean after release work.
- Prefer short-lived credentials and explicit logout if needed:
    npm logout
- Use checksums/signatures for release artifacts when you add that capability.

---

## 11) Minimal Command Cheat Sheet

From repo root:
    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test
    MIX_ENV=prod mix release --overwrite

Asset packaging:
    VERSION=X.Y.Z
    TARGET=linux-x64
    mkdir -p dist
    tar -czf "dist/graphonomous-v${VERSION}-${TARGET}.tar.gz" -C "_build/prod/rel" graphonomous

Tagging:
    git tag vX.Y.Z
    git push origin vX.Y.Z

npm publish (manual):
    cd npm
    npm pack --dry-run
    npm publish --access public
    npm view graphonomous version

---

## 12) Current Status

Graphonomous already has:
- `Graphonomous.CLI` entrypoint
- stdio MCP launch path
- npm wrapper scaffold under `npm/`
- docs for bootstrap and Zed integration

This runbook is now explicitly optimized for **manual releases and manual npm publish**, with no dependency on permanent GitHub Actions publish credentials.