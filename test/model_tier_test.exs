defmodule Graphonomous.ModelTierTest do
  use ExUnit.Case, async: true

  alias Graphonomous.ModelTier

  test "profile/1 returns correct defaults for each tier" do
    for tier <- [:local_small, :local_large, :cloud_frontier] do
      profile = ModelTier.profile(tier)

      assert is_map(profile)
      assert is_binary(profile.label)
      assert is_map(profile.deliberation)
      assert is_map(profile.attention)
      assert is_map(profile.embedding)
      assert is_map(profile.crystallization)
      assert is_integer(profile.effective_context_tokens)
      assert is_integer(profile.max_nodes_per_prompt)
      assert is_integer(profile.avg_inference_ms)
    end
  end

  test "deliberation_config/1 returns tier-appropriate strategy" do
    assert ModelTier.deliberation_config(:local_small).strategy == :single_pass
    assert ModelTier.deliberation_config(:local_large).strategy == :multi_pass
    assert ModelTier.deliberation_config(:cloud_frontier).strategy == :multi_pass
  end

  test "attention_config/1 returns tier-appropriate trigger_mode" do
    assert ModelTier.attention_config(:local_small).trigger_mode == :demand
    assert ModelTier.attention_config(:local_large).trigger_mode == :heartbeat
    assert ModelTier.attention_config(:cloud_frontier).trigger_mode == :heartbeat
  end

  test "local_small has single_pass strategy and demand trigger" do
    deliberation = ModelTier.deliberation_config(:local_small)
    attention = ModelTier.attention_config(:local_small)

    assert deliberation.strategy == :single_pass
    assert attention.trigger_mode == :demand
  end

  test "local_large has multi_pass strategy and heartbeat trigger" do
    deliberation = ModelTier.deliberation_config(:local_large)
    attention = ModelTier.attention_config(:local_large)

    assert deliberation.strategy == :multi_pass
    assert attention.trigger_mode == :heartbeat
  end

  test "cloud_frontier has multi_pass strategy and heartbeat trigger" do
    deliberation = ModelTier.deliberation_config(:cloud_frontier)
    attention = ModelTier.attention_config(:cloud_frontier)

    assert deliberation.strategy == :multi_pass
    assert attention.trigger_mode == :heartbeat
  end

  test "local_small has kappa_deliberation_floor of 2" do
    assert ModelTier.deliberation_config(:local_small).kappa_deliberation_floor == 2
  end

  test "local_large has kappa_deliberation_floor of 1" do
    assert ModelTier.deliberation_config(:local_large).kappa_deliberation_floor == 1
  end
end
