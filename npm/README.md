# graphonomous (npm wrapper)

This package provides an npm-friendly launcher for the Graphonomous MCP server CLI.

It installs (or reuses) a platform-specific `graphonomous` binary and exposes:

- `graphonomous ...`
- `npx graphonomous ...`

The underlying server communicates over **STDIO**, so it works well with MCP-capable editors/clients (for example Zed custom context servers).

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

---

## Release asset override instructions

The installer supports override environment variables for custom repos/tags/asset hosting.

### Override GitHub owner/repo/tag

```sh
GRAPHONOMOUS_GITHUB_OWNER=my-org \
GRAPHONOMOUS_GITHUB_REPO=graphonomous \
GRAPHONOMOUS_RELEASE_TAG=v0.1.0 \
npm i graphonomous
```

### Override version used for asset naming

```sh
GRAPHONOMOUS_VERSION=0.1.0 npm i graphonomous
```

### Use custom release base URL (bypass GitHub release URL construction)

`GRAPHONOMOUS_RELEASE_BASE_URL` should point to a directory containing assets named like:

`graphonomous-v<version>-<platform>-<arch>.tar.gz`

Example:

```sh
GRAPHONOMOUS_RELEASE_BASE_URL=https://downloads.example.com/graphonomous \
GRAPHONOMOUS_VERSION=0.1.0 \
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

## Source of truth

The npm package is a distribution wrapper around the Graphonomous Elixir CLI.  
Core implementation and release process live in the Graphonomous repository.