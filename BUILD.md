BUILD
========

Manual npm Publish Path (No CI Token Dependency)
------------------------------------------------

This guide handles the exact case where `npm i -g graphonomous` fails because the expected GitHub release asset does not exist yet.

Error pattern:
- npm postinstall tries to download:
  `https://github.com/c-u-l8er/graphonomous/releases/download/vX.Y.Z/graphonomous-vX.Y.Z-linux-x64.tar.gz`
- install fails with `HTTP 404` when release/tag/assets are missing.

---

Prerequisites
-------------

- You are in this repo: `ProjectAmp2/graphonomous`
- `gh auth status` is valid for the target GitHub account/org
- `npm whoami` is valid for the npm publisher account
- Local toolchain is installed (Elixir/OTP, Node/npm, git, tar)

---

0) Set version once (important)
-------------------------------

Pick one version and use it consistently in all commands below.

```bash
VERSION="0.1.1"
TAG="v${VERSION}"
TARGET="linux-x64"
ASSET="graphonomous-v${VERSION}-${TARGET}.tar.gz"
```

---

1) Ensure local project version matches
---------------------------------------

Confirm versions:
- `mix.exs` -> `version: "0.1.1"`
- `npm/package.json` -> `"version": "0.1.1"`

Quick checks:

```bash
grep -n 'version:' mix.exs
node -p "require('./npm/package.json').version"
```

---

2) Build OTP release and package asset
--------------------------------------

```bash
cd /home/travis/ProjectAmp2/graphonomous
MIX_ENV=prod mix release --overwrite
mkdir -p dist
tar -czf "dist/${ASSET}" -C _build/prod/rel graphonomous
ls -lh "dist/${ASSET}"
```

Sanity check the release command:

```bash
_build/prod/rel/graphonomous/bin/graphonomous version
_build/prod/rel/graphonomous/bin/graphonomous eval "Graphonomous.CLI.main(System.argv())" --help
```

---

3) Create tag if missing and push it
------------------------------------

Check if the tag exists locally/remotely:

```bash
git tag --list "${TAG}"
git ls-remote --tags origin "${TAG}"
```

If missing locally:

```bash
git tag "${TAG}"
```

Push tag (safe if already present remotely; it will fail noisily if conflicting):

```bash
git push origin "${TAG}"
```

---

4) Create GitHub release if missing
-----------------------------------

Your previous error `release not found` means this step is required.

Create release and upload first asset in one command:

```bash
gh release create "${TAG}" "dist/${ASSET}" \
  --title "${TAG}" \
  --notes "Manual release assets upload"
```

If release already exists, upload (or replace) asset:

```bash
gh release upload "${TAG}" "dist/${ASSET}" --clobber
```

Verify release + assets:

```bash
gh release view "${TAG}"
gh release view "${TAG}" --json assets --jq '.assets[].name'
```

---

5) Re-test npm install
----------------------

```bash
npm i -g graphonomous
graphonomous --help
```

If global install was partially broken earlier, clean and retry:

```bash
npm uninstall -g graphonomous
npm cache verify
npm i -g graphonomous
```

---

6) Optional: Quick runtime smoke test
-------------------------------------

```bash
mkdir -p ~/.graphonomous
graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

(Stop with `Ctrl+C` after startup confirmation.)

---

If release creation still fails
-------------------------------

### A) `gh release create ...` says tag is missing
Push the tag first:

```bash
git push origin "${TAG}"
```

### B) Permission error on release create/upload
Check GitHub auth/account:

```bash
gh auth status
gh repo view
```

Ensure you have write access to `c-u-l8er/graphonomous`.

### C) npm still fails with 404
Confirm asset naming exactly matches what installer expects:

```bash
echo "Expected: ${ASSET}"
gh release view "${TAG}" --json assets --jq '.assets[].name'
```

Name must match exactly:
`graphonomous-vX.Y.Z-linux-x64.tar.gz`

---

Multi-platform publishing (later)
---------------------------------

For broader support, repeat asset build/upload on each target machine:

- `linux-x64`
- `linux-arm64`
- `darwin-x64`
- `darwin-arm64`

Asset names must follow:

- `graphonomous-vX.Y.Z-linux-x64.tar.gz`
- `graphonomous-vX.Y.Z-linux-arm64.tar.gz`
- `graphonomous-vX.Y.Z-darwin-x64.tar.gz`
- `graphonomous-vX.Y.Z-darwin-arm64.tar.gz`

---

Minimal command checklist
-------------------------

```bash
cd /home/travis/ProjectAmp2/graphonomous
VERSION="0.1.1"; TAG="v${VERSION}"; TARGET="linux-x64"; ASSET="graphonomous-v${VERSION}-${TARGET}.tar.gz"
MIX_ENV=prod mix release --overwrite
mkdir -p dist
tar -czf "dist/${ASSET}" -C _build/prod/rel graphonomous
git tag "${TAG}" 2>/dev/null || true
git push origin "${TAG}"
gh release create "${TAG}" "dist/${ASSET}" --title "${TAG}" --notes "Manual release assets upload" || gh release upload "${TAG}" "dist/${ASSET}" --clobber
npm i -g graphonomous
graphonomous --help
```
