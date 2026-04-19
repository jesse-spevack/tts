require "test_helper"

class FindsUserByEmailTest < ActiveSupport::TestCase
  test "returns an active user matched by email" do
    user = users(:one)

    assert_equal user, FindsUserByEmail.call(email_address: user.email_address)
  end

  test "returns a soft-deleted user (unscoped) so the revive flow can bind" do
    user = users(:one)
    user.update!(deleted_at: Time.current)

    assert_equal user, FindsUserByEmail.call(email_address: user.email_address)
  end

  test "returns nil when no user matches" do
    assert_nil FindsUserByEmail.call(email_address: "nobody@example.com")
  end
end
