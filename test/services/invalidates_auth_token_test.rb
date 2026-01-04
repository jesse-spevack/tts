require "test_helper"

class InvalidatesAuthTokenTest < ActiveSupport::TestCase
  test "call sets auth_token to nil" do
    user = users(:one)
    user.update!(auth_token: "some_token", auth_token_expires_at: 30.minutes.from_now)

    InvalidatesAuthToken.call(user: user)

    user.reload
    assert_nil user.auth_token
  end

  test "call sets auth_token_expires_at to nil" do
    user = users(:one)
    user.update!(auth_token: "some_token", auth_token_expires_at: 30.minutes.from_now)

    InvalidatesAuthToken.call(user: user)

    user.reload
    assert_nil user.auth_token_expires_at
  end

  test "call persists changes to database" do
    user = users(:one)
    user.update!(auth_token: "some_token", auth_token_expires_at: 30.minutes.from_now)

    InvalidatesAuthToken.call(user: user)

    user_from_db = User.find(user.id)
    assert_nil user_from_db.auth_token
    assert_nil user_from_db.auth_token_expires_at
  end
end
