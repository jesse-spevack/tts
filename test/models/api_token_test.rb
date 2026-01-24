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

  # Token Generation Tests
  test "generate_for creates a token with correct prefix format" do
    user = users(:two)
    # Clear existing tokens for this user
    user.api_tokens.destroy_all

    token = ApiToken.generate_for(user)

    assert token.persisted?
    assert token.plain_token.start_with?("tts_ext_")
    assert_equal "tts_ext_", token.token_prefix
  end

  test "generate_for returns plain_token which is not stored in database" do
    user = users(:two)
    user.api_tokens.destroy_all

    token = ApiToken.generate_for(user)
    plain_token = token.plain_token

    assert_not_nil plain_token

    # Verify plain_token is not a database column by fetching a fresh instance
    fresh_token = ApiToken.find(token.id)
    assert_nil fresh_token.plain_token

    # Verify the plain_token is not the same as token_digest
    assert_not_equal plain_token, token.token_digest
  end

  test "generate_for stores hashed token_digest" do
    user = users(:two)
    user.api_tokens.destroy_all

    token = ApiToken.generate_for(user)
    plain_token = token.plain_token

    # Verify the digest is a SHA256 hash of the plain token
    expected_digest = Digest::SHA256.hexdigest(plain_token)
    assert_equal expected_digest, token.token_digest
  end

  test "generate_for revokes existing active tokens for user" do
    user = users(:one)
    existing_active_token = api_tokens(:active_token)

    assert existing_active_token.active?

    ApiToken.generate_for(user)

    existing_active_token.reload
    assert existing_active_token.revoked?
  end

  test "generate_for does not affect already revoked tokens" do
    user = users(:one)
    revoked_token = api_tokens(:revoked_token)
    original_revoked_at = revoked_token.revoked_at

    ApiToken.generate_for(user)

    revoked_token.reload
    # The revoked_at time should not have changed
    assert_equal original_revoked_at.to_i, revoked_token.revoked_at.to_i
  end

  # Token Validation Tests
  test "find_by_token returns token for valid plain token" do
    user = users(:two)
    user.api_tokens.destroy_all

    token = ApiToken.generate_for(user)
    plain_token = token.plain_token

    found_token = ApiToken.find_by_token(plain_token)

    assert_equal token, found_token
  end

  test "find_by_token returns nil for invalid token" do
    result = ApiToken.find_by_token("tts_ext_invalid_token_12345")

    assert_nil result
  end

  test "find_by_token returns nil for revoked token" do
    user = users(:two)
    user.api_tokens.destroy_all

    token = ApiToken.generate_for(user)
    plain_token = token.plain_token
    token.revoke!

    result = ApiToken.find_by_token(plain_token)

    assert_nil result
  end

  test "find_by_token returns nil for blank token" do
    assert_nil ApiToken.find_by_token(nil)
    assert_nil ApiToken.find_by_token("")
  end

  # Token Revocation Tests
  test "revoke! sets revoked_at timestamp" do
    token = api_tokens(:active_token)

    assert_nil token.revoked_at

    freeze_time do
      token.revoke!

      assert_equal Time.current, token.revoked_at
    end
  end

  test "revoke! does not delete the record" do
    token = api_tokens(:active_token)
    token_id = token.id

    token.revoke!

    assert ApiToken.exists?(token_id)
  end

  test "revoked? returns true for revoked tokens" do
    token = api_tokens(:revoked_token)

    assert token.revoked?
  end

  test "revoked? returns false for active tokens" do
    token = api_tokens(:active_token)

    refute token.revoked?
  end

  test "active? returns true for non-revoked tokens" do
    token = api_tokens(:active_token)

    assert token.active?
  end

  test "active? returns false for revoked tokens" do
    token = api_tokens(:revoked_token)

    refute token.active?
  end

  # Active Scope Tests
  test "active scope returns only non-revoked tokens" do
    active_tokens = ApiToken.active

    assert_includes active_tokens, api_tokens(:active_token)
    assert_includes active_tokens, api_tokens(:recently_used_token)
    refute_includes active_tokens, api_tokens(:revoked_token)
  end

  # Active Token For User Tests
  test "active_token_for returns active token for user" do
    user = users(:one)

    token = ApiToken.active_token_for(user)

    assert_equal api_tokens(:active_token), token
  end

  test "active_token_for returns nil when user has no active tokens" do
    user = users(:one)
    user.api_tokens.active.each(&:revoke!)

    token = ApiToken.active_token_for(user)

    assert_nil token
  end

  # One Active Token Per User Tests
  test "user can only have one active token at a time" do
    user = users(:two)
    user.api_tokens.destroy_all

    first_token = ApiToken.generate_for(user)
    assert first_token.active?

    second_token = ApiToken.generate_for(user)

    first_token.reload
    assert first_token.revoked?
    assert second_token.active?
    assert_equal 1, user.api_tokens.active.count
  end
end
