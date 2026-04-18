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
    assert api_token.plain_token.start_with?("sk_live_")
  end

  test "call creates token associated with user" do
    api_token = GeneratesApiToken.call(user: @user)

    assert_equal @user, api_token.user
  end

  test "call allows multiple active tokens per user" do
    first_token = GeneratesApiToken.call(user: @user)
    second_token = GeneratesApiToken.call(user: @user)

    first_token.reload
    assert first_token.active?
    assert second_token.active?
  end

  test "call defaults source to user" do
    token = GeneratesApiToken.call(user: @user)
    assert_equal "user", token.source
  end

  test "call accepts explicit source" do
    token = GeneratesApiToken.call(user: @user, source: "extension")
    assert_equal "extension", token.source
  end

  test "call populates token_prefix with prefix + 4 chars of random portion" do
    token = GeneratesApiToken.call(user: @user)

    assert token.token_prefix.start_with?("sk_live_")
    # 8 chars of "sk_live_" + 4 chars from the random portion = 12 chars total
    assert_equal 12, token.token_prefix.length
    assert token.plain_token.start_with?(token.token_prefix)
  end

  test "call generates unique tokens each time" do
    token1 = GeneratesApiToken.call(user: @user)
    token2 = GeneratesApiToken.call(user: @user)

    assert_not_equal token1.plain_token, token2.plain_token
  end

  test "call generates tokens that can be found by FindsApiToken" do
    api_token = GeneratesApiToken.call(user: @user)
    plain_token = api_token.plain_token

    found_token = FindsApiToken.call(plain_token: plain_token)
    assert_not_nil found_token
    assert_equal api_token.id, found_token.id
  end

  test "call emits structured log with event, user_id, source, and token_prefix" do
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      token = GeneratesApiToken.call(user: @user, source: "extension")
    ensure
      Rails.logger = original_logger
    end

    logs = output.string
    assert_match(/event=api_token_generated/, logs)
    assert_match(/user_id=#{@user.id}/, logs)
    assert_match(/source=extension/, logs)
    assert_match(/token_prefix=#{Regexp.escape(token.token_prefix)}/, logs)
    refute_match(/token_digest/, logs, "token_digest must never appear in logs")
    refute_match(Regexp.new(Regexp.escape(token.plain_token)), logs, "plain token must never appear in logs")
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
