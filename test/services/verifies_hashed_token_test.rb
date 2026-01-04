require "test_helper"

class VerifiesHashedTokenTest < ActiveSupport::TestCase
  test "call returns true when raw token matches hashed token" do
    raw_token = "secret_token_123"
    hashed_token = BCrypt::Password.create(raw_token)

    result = VerifiesHashedToken.call(hashed_token: hashed_token, raw_token: raw_token)

    assert result
  end

  test "call returns false when raw token does not match hashed token" do
    raw_token = "secret_token_123"
    wrong_token = "wrong_token_456"
    hashed_token = BCrypt::Password.create(raw_token)

    result = VerifiesHashedToken.call(hashed_token: hashed_token, raw_token: wrong_token)

    assert_not result
  end

  test "call returns false when hashed token is nil" do
    result = VerifiesHashedToken.call(hashed_token: nil, raw_token: "some_token")

    assert_not result
  end

  test "call returns false when raw token is nil" do
    hashed_token = BCrypt::Password.create("some_token")

    result = VerifiesHashedToken.call(hashed_token: hashed_token, raw_token: nil)

    assert_not result
  end

  test "call returns false when hashed token is invalid" do
    invalid_hash = "not_a_valid_bcrypt_hash"

    result = VerifiesHashedToken.call(hashed_token: invalid_hash, raw_token: "some_token")

    assert_not result
  end
end
