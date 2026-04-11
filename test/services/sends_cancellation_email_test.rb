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
    # Simulate the TOCTOU race that the DB's unique index guards against:
    # two threads pass `already_sent?` (both see no row), both fall through
    # to `create!`; the loser's INSERT trips the unique index and raises
    # ActiveRecord::RecordNotUnique. We reproduce this by:
    # 1. Prepending an override of `already_sent?` to bypass the in-Ruby guard.
    # 2. Temporarily removing SentMessage's Rails-level uniqueness validator
    #    (which would otherwise intercept with RecordInvalid before the DB
    #    level unique index fires).
    # 3. Pre-creating a row with the same (user_id, message_type) so the
    #    service's `create!` provokes the real DB-level RecordNotUnique.
    message_type = "cancellation_#{@subscription.stripe_subscription_id}"
    @user.sent_messages.create!(message_type: message_type)

    with_already_sent_stubbed_false(SendsCancellationEmail) do
      with_sent_message_uniqueness_disabled do
        result = SendsCancellationEmail.call(user: @user, subscription: @subscription, ends_at: @ends_at)
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
    # Remove the stub by reopening the prepended module to restore original
    # behavior (calls super → real method). Prepend ordering guarantees the
    # stub is called first; redefining to call super disables the stub without
    # needing to unprepend (which Ruby does not support).
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
