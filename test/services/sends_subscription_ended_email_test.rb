require "test_helper"

class SendsSubscriptionEndedEmailTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:subscriber)
    @subscription = @user.subscription
  end

  test "sends email to user" do
    assert_enqueued_emails 1 do
      result = SendsSubscriptionEndedEmail.call(user: @user, subscription: @subscription)
      assert result.success?
    end
  end

  test "creates sent_message record" do
    assert_difference -> { @user.sent_messages.count }, 1 do
      SendsSubscriptionEndedEmail.call(user: @user, subscription: @subscription)
    end

    expected_type = "subscription_ended_#{@subscription.stripe_subscription_id}"
    assert @user.sent_messages.exists?(message_type: expected_type)
  end

  test "does not send if already sent" do
    message_type = "subscription_ended_#{@subscription.stripe_subscription_id}"
    @user.sent_messages.create!(message_type: message_type)

    assert_no_enqueued_emails do
      result = SendsSubscriptionEndedEmail.call(user: @user, subscription: @subscription)
      refute result.success?
      assert_match(/Already sent/, result.error)
    end
  end

  test "returns failure when create! raises RecordNotUnique from a race" do
    # See SendsCancellationEmailTest for the rationale on this pattern.
    raising_collection = Object.new
    raising_collection.define_singleton_method(:exists?) { |**| false }
    raising_collection.define_singleton_method(:create!) { |**| raise ActiveRecord::RecordNotUnique.new("simulated race") }

    with_stubbed_sent_messages(@user, raising_collection) do
      result = SendsSubscriptionEndedEmail.call(user: @user, subscription: @subscription)
      refute result.success?, "Expected Result.failure when create! raises RecordNotUnique"
      assert_match(/Already sent/, result.error)
    end
  end

  private

  def with_stubbed_sent_messages(user, replacement)
    user.define_singleton_method(:sent_messages) { replacement }
    yield
  ensure
    user.singleton_class.remove_method(:sent_messages)
  end
end
