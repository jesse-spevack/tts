require "test_helper"

class FindsApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    @api_token = GeneratesApiToken.call(user: @user)
    @plain_token = @api_token.plain_token
  end

  test "call returns token for valid plain token" do
    found_token = FindsApiToken.call(plain_token: @plain_token)

    assert_not_nil found_token
    assert_equal @api_token.id, found_token.id
  end

  test "call returns nil for invalid token" do
    result = FindsApiToken.call(plain_token: "pk_test_invalid_token_12345")

    assert_nil result
  end

  test "call returns nil for revoked token" do
    RevokesApiToken.call(token: @api_token)

    result = FindsApiToken.call(plain_token: @plain_token)

    assert_nil result
  end

  test "call returns nil for nil token" do
    result = FindsApiToken.call(plain_token: nil)

    assert_nil result
  end

  test "call returns nil for empty string token" do
    result = FindsApiToken.call(plain_token: "")

    assert_nil result
  end

  test "call returns nil for whitespace-only token" do
    result = FindsApiToken.call(plain_token: "   ")

    assert_nil result
  end

  test "call returns the correct user association" do
    found_token = FindsApiToken.call(plain_token: @plain_token)

    assert_equal @user, found_token.user
  end

  test "call only returns active tokens" do
    # Verify token is initially active
    assert @api_token.active?

    found_token = FindsApiToken.call(plain_token: @plain_token)
    assert_not_nil found_token

    # Revoke the token
    RevokesApiToken.call(token: @api_token)

    # Should no longer be findable
    result = FindsApiToken.call(plain_token: @plain_token)
    assert_nil result
  end
end
