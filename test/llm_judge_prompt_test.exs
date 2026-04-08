defmodule Mix.Tasks.Benchmark.LlmJudgePromptTest do
  @moduledoc """
  Tests for LLM judge ability-specific prompt instructions.
  Verifies the context schema, anti-IDK rules, and ability-specific guidance.
  """
  use ExUnit.Case, async: true

  # Access the public ability_specific_instruction function
  # These are private, so we test indirectly through the module attributes

  describe "ability-specific instructions" do
    test "knowledge_update instruction references USER CLAIMS section" do
      instruction = get_instruction("knowledge_update")

      assert instruction =~ "USER CLAIMS"
      assert instruction =~ "[UPDATE]"
      assert instruction =~ "MOST RECENT"
    end

    test "information_extraction instruction references USER STATEMENTS" do
      instruction = get_instruction("information_extraction")

      assert instruction =~ "USER STATEMENTS"
      assert instruction =~ "USER turn"
    end

    test "multi_session_reasoning includes anti-IDK instruction" do
      instruction = get_instruction("multi_session_reasoning")

      assert instruction =~ "NEVER refuse"
      assert instruction =~ "Partial evidence"
    end

    test "temporal_reasoning includes chain-of-thought steps" do
      instruction = get_instruction("temporal_reasoning")

      assert instruction =~ "chronological order"
      assert instruction =~ "arithmetic"
      assert instruction =~ "Step 1"
    end

    test "abstention instruction requires explicit evidence" do
      instruction = get_instruction("abstention")

      assert instruction =~ "EXPLICITLY stated"
      assert instruction =~ "Do NOT infer"
    end

    test "unknown ability returns empty string" do
      instruction = get_instruction("nonexistent_ability")
      assert instruction == ""
    end
  end

  # Access private function via apply — these are defp, so we use
  # a compile-time trick: the test module defines its own accessor.
  # Since ability_specific_instruction is defp, we test by verifying
  # the module compiles and the instructions are embedded in the
  # generate_answer prompt.
  defp get_instruction(ability) do
    # The function is private, so we call it through the module's
    # internal mechanism. In Elixir, we can use :erlang.apply on
    # compiled BEAM modules for any function regardless of visibility.
    :erlang.apply(Mix.Tasks.Benchmark.LlmJudge, :ability_specific_instruction, [ability])
  end
end
