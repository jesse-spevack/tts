require "test_helper"

class AuthenticatesMagicLinkTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "call with valid token returns success and user" do
    token = GeneratesAuthToken.call(user: @user)

    result = AuthenticatesMagicLink.call(token: token)

    assert result.success?
    assert_equal @user, result.data
  end

  test "call invalidates token after successful authentication" do
    token = GeneratesAuthToken.call(user: @user)

    AuthenticatesMagicLink.call(token: token)

    @user.reload
    assert_nil @user.auth_token
    assert_nil @user.auth_token_expires_at
  end

  test "call with invalid token returns failure" do
    result = AuthenticatesMagicLink.call(token: "invalid_token")

    assert_not result.success?
    assert_nil result.data
  end

  test "call with expired token returns failure" do
    raw_token = "expired_token"
    hashed_token = BCrypt::Password.create(raw_token)

    @user.update!(
      auth_token: hashed_token,
      auth_token_expires_at: 1.hour.ago
    )

    result = AuthenticatesMagicLink.call(token: raw_token)

    assert_not result.success?
    assert_nil result.data
  end

  test "call with nil token returns failure" do
    result = AuthenticatesMagicLink.call(token: nil)

    assert_not result.success?
    assert_nil result.data
  end

  test "token cannot be reused after successful authentication" do
    token = GeneratesAuthToken.call(user: @user)

    # First authentication succeeds
    first_result = AuthenticatesMagicLink.call(token: token)
    assert first_result.success?

    # Second authentication with same token fails
    second_result = AuthenticatesMagicLink.call(token: token)
    assert_not second_result.success?
    assert_nil second_result.data
  end
end
