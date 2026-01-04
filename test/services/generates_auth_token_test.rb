require "test_helper"

class GeneratesAuthTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "call generates new token" do
    token = GeneratesAuthToken.call(user: @user)

    @user.reload
    assert @user.auth_token.present?
    assert_match(/^\$2a\$/, @user.auth_token) # BCrypt hash format
    assert_match(/^[A-Za-z0-9_-]+$/, token) # Raw token format
  end

  test "call sets expiration to 30 minutes from now" do
    freeze_time do
      GeneratesAuthToken.call(user: @user)

      @user.reload
      expected_expiration = 30.minutes.from_now
      assert_equal expected_expiration, @user.auth_token_expires_at
    end
  end

  test "call replaces existing token" do
    @user.update!(auth_token: "old_token", auth_token_expires_at: 1.hour.from_now)

    GeneratesAuthToken.call(user: @user)

    @user.reload
    assert_not_equal "old_token", @user.auth_token
  end

  test "call generates unique tokens" do
    user2 = users(:two)

    GeneratesAuthToken.call(user: @user)
    GeneratesAuthToken.call(user: user2)

    @user.reload
    user2.reload

    assert_not_equal @user.auth_token, user2.auth_token
  end

  test "call persists token to database" do
    GeneratesAuthToken.call(user: @user)

    # Verify it's actually in the database, not just in memory
    user_from_db = User.find(@user.id)
    assert user_from_db.auth_token.present?
    assert user_from_db.auth_token_expires_at.present?
  end
end
