require "test_helper"

class FindsUserByAuthTokenTest < ActiveSupport::TestCase
  test "returns the user whose hashed auth_token matches the raw token" do
    user = users(:one)
    raw_token = GeneratesAuthToken.call(user: user)

    assert_equal user, FindsUserByAuthToken.call(raw_token: raw_token)
  end

  test "returns nil for a blank raw token" do
    assert_nil FindsUserByAuthToken.call(raw_token: nil)
    assert_nil FindsUserByAuthToken.call(raw_token: "")
  end

  test "returns nil for an unknown raw token" do
    assert_nil FindsUserByAuthToken.call(raw_token: "not_a_real_token")
  end

  test "returns nil when the matching user's token is expired" do
    user = users(:one)
    raw_token = GeneratesAuthToken.call(user: user)
    user.update!(auth_token_expires_at: 1.hour.ago)

    assert_nil FindsUserByAuthToken.call(raw_token: raw_token)
  end

  test "finds soft-deleted users (unscoped) so they can reach the restore flow" do
    user = users(:one)
    raw_token = GeneratesAuthToken.call(user: user)
    user.update!(deleted_at: Time.current)

    assert_equal user, FindsUserByAuthToken.call(raw_token: raw_token)
  end
end
