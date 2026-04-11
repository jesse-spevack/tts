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
    message_type = "subscription_ended_#{@subscription.stripe_subscription_id}"
    @user.sent_messages.create!(message_type: message_type)

    with_already_sent_stubbed_false(SendsSubscriptionEndedEmail) do
      with_sent_message_uniqueness_disabled do
        result = SendsSubscriptionEndedEmail.call(user: @user, subscription: @subscription)
        refute result.success?, "Expected Result.failure when create! raises RecordNotUnique"
        assert_match(/Already sent/, result.error)
      end
    end
  end

  private

  def with_already_sent_stubbed_false(service_class)
    stub_module = Module.new do
      define_method(:already_sent?) { false }
    end
    service_class.prepend(stub_module)
    yield
  ensure
    stub_module.module_eval do
      remove_method(:already_sent?)
      define_method(:already_sent?) { super() }
    end
  end

  def with_sent_message_uniqueness_disabled
    SentMessage.clear_validators!
    SentMessage.validates :message_type, presence: true
    yield
  ensure
    SentMessage.clear_validators!
    SentMessage.validates :message_type, presence: true
    SentMessage.validates :message_type, uniqueness: { scope: :user_id }
  end
end
