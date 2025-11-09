require "test_helper"

class AuthenticateMagicLinkTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @service = AuthenticateMagicLink.new
  end

  test "authenticate with valid token returns success and user" do
    @user.generate_auth_token!
    token = @user.auth_token

    result = @service.authenticate(token)

    assert result.success?
    assert_equal @user, result.user
  end

  test "authenticate invalidates token after successful authentication" do
    @user.generate_auth_token!
    token = @user.auth_token

    @service.authenticate(token)

    @user.reload
    assert_nil @user.auth_token
    assert_nil @user.auth_token_expires_at
  end

  test "authenticate with invalid token returns failure" do
    result = @service.authenticate("invalid_token")

    assert_not result.success?
    assert_nil result.user
  end

  test "authenticate with expired token returns failure" do
    @user.update!(
      auth_token: "expired_token",
      auth_token_expires_at: 1.hour.ago
    )

    result = @service.authenticate("expired_token")

    assert_not result.success?
    assert_nil result.user
  end

  test "authenticate with nil token returns failure" do
    result = @service.authenticate(nil)

    assert_not result.success?
    assert_nil result.user
  end

  test "token cannot be reused after successful authentication" do
    @user.generate_auth_token!
    token = @user.auth_token

    # First authentication succeeds
    first_result = @service.authenticate(token)
    assert first_result.success?

    # Second authentication with same token fails
    second_result = @service.authenticate(token)
    assert_not second_result.success?
    assert_nil second_result.user
  end
end
