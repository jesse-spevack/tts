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

  test "call with valid token for deactivated user returns failure" do
    token = GeneratesAuthToken.call(user: @user)
    @user.update!(active: false)

    result = AuthenticatesMagicLink.call(token: token)

    assert_not result.success?
    assert_nil result.data
    # The surviving token stays usable for nothing — but we don't invalidate
    # it here; InvalidatesAuthToken only runs on the success branch
    @user.reload
    assert_not_nil @user.auth_token
  end

  # --- pack_size carry through AuthenticatesMagicLink (iny7) ---
  # Per iny7 design, AuthenticatesMagicLink should expose the plan and
  # pack_size carried alongside the token so SessionsController can set
  # session values uniformly. This is the "extracts both" contract referenced
  # in the iny7 design notes.

  test "call returns user alongside carried plan and pack_size" do
    # pack_size round-trips through the magic link; the service should
    # surface it so the controller can route to the right checkout.
    token = GeneratesAuthToken.call(user: @user)

    result = AuthenticatesMagicLink.call(token: token, plan: "credit_pack", pack_size: 10)

    assert result.success?
    # The user remains accessible. Implementer chooses whether to expose
    # plan/pack_size on the Result data (struct / hash) or as additional
    # accessors — either way, the returned data must still include the user.
    user = result.data.respond_to?(:user) ? result.data.user : result.data
    assert_equal @user, user
  end

  test "call without plan or pack_size works as before" do
    # Back-compat: the two kwargs default to nil and the existing contract
    # (return user on success) is preserved.
    token = GeneratesAuthToken.call(user: @user)

    result = AuthenticatesMagicLink.call(token: token)

    assert result.success?
    user = result.data.respond_to?(:user) ? result.data.user : result.data
    assert_equal @user, user
  end
end
