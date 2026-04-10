# graphonomous (npm wrapper)

**Continual learning memory loop for AI agents — 5 loop-phase MCP machines.**

One of four MCP servers in the [&] three-protocol stack:

| Package        | Role                                          | Install                                                          |
|----------------|-----------------------------------------------|------------------------------------------------------------------|
| `box-and-box`  | [&] Protocol validator / composer             | `npx -y box-and-box --db ~/.box-and-box/specs.db`                |
| `graphonomous` | Memory loop (**this**, 5 machines)            | `npx -y graphonomous --db ~/.graphonomous/knowledge.db`          |
| `os-prism`     | Diagnostic loop (6 machines)                  | `npx -y os-prism --db ~/.os-prism/benchmarks.db`                 |
| `os-pulse`     | PULSE manifest registry                       | `npx -y os-pulse --db ~/.os-pulse/manifests.db`                  |

Graphonomous exposes the five memory-loop machines — `retrieve`, `route`, `act`,
`learn`, `consolidate` — with κ-aware routing, causal metadata, and neural
embeddings. When PRISM benchmarks Graphonomous, the loops nest: `PRISM.interact
→ Graphonomous.retrieve → route → act → learn → consolidate → PRISM.observe`.

This package provides an npm-friendly launcher for the Graphonomous MCP server CLI.

It installs (or reuses) a platform-specific `graphonomous` binary and exposes:

- `graphonomous ...`
- `npx graphonomous ...`

The underlying server communicates over **STDIO**, so it works well with MCP-capable editors/clients (for example Claude Code, Zed, and Cursor).

---

## What this package does

- Detects your OS/arch (`darwin|linux` + `x64|arm64`)
- Downloads a matching release asset at install time
- Installs the OTP release command path under `vendor/<platform>-<arch>/graphonomous/bin/graphonomous` when available
- Creates/uses `vendor/<platform>-<arch>/graphonomous` as the launcher target for consistent execution
- Runs the resolved Graphonomous command with all arguments passed through

---

## Requirements

- Node.js `>= 18`
- Supported platforms:
  - macOS: `x64`, `arm64`
  - Linux: `x64`, `arm64`

---

## Install

### Global install

```sh
npm i -g graphonomous
```

Then run:

```sh
graphonomous --help
```

### One-off execution

```sh
npx -y graphonomous --help
```

### Local project install

```sh
npm i graphonomous
npx graphonomous --help
```

---

## Run examples

Start Graphonomous MCP server with a local DB path:

```sh
graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

Safe laptop-oriented defaults:

```sh
graphonomous \
  --db ~/.graphonomous/knowledge.db \
  --embedder-backend fallback \
  --log-level info
```

---

## Zed configuration example

In Zed settings JSON:

```json
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
```

If you prefer not to install globally:

```json
{
  "context_servers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db", "--embedder-backend", "fallback"],
      "env": {}
    }
  }
}
```

## Claude Code configuration

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "./.graphonomous/knowledge.db", "--embedder-backend", "fallback"]
    }
  }
}
```

To run the full four-package stack side by side:

```json
{
  "mcpServers": {
    "box-and-box":  { "command": "npx", "args": ["-y", "box-and-box",  "--db", "~/.box-and-box/specs.db"] },
    "graphonomous": { "command": "npx", "args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db", "--embedder-backend", "fallback"] },
    "os-prism":     { "command": "npx", "args": ["-y", "os-prism",     "--db", "~/.os-prism/benchmarks.db"] },
    "os-pulse":     { "command": "npx", "args": ["-y", "os-pulse",     "--db", "~/.os-pulse/manifests.db"] }
  }
}
```

---

## Release asset override instructions

By default, the installer resolves the GitHub release source from this package metadata (`repository.url`, then `homepage`, then `bugs.url`).

Current default source in this package points to:

- Owner: `c-u-l8er`
- Repo: `graphonomous`

So for version `X.Y.Z`, the default asset URL pattern is:

- `https://github.com/c-u-l8er/graphonomous/releases/download/vX.Y.Z/graphonomous-vX.Y.Z-<platform>-<arch>.tar.gz`

You can override this behavior with environment variables for custom repos/tags/asset hosting.

### Override GitHub owner/repo/tag

```sh
GRAPHONOMOUS_GITHUB_OWNER=my-org \
GRAPHONOMOUS_GITHUB_REPO=graphonomous \
GRAPHONOMOUS_RELEASE_TAG=v0.1.1 \
npm i graphonomous
```

### Override version used for asset naming

```sh
GRAPHONOMOUS_VERSION=0.1.1 npm i graphonomous
```

### Use custom release base URL (bypass GitHub release URL construction)

`GRAPHONOMOUS_RELEASE_BASE_URL` should point to a directory containing assets named like:

`graphonomous-v<version>-<platform>-<arch>.tar.gz`

Example:

```sh
GRAPHONOMOUS_RELEASE_BASE_URL=https://downloads.example.com/graphonomous \
GRAPHONOMOUS_VERSION=0.1.1 \
npm i graphonomous
```

### Private release download token

```sh
GRAPHONOMOUS_GITHUB_TOKEN=ghp_xxx npm i graphonomous
```

(You can also use `GITHUB_TOKEN`.)

### Skip, force, and tune download behavior

```sh
# Skip download entirely
GRAPHONOMOUS_SKIP_DOWNLOAD=1 npm i graphonomous

# Force re-download even if binary exists
GRAPHONOMOUS_FORCE_DOWNLOAD=1 npm i graphonomous

# Timeout and redirect controls
GRAPHONOMOUS_DOWNLOAD_TIMEOUT_MS=120000 \
GRAPHONOMOUS_DOWNLOAD_MAX_REDIRECTS=10 \
npm i graphonomous
```

---

### Runtime command override

You can bypass installed vendor binaries/release layout and point directly to a custom executable:

```sh
GRAPHONOMOUS_BINARY_PATH=/absolute/path/to/graphonomous graphonomous --help
```

---

## Troubleshooting

### Binary not found after install
Try reinstalling or rebuilding:

```sh
npm rebuild graphonomous
# or
npm i graphonomous@latest
```

### Unsupported platform message
Current prebuilt targets are Linux/macOS + x64/arm64.

### Permission issue on command path
Reinstall the package, or manually set executable bit on unix-like systems:

```sh
chmod +x node_modules/graphonomous/vendor/<target>/graphonomous
chmod +x node_modules/graphonomous/vendor/<target>/graphonomous/bin/graphonomous
```

---

## PULSE manifest

This package ships a PULSE loop manifest describing Graphonomous's 5-phase
continual learning loop:

- `graphonomous.continual_learning.pulse.json` (at the package root)

Any PULSE-conforming benchmark (for example `os-prism`) can read this file
directly to discover the loop's phases, signatures, substrates, and
cross-loop token connections. To register it with a running `os-pulse`
instance:

```bash
npx -y os-pulse --db ~/.os-pulse/manifests.db
# then, from another shell or an MCP client:
#   pulse.register { "path": "$(npm root -g)/graphonomous/graphonomous.continual_learning.pulse.json" }
```

---

## Source of truth

The npm package is a distribution wrapper around the Graphonomous Elixir CLI.
Core implementation and release process live in the Graphonomous repository.