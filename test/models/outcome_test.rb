# frozen_string_literal: true

require "test_helper"

class OutcomeTest < ActiveSupport::TestCase
  test "success creates successful outcome with message" do
    outcome = Outcome.success("It worked")

    assert outcome.success?
    refute outcome.failure?
    assert_equal "It worked", outcome.message
    assert_nil outcome.error
    assert_nil outcome.data
  end

  test "success works with nil message" do
    outcome = Outcome.success

    assert outcome.success?
    assert_nil outcome.message
  end

  test "success accepts optional data kwargs" do
    outcome = Outcome.success("Allowed", remaining: 5)

    assert outcome.success?
    assert_equal "Allowed", outcome.message
    assert_equal({ remaining: 5 }, outcome.data)
  end

  test "failure creates failed outcome with message" do
    outcome = Outcome.failure("Not allowed")

    refute outcome.success?
    assert outcome.failure?
    assert_equal "Not allowed", outcome.message
    assert_nil outcome.data
  end

  test "failure accepts optional error" do
    error = StandardError.new("details")
    outcome = Outcome.failure("Failed", error: error)

    assert outcome.failure?
    assert_equal "Failed", outcome.message
    assert_equal error, outcome.error
  end

  test "outcomes are frozen" do
    outcome = Outcome.success("test")

    assert outcome.frozen?
  end

  test "flash_type returns notice for success" do
    outcome = Outcome.success("Yay")

    assert_equal :notice, outcome.flash_type
  end

  test "flash_type returns alert for failure" do
    outcome = Outcome.failure("Nope")

    assert_equal :alert, outcome.flash_type
  end
end
