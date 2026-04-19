require "test_helper"

class RotatesExtensionTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "revokes all active extension tokens and issues a new one" do
    existing_extension = api_tokens(:active_token)
    assert_equal @user, existing_extension.user
    assert existing_extension.source_extension?

    new_token = RotatesExtensionToken.call(user: @user)

    existing_extension.reload
    assert existing_extension.revoked?
    assert new_token.active?
    assert new_token.source_extension?
    assert_equal @user, new_token.user
  end

  test "does not revoke the user's user-created tokens" do
    user_token = api_tokens(:user_created_token)
    assert user_token.active?

    RotatesExtensionToken.call(user: @user)

    user_token.reload
    assert user_token.active?, "user-created tokens must survive extension rotation"
  end

  test "does not revoke other users' extension tokens" do
    other_user = users(:two)
    other_user_token = api_tokens(:recently_used_token)
    assert_equal other_user, other_user_token.user
    assert other_user_token.active?

    RotatesExtensionToken.call(user: @user)

    other_user_token.reload
    assert other_user_token.active?, "rotation for user A must never touch user B's tokens"
  end

  test "returns a token with plain_token set for caller display" do
    new_token = RotatesExtensionToken.call(user: @user)

    assert new_token.plain_token.present?
    assert new_token.plain_token.start_with?("sk_live_")
  end
end
