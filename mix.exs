defmodule Graphonomous.MixProject do
  use Mix.Project

  def project do
    [
      app: :graphonomous,
      version: "0.1.1",
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
      # MCP server
      {:anubis_mcp, "~> 0.17"},

      # Storage
      {:exqlite, "~> 0.27"},
      # sqlite-vec wrapper (if this fails, pin to a commit/branch or load extension manually)
      {:sqlite_vec, github: "joelpaulkoch/sqlite_vec"},

      # Local embeddings
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.9"},
      # EXLA is intentionally optional for now to avoid CUDA-linked NIF startup failures.
      # Add it back when your runtime has a compatible CPU/CUDA setup.

      # Utilities
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
