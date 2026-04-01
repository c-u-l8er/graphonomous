defmodule Graphonomous.MixProject do
  use Mix.Project

  def project do
    [
      app: :graphonomous,
      version: "0.1.12",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Graphonomous",
      description: "Continual learning engine — self-evolving knowledge graphs for AI agents",
      source_url: "https://github.com/c-u-l8er/graphonomous",
      escript: [main_module: Graphonomous.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Graphonomous.Application, []}
    ]
  end

  defp deps do
    [
      # MCP server (pinned to vendored patched source for reliable STDIO transport)
      {:anubis_mcp, path: "vendor/anubis_mcp"},

      # Storage
      {:exqlite, "~> 0.27"},
      # sqlite-vec wrapper (if this fails, pin to a commit/branch or load extension manually)
      {:sqlite_vec, github: "joelpaulkoch/sqlite_vec"},

      # Local embeddings
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.9"},
      # EXLA for fast GPU/CPU inference via XLA JIT compilation.
      # Requires LD_LIBRARY_PATH=/opt/cuda/lib64 at runtime for CUDA support.
      # If EXLA fails to load, embedder gracefully falls back to deterministic hashing.
      # Set GRAPHONOMOUS_EMBEDDER_BACKEND=fallback to skip EXLA entirely.
      {:exla, "~> 0.9", runtime: false},

      # Utilities
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
