require "test_helper"

class LlmUsageTest < ActiveSupport::TestCase
  test "belongs to episode" do
    usage = LlmUsage.new(
      episode: episodes(:one),
      model_id: "claude-3-haiku",
      provider: "vertex_ai",
      input_tokens: 1000,
      output_tokens: 500,
      cost_cents: 0.05
    )
    assert usage.valid?
    assert_equal episodes(:one), usage.episode
  end

  test "requires episode" do
    usage = LlmUsage.new(
      model_id: "claude-3-haiku",
      provider: "vertex_ai",
      input_tokens: 1000,
      output_tokens: 500,
      cost_cents: 0.05
    )
    assert_not usage.valid?
    assert_includes usage.errors[:episode], "must exist"
  end

  test "requires model_id" do
    usage = LlmUsage.new(
      episode: episodes(:one),
      provider: "vertex_ai",
      input_tokens: 1000,
      output_tokens: 500
    )
    assert_not usage.valid?
    assert_includes usage.errors[:model_id], "can't be blank"
  end

  test "requires provider" do
    usage = LlmUsage.new(
      episode: episodes(:one),
      model_id: "claude-3-haiku",
      input_tokens: 1000,
      output_tokens: 500
    )
    assert_not usage.valid?
    assert_includes usage.errors[:provider], "can't be blank"
  end

  test "cost_dollars converts cents to dollars" do
    usage = LlmUsage.new(cost_cents: 5.25)
    assert_equal 0.0525, usage.cost_dollars
  end
end
