defmodule Graphonomous.ModelTier do
  @moduledoc """
  Hardware-adaptive model tier profiles and config helpers.

  Tiers represent effective reasoning capability, not raw model size.
  """

  @type model_tier :: :local_small | :local_large | :cloud_frontier

  @default_tier :local_small

  @profiles %{
    local_small: %{
      label: "Local 8B (e.g., Llama 3.1 8B, Qwen 2.5 7B, Gemma 2 9B)",
      effective_context_tokens: 4_096,
      max_nodes_per_prompt: 8,
      avg_inference_ms: 15_000,
      deliberation: %{
        strategy: :single_pass,
        max_agent_calls_per_scc: 1,
        max_iterations: 1,
        confidence_threshold: 0.6,
        timeout_multiplier: 3.0,
        kappa_deliberation_floor: 2
      },
      attention: %{
        trigger_mode: :demand,
        heartbeat_ms: :disabled,
        max_items_per_cycle: 1,
        max_explore_calls: 2,
        max_deliberation_sccs: 1,
        max_action_dispatches: 1,
        total_timeout_ms: 120_000,
        propose_enabled: false,
        default_autonomy: :observe
      },
      embedding: %{
        model: "all-MiniLM-L6-v2",
        dimensions: 384,
        device: :cpu,
        retrieval_limit: 10
      },
      crystallization: %{
        aggressive: true,
        cache_retrievals: true
      }
    },
    local_large: %{
      label: "Local 70B+ (e.g., Llama 3.1 70B, Qwen 2.5 72B, DeepSeek-V3)",
      effective_context_tokens: 16_384,
      max_nodes_per_prompt: 20,
      avg_inference_ms: 5_000,
      deliberation: %{
        strategy: :multi_pass,
        max_agent_calls_per_scc: 3,
        max_iterations: 3,
        confidence_threshold: 0.7,
        timeout_multiplier: 2.0,
        kappa_deliberation_floor: 1
      },
      attention: %{
        trigger_mode: :heartbeat,
        heartbeat_ms: 600_000,
        max_items_per_cycle: 2,
        max_explore_calls: 5,
        max_deliberation_sccs: 1,
        max_action_dispatches: 1,
        total_timeout_ms: 90_000,
        propose_enabled: false,
        default_autonomy: :advise
      },
      embedding: %{
        model: "nomic-embed-text",
        dimensions: 768,
        device: :gpu,
        retrieval_limit: 20
      },
      crystallization: %{
        aggressive: true,
        cache_retrievals: true
      }
    },
    cloud_frontier: %{
      label: "Cloud API (e.g., Claude, GPT, Gemini frontier models)",
      effective_context_tokens: 128_000,
      max_nodes_per_prompt: 50,
      avg_inference_ms: 1_500,
      deliberation: %{
        strategy: :multi_pass,
        max_agent_calls_per_scc: :budget,
        max_iterations: 5,
        confidence_threshold: 0.75,
        timeout_multiplier: 1.0,
        kappa_deliberation_floor: 1
      },
      attention: %{
        trigger_mode: :heartbeat,
        heartbeat_ms: 300_000,
        max_items_per_cycle: 3,
        max_explore_calls: 10,
        max_deliberation_sccs: 2,
        max_action_dispatches: 1,
        total_timeout_ms: 60_000,
        propose_enabled: true,
        default_autonomy: :advise
      },
      embedding: %{
        model: :provider_default,
        dimensions: :provider_default,
        device: :api,
        retrieval_limit: 50
      },
      crystallization: %{
        aggressive: false,
        cache_retrievals: false
      }
    }
  }

  @doc "Returns all supported tiers."
  @spec tiers() :: [model_tier()]
  def tiers, do: Map.keys(@profiles)

  @doc "Returns true if value can be normalized into a supported tier."
  @spec valid_tier?(term()) :: boolean()
  def valid_tier?(value), do: normalize_tier(value) in tiers()

  @doc """
  Returns the configured runtime tier.

  Reads `config :graphonomous, :model_tier`.
  Accepts atom/string values, including `:auto` (falls back to default).
  """
  @spec current_tier() :: model_tier()
  def current_tier do
    :graphonomous
    |> Application.get_env(:model_tier, @default_tier)
    |> normalize_tier()
  end

  @doc "Get the full profile for a tier. Invalid values fall back to the configured/default tier."
  @spec profile(model_tier() | String.t() | atom() | term()) :: map()
  def profile(tier \\ current_tier()) do
    tier = normalize_tier(tier)
    Map.fetch!(@profiles, tier)
  end

  @doc "Get the deliberation config for a tier."
  @spec deliberation_config(model_tier() | String.t() | atom() | term()) :: map()
  def deliberation_config(tier \\ current_tier()), do: profile(tier).deliberation

  @doc "Get the attention config for a tier."
  @spec attention_config(model_tier() | String.t() | atom() | term()) :: map()
  def attention_config(tier \\ current_tier()), do: profile(tier).attention

  @doc "Get the embedding config for a tier."
  @spec embedding_config(model_tier() | String.t() | atom() | term()) :: map()
  def embedding_config(tier \\ current_tier()), do: profile(tier).embedding

  @doc "Get the crystallization config for a tier."
  @spec crystallization_config(model_tier() | String.t() | atom() | term()) :: map()
  def crystallization_config(tier \\ current_tier()), do: profile(tier).crystallization

  @doc """
  Normalize unknown tier inputs into a supported tier.

  Mapping:
  - `:auto` or `"auto"` => default tier (`#{@default_tier}`)
  - unsupported values => default tier
  """
  @spec normalize_tier(term()) :: model_tier()
  def normalize_tier(:local_small), do: :local_small
  def normalize_tier(:local_large), do: :local_large
  def normalize_tier(:cloud_frontier), do: :cloud_frontier
  def normalize_tier(:auto), do: @default_tier

  def normalize_tier(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "local_small" -> :local_small
      "local-large" -> :local_large
      "local_large" -> :local_large
      "cloud_frontier" -> :cloud_frontier
      "cloud-frontier" -> :cloud_frontier
      "auto" -> @default_tier
      _ -> @default_tier
    end
  end

  def normalize_tier(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_tier()
  end

  def normalize_tier(_), do: @default_tier
end
