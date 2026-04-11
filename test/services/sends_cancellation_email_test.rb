require "test_helper"

class SendsCancellationEmailTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:subscriber)
    @subscription = @user.subscription
    @ends_at = 1.month.from_now
  end

  test "sends email to user" do
    assert_enqueued_emails 1 do
      result = SendsCancellationEmail.call(user: @user, subscription: @subscription, ends_at: @ends_at)
      assert result.success?
    end
  end

  test "creates sent_message record" do
    assert_difference -> { @user.sent_messages.count }, 1 do
      SendsCancellationEmail.call(user: @user, subscription: @subscription, ends_at: @ends_at)
    end

    expected_type = "cancellation_#{@subscription.stripe_subscription_id}"
    assert @user.sent_messages.exists?(message_type: expected_type)
  end

  test "does not send if already sent" do
    message_type = "cancellation_#{@subscription.stripe_subscription_id}"
    @user.sent_messages.create!(message_type: message_type)

    assert_no_enqueued_emails do
      result = SendsCancellationEmail.call(user: @user, subscription: @subscription, ends_at: @ends_at)
      refute result.success?
      assert_match(/Already sent/, result.error)
    end
  end

  test "returns failure when create! raises RecordNotUnique from a race" do
    # Simulate a concurrent-webhook TOCTOU race: two threads pass `already_sent?`,
    # both reach `create!`, and the DB unique index raises on the loser. The stub
    # returns an object that lies about `exists?` (to bypass `already_sent?`) and
    # raises from `create!`. Scoped per-instance so no global state leaks.
    raising_collection = Object.new
    raising_collection.define_singleton_method(:exists?) { |**| false }
    raising_collection.define_singleton_method(:create!) { |**| raise ActiveRecord::RecordNotUnique.new("simulated race") }

    with_stubbed_sent_messages(@user, raising_collection) do
      result = SendsCancellationEmail.call(user: @user, subscription: @subscription, ends_at: @ends_at)
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
