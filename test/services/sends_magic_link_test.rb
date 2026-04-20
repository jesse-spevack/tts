require "test_helper"

class SendsMagicLinkTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper
  test "call with new email creates user and sends email" do
    email = "newuser@example.com"

    assert_difference "User.count", 1 do
      assert_emails 1 do
        result = SendsMagicLink.call(email_address: email)

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
        result = SendsMagicLink.call(email_address: email)

        assert result.success?
        assert_equal user.id, result.data.id
      end
    end
  end

  test "call generates new token for existing user" do
    user = users(:one)
    GeneratesAuthToken.call(user: user)
    old_token = user.reload.auth_token

    result = SendsMagicLink.call(email_address: user.email_address)

    assert result.success?
    user.reload
    assert_not_equal old_token, user.auth_token
  end

  test "call normalizes email address" do
    result = SendsMagicLink.call(email_address: "  NewUser@EXAMPLE.com  ")

    assert result.success?
    assert_equal "newuser@example.com", result.data.email_address
  end

  test "call with invalid email returns failure" do
    result = SendsMagicLink.call(email_address: "not-an-email")

    assert_not result.success?
    assert_nil result.data
  end

  test "call with blank email returns failure" do
    result = SendsMagicLink.call(email_address: "")

    assert_not result.success?
    assert_nil result.data
  end

  test "call enqueues email with correct user" do
    email = "test@example.com"

    assert_enqueued_emails 1 do
      result = SendsMagicLink.call(email_address: email)
      assert result.success?
    end
  end

  test "call sets token expiration to 30 minutes from now" do
    result = SendsMagicLink.call(email_address: "test@example.com")

    user = result.data
    expected_expiration = 30.minutes.from_now

    assert_in_delta expected_expiration, user.auth_token_expires_at, 1.second
  end

  # --- pack_size carry through magic link (iny7) ---
  # iny7 extends the signature to accept pack_size alongside plan. The pack_size
  # must round-trip through the magic-link URL so post-login can resolve the
  # correct checkout pack. A nil / missing pack_size leaves existing flows
  # unchanged.

  test "call accepts pack_size kwarg without error" do
    # The signature contract — passing pack_size must not raise ArgumentError.
    result = SendsMagicLink.call(
      email_address: "test@example.com",
      plan: "credit_pack",
      pack_size: 10
    )

    assert result.success?
  end

  test "call with pack_size embeds pack_size in the magic link URL" do
    ActionMailer::Base.perform_deliveries = true

    SendsMagicLink.call(
      email_address: "test@example.com",
      plan: "credit_pack",
      pack_size: 20
    )

    # Force the enqueued mailer job to deliver so the body is inspectable.
    perform_enqueued_jobs

    mail = ActionMailer::Base.deliveries.last
    refute_nil mail, "Expected a magic-link email to have been delivered"
    assert_includes mail.body.to_s, "pack_size=20"
    assert_includes mail.body.to_s, "plan=credit_pack"
  end

  test "call without pack_size does not add pack_size to the magic link URL" do
    # Back-compat: plan-only or bare calls must not leak an empty pack_size.
    SendsMagicLink.call(email_address: "test@example.com", plan: "credit_pack")
    perform_enqueued_jobs

    mail = ActionMailer::Base.deliveries.last
    refute_match(/pack_size=/, mail.body.to_s,
      "An absent pack_size must not appear as a URL param")
  end

  test "call with neither plan nor pack_size still works" do
    # Smoke check for unchanged existing flows.
    assert_emails 1 do
      result = SendsMagicLink.call(email_address: "signup@example.com")
      assert result.success?
    end
  end
end
