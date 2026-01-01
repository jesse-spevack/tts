require "test_helper"

class SendsUpgradeNudgeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @free_user = users(:free_user)
  end

  test "sends email to free user" do
    assert_enqueued_emails 1 do
      result = SendsUpgradeNudge.call(user: @free_user)
      assert result.success?
    end
  end

  test "creates sent_message record" do
    expected_type = "upgrade_nudge_#{Date.current.strftime('%Y_%m')}"

    assert_difference -> { @free_user.sent_messages.count }, 1 do
      SendsUpgradeNudge.call(user: @free_user)
    end

    assert @free_user.sent_messages.exists?(message_type: expected_type)
  end

  test "does not send if already sent this month" do
    message_type = "upgrade_nudge_#{Date.current.strftime('%Y_%m')}"
    @free_user.sent_messages.create!(message_type: message_type)

    assert_no_enqueued_emails do
      result = SendsUpgradeNudge.call(user: @free_user)
      refute result.success?
      assert_match(/Already sent/, result.error)
    end
  end

  test "does not send to premium user" do
    premium_user = users(:subscriber)

    assert_no_enqueued_emails do
      result = SendsUpgradeNudge.call(user: premium_user)
      refute result.success?
      assert_match(/Not a free user/, result.error)
    end
  end
end
