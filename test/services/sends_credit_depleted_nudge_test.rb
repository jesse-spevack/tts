# frozen_string_literal: true

require "test_helper"

class SendsCreditDepletedNudgeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "sends email when user has no credits" do
    user = users(:jesse)  # has empty_balance (0 credits)

    assert_enqueued_emails 1 do
      result = SendsCreditDepletedNudge.call(user: user)
      assert result.success?
    end
  end

  test "creates sent_message record" do
    user = users(:jesse)
    expected_type = "credit_depleted_#{Date.current.strftime('%Y_%m')}"

    assert_difference -> { user.sent_messages.count }, 1 do
      SendsCreditDepletedNudge.call(user: user)
    end

    assert user.sent_messages.exists?(message_type: expected_type)
  end

  test "does not send if user still has credits" do
    user = users(:credit_user)  # has 3 credits

    assert_no_enqueued_emails do
      result = SendsCreditDepletedNudge.call(user: user)
      refute result.success?
      assert_match(/still has credits/, result.error)
    end
  end

  test "does not send if already sent this month" do
    user = users(:jesse)
    message_type = "credit_depleted_#{Date.current.strftime('%Y_%m')}"
    user.sent_messages.create!(message_type: message_type)

    assert_no_enqueued_emails do
      result = SendsCreditDepletedNudge.call(user: user)
      refute result.success?
      assert_match(/Already sent/, result.error)
    end
  end
end
