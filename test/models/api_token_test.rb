require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "belongs to user" do
    token = api_tokens(:active_token)
    assert_equal users(:one), token.user
  end

  test "requires user" do
    token = ApiToken.new(token_digest: "test_digest", token_prefix: "tts_ext_x")
    refute token.valid?
    assert_includes token.errors[:user], "must exist"
  end

  test "requires token_digest" do
    token = ApiToken.new(user: users(:one), token_prefix: "tts_ext_x")
    refute token.valid?
    assert_includes token.errors[:token_digest], "can't be blank"
  end

  test "requires token_prefix" do
    token = ApiToken.new(user: users(:one), token_digest: "test_digest")
    refute token.valid?
    assert_includes token.errors[:token_prefix], "can't be blank"
  end

  test "enforces uniqueness of token_digest" do
    existing = api_tokens(:active_token)
    duplicate = ApiToken.new(
      user: users(:two),
      token_digest: existing.token_digest,
      token_prefix: "tts_ext_d"
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:token_digest], "has already been taken"
  end

  test "allows last_used_at to be nil" do
    token = api_tokens(:active_token)
    assert_nil token.last_used_at
    assert token.valid?
  end

  test "allows revoked_at to be nil" do
    token = api_tokens(:active_token)
    assert_nil token.revoked_at
    assert token.valid?
  end

  test "user has many api_tokens" do
    user = users(:one)
    assert_includes user.api_tokens, api_tokens(:active_token)
    assert_includes user.api_tokens, api_tokens(:revoked_token)
  end
end
