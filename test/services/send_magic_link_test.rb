require "test_helper"

class SendMagicLinkTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  test "call with new email creates user and sends email" do
    email = "newuser@example.com"

    assert_difference "User.count", 1 do
      assert_emails 1 do
        result = SendMagicLink.call(email_address: email)

        assert result.success?
        assert_equal email, result.data.email_address
        assert result.data.auth_token.present?
        assert result.data.auth_token_expires_at.present?
      end
    end
  end

  test "call with existing user does not create duplicate" do
    user = users(:one)
    email = user.email_address

    assert_no_difference "User.count" do
      assert_emails 1 do
        result = SendMagicLink.call(email_address: email)

        assert result.success?
        assert_equal user.id, result.data.id
      end
    end
  end

  test "call generates new token for existing user" do
    user = users(:one)
    GenerateAuthToken.call(user: user)
    old_token = user.reload.auth_token

    result = SendMagicLink.call(email_address: user.email_address)

    assert result.success?
    user.reload
    assert_not_equal old_token, user.auth_token
  end

  test "call normalizes email address" do
    result = SendMagicLink.call(email_address: "  NewUser@EXAMPLE.com  ")

    assert result.success?
    assert_equal "newuser@example.com", result.data.email_address
  end

  test "call with invalid email returns failure" do
    result = SendMagicLink.call(email_address: "not-an-email")

    assert_not result.success?
    assert_nil result.data
  end

  test "call with blank email returns failure" do
    result = SendMagicLink.call(email_address: "")

    assert_not result.success?
    assert_nil result.data
  end

  test "call enqueues email with correct user" do
    email = "test@example.com"

    assert_enqueued_emails 1 do
      result = SendMagicLink.call(email_address: email)
      assert result.success?
    end
  end

  test "call sets token expiration to 30 minutes from now" do
    result = SendMagicLink.call(email_address: "test@example.com")

    user = result.data
    expected_expiration = 30.minutes.from_now

    assert_in_delta expected_expiration, user.auth_token_expires_at, 1.second
  end
end
