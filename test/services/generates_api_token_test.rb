require "test_helper"

class GeneratesApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
  end

  test "call generates new api token for user" do
    assert_difference "ApiToken.count", 1 do
      GeneratesApiToken.call(user: @user)
    end
  end

  test "call returns api token with plain_token accessible" do
    api_token = GeneratesApiToken.call(user: @user)

    assert api_token.is_a?(ApiToken)
    assert api_token.plain_token.present?
    assert api_token.plain_token.start_with?("pk_test_")
  end

  test "call creates token associated with user" do
    api_token = GeneratesApiToken.call(user: @user)

    assert_equal @user, api_token.user
  end

  test "call revokes existing active tokens for user" do
    # Generate first token
    first_token = GeneratesApiToken.call(user: @user)
    assert first_token.active?

    # Generate second token
    second_token = GeneratesApiToken.call(user: @user)

    # First token should now be revoked
    first_token.reload
    assert first_token.revoked?

    # Second token should be active
    assert second_token.active?
  end

  test "call generates unique tokens each time" do
    token1 = GeneratesApiToken.call(user: @user)
    token2 = GeneratesApiToken.call(user: @user)

    assert_not_equal token1.plain_token, token2.plain_token
  end

  test "call generates tokens that can be found by ApiToken.find_by_token" do
    api_token = GeneratesApiToken.call(user: @user)
    plain_token = api_token.plain_token

    found_token = ApiToken.find_by_token(plain_token)
    assert_not_nil found_token
    assert_equal api_token.id, found_token.id
  end

  test "call creates token with correct digest" do
    api_token = GeneratesApiToken.call(user: @user)

    assert api_token.token_digest.present?
    assert_not_equal api_token.plain_token, api_token.token_digest
  end

  test "call does not affect tokens for other users" do
    user2 = users(:two)
    other_token = GeneratesApiToken.call(user: user2)
    assert other_token.active?

    # Generate token for original user
    GeneratesApiToken.call(user: @user)

    # Other user's token should still be active
    other_token.reload
    assert other_token.active?
  end
end
