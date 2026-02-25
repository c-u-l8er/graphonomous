# Graphonomous + Zed MCP Setup Guide

This guide shows you how to run Graphonomous as an MCP server in **Zed** with a working local setup.

---

## 1) Prerequisites

- Elixir `~> 1.17`
- Erlang/OTP `27.x`
- Zed with Agent/AI features enabled

From the project root:

    cd ProjectAmp2/graphonomous

---

## 2) Choose a launch mode

You can run Graphonomous in two modes:

### A) Fast dev mode (recommended while iterating)

Use Mix with no compile step:

    mix run --no-compile -e 'Graphonomous.CLI.main(["--db","~/.graphonomous/knowledge.db","--embedder-backend","fallback"])'

This is the easiest way to test local changes quickly.

### B) Built executable mode (recommended for stable deployment)

Build the `graphonomous` executable:

    MIX_ENV=prod mix escript.build

This creates:

    ./graphonomous

---

## 3) Quick local run check (recommended)

Before wiring Zed, verify the command starts.

If using fast dev mode:

    mix run --no-compile -e 'Graphonomous.CLI.main(["--help"])'

If using built executable mode:

    ./graphonomous --help

Then run server mode (stdio MCP transport).

Fast dev mode:

    mix run --no-compile -e 'Graphonomous.CLI.main(["--db","~/.graphonomous/knowledge.db","--embedder-backend","fallback"])'

Built executable mode:

    ./graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback

Notes:
- `--embedder-backend fallback` is the safest default for constrained laptops.
- Press `Ctrl+C` to stop.

### MCP smoke test workflow (pre-deploy)

Run this before deploying or updating your Zed config:

    python scripts/mcp_smoke_test.py --cwd .

What it validates:
1. `initialize` handshake succeeds
2. `notifications/initialized` is accepted
3. `tools/list` responds
4. `resources/list` responds
5. response latencies stay within thresholds

Useful variants:

    # verbose stderr while testing
    python scripts/mcp_smoke_test.py --cwd . --tee-stderr

    # stricter latency gates (example)
    python scripts/mcp_smoke_test.py --cwd . --max-initialize-ms 2500 --max-discovery-ms 2500

---

## 4) Configure Zed (`context_servers`)

Open your Zed settings JSON and add one of the following.

### Option A: Built executable (recommended for stable use)

    {
      "context_servers": {
        "graphonomous": {
          "command": "/absolute/path/to/ProjectAmp2/graphonomous/graphonomous",
          "args": [
            "--db",
            "~/.graphonomous/knowledge.db",
            "--embedder-backend",
            "fallback"
          ],
          "env": {
            "GRAPHONOMOUS_EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2",
            "LOG_LEVEL": "info"
          }
        }
      }
    }

If `graphonomous` is on your `PATH`, you can use:

    "command": "graphonomous"

instead of an absolute path.

### Option B: Fast dev mode with no compile

    {
      "context_servers": {
        "graphonomous": {
          "command": "sh",
          "args": [
            "-lc",
            "cd /absolute/path/to/ProjectAmp2/graphonomous && mix run --no-compile -e 'Graphonomous.CLI.main([\"--db\",\"~/.graphonomous/knowledge.db\",\"--embedder-backend\",\"fallback\"])'"
          ],
          "env": {
            "LOG_LEVEL": "info"
          }
        }
      }
    }

Use Option B while actively changing code; switch to Option A for daily/stable usage.

---

## 5) Validate in Zed

1. Open the Agent panel.
2. Go to MCP/context server settings.
3. Confirm `graphonomous` is active (running indicator).
4. Start a prompt and ask it to use Graphonomous tools explicitly, e.g.:
   - “Use `graphonomous` to store this as semantic memory…”
   - “Use `graphonomous` to retrieve context for…”
   - “Use `graphonomous` to learn from this outcome…”

---

## 6) First-use workflow (fastest)

1. Store a few nodes with `store_node`.
2. Query them via `retrieve_context`.
3. Feed outcomes via `learn_from_outcome`.
4. Inspect runtime with `query_graph` and resource snapshots.

This gives you a full closed-loop memory flow without external integrations.

---

## 7) Optional: install command globally

If you want Zed to use `command: "graphonomous"` without absolute paths:

    sudo install -m 0755 ./graphonomous /usr/local/bin/graphonomous

Then confirm:

    graphonomous --help

---

## 8) Troubleshooting

### Server does not start in Zed
- Use absolute `command` path first.
- Verify executable permissions:
  
      chmod +x /absolute/path/to/graphonomous

- Test the exact command manually in terminal.

### Path/database issues
- Ensure parent dir exists:

      mkdir -p ~/.graphonomous

### Heavy model/runtime pressure on laptop
- Keep `--embedder-backend fallback`.
- Keep default model unless you intentionally change it.

### Zed shows server but tools are not being used
- Mention `graphonomous` by name in your prompt.
- Ask explicitly to call a specific tool (`store_node`, `retrieve_context`, etc.).

---

## 9) Minimal copy-paste config

    {
      "context_servers": {
        "graphonomous": {
          "command": "/absolute/path/to/ProjectAmp2/graphonomous/graphonomous",
          "args": ["--db", "~/.graphonomous/knowledge.db", "--embedder-backend", "fallback"],
          "env": {}
        }
      }
    }

---

## 10) Upgrade flow

When you pull new changes:

    cd ProjectAmp2/graphonomous
    git pull
    MIX_ENV=prod mix escript.build

If you installed globally, reinstall the binary:

    sudo install -m 0755 ./graphonomous /usr/local/bin/graphonomous