require "test_helper"

class RevokesApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    @api_token = GeneratesApiToken.call(user: @user)
  end

  test "call revokes the token" do
    assert @api_token.active?

    RevokesApiToken.call(token: @api_token)

    @api_token.reload
    assert @api_token.revoked?
  end

  test "call sets revoked_at timestamp" do
    assert_nil @api_token.revoked_at

    freeze_time do
      RevokesApiToken.call(token: @api_token)

      @api_token.reload
      assert_equal Time.current, @api_token.revoked_at
    end
  end

  test "call returns the token" do
    result = RevokesApiToken.call(token: @api_token)

    assert_equal @api_token, result
  end

  test "call persists changes to database" do
    RevokesApiToken.call(token: @api_token)

    token_from_db = ApiToken.find(@api_token.id)
    assert token_from_db.revoked?
  end

  test "call makes token unfindable by find_by_token" do
    plain_token = @api_token.plain_token

    # Token should be findable before revocation
    assert_not_nil ApiToken.find_by_token(plain_token)

    RevokesApiToken.call(token: @api_token)

    # Token should not be findable after revocation (find_by_token only returns active tokens)
    assert_nil ApiToken.find_by_token(plain_token)
  end

  test "call does not affect other tokens" do
    user2 = users(:two)
    other_token = GeneratesApiToken.call(user: user2)

    RevokesApiToken.call(token: @api_token)

    other_token.reload
    assert other_token.active?
  end
end
