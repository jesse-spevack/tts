require "test_helper"

class AuthenticateMagicLinkTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "call with valid token returns success and user" do
    GenerateAuthToken.call(user: @user)
    token = @user.auth_token

    result = AuthenticateMagicLink.call(token: token)

    assert result.success?
    assert_equal @user, result.user
  end

  test "call invalidates token after successful authentication" do
    GenerateAuthToken.call(user: @user)
    token = @user.auth_token

    AuthenticateMagicLink.call(token: token)

    @user.reload
    assert_nil @user.auth_token
    assert_nil @user.auth_token_expires_at
  end

  test "call with invalid token returns failure" do
    result = AuthenticateMagicLink.call(token: "invalid_token")

    assert_not result.success?
    assert_nil result.user
  end

  test "call with expired token returns failure" do
    @user.update!(
      auth_token: "expired_token",
      auth_token_expires_at: 1.hour.ago
    )

    result = AuthenticateMagicLink.call(token: "expired_token")

    assert_not result.success?
    assert_nil result.user
  end

  test "call with nil token returns failure" do
    result = AuthenticateMagicLink.call(token: nil)

    assert_not result.success?
    assert_nil result.user
  end

  test "token cannot be reused after successful authentication" do
    GenerateAuthToken.call(user: @user)
    token = @user.auth_token

    # First authentication succeeds
    first_result = AuthenticateMagicLink.call(token: token)
    assert first_result.success?

    # Second authentication with same token fails
    second_result = AuthenticateMagicLink.call(token: token)
    assert_not second_result.success?
    assert_nil second_result.user
  end
end
