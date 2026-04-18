require "test_helper"

class NarrationTest < ActiveSupport::TestCase
  test "expired? returns true when expires_at is in the past" do
    assert narrations(:expired).expired?
  end

  test "expired? returns false when expires_at is in the future" do
    refute narrations(:one).expired?
  end
end
