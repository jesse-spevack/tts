require "test_helper"

class SendsWelcomeEmailTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:subscriber)
    @subscription = @user.subscription
  end

  test "sends email to user" do
    assert_enqueued_emails 1 do
      result = SendsWelcomeEmail.call(user: @user, subscription: @subscription)
      assert result.success?
    end
  end

  test "creates sent_message record" do
    assert_difference -> { @user.sent_messages.count }, 1 do
      SendsWelcomeEmail.call(user: @user, subscription: @subscription)
    end

    expected_type = "welcome_#{@subscription.stripe_subscription_id}"
    assert @user.sent_messages.exists?(message_type: expected_type)
  end

  test "does not send if already sent" do
    message_type = "welcome_#{@subscription.stripe_subscription_id}"
    @user.sent_messages.create!(message_type: message_type)

    assert_no_enqueued_emails do
      result = SendsWelcomeEmail.call(user: @user, subscription: @subscription)
      refute result.success?
      assert_match(/Already sent/, result.error)
    end
  end
end
