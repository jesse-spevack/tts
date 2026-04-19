require "test_helper"

class GetsApiTokenTest < ActiveSupport::TestCase
  test "call returns active token for user" do
    user = users(:one)

    token = GetsApiToken.call(user: user)

    assert_equal api_tokens(:active_token), token
  end

  test "call returns nil when user has no active tokens" do
    user = users(:one)
    user.api_tokens.active.each { |t| RevokesApiToken.call(token: t) }

    token = GetsApiToken.call(user: user)

    assert_nil token
  end

  test "call returns nil for user with no tokens" do
    user = users(:free_user)

    token = GetsApiToken.call(user: user)

    assert_nil token
  end

  test "call does not return revoked tokens" do
    user = users(:one)
    revoked_token = api_tokens(:revoked_token)

    token = GetsApiToken.call(user: user)

    assert_not_equal revoked_token, token
  end

  test "call does not return user-created tokens" do
    user = users(:one)
    user_token = api_tokens(:user_created_token)
    assert_equal user, user_token.user
    assert user_token.active?
    assert user_token.source_user?

    # Revoke the active extension token so it would fall through to the PAT
    # if the source filter were missing.
    RevokesApiToken.call(token: api_tokens(:active_token))

    token = GetsApiToken.call(user: user)

    assert_nil token,
      "GetsApiToken must only return extension-sourced tokens to prevent " \
      "'Disconnect Extension' from silently revoking user-created PATs"
  end
end
