# frozen_string_literal: true

require "test_helper"

class CreatesWebhookEventTest < ActiveSupport::TestCase
  test "creates a WebhookEvent row and returns success with the record on first delivery" do
    result = nil

    assert_difference "WebhookEvent.count", 1 do
      result = CreatesWebhookEvent.call(
        provider: "stripe",
        event_id: "evt_first_#{SecureRandom.hex(6)}",
        event_type: "customer.subscription.updated"
      )
    end

    assert result.success?
    assert_kind_of WebhookEvent, result.data
    assert_equal "stripe", result.data.provider
    assert_equal "customer.subscription.updated", result.data.event_type
    assert_not_nil result.data.received_at
  end

  test "returns success with nil data and does not insert a second row when event is already seen" do
    event_id = "evt_dup_#{SecureRandom.hex(6)}"
    WebhookEvent.create!(
      provider: "stripe",
      event_id: event_id,
      event_type: "customer.subscription.updated",
      received_at: Time.current
    )

    result = nil
    log_output = capture_logs do
      assert_no_difference "WebhookEvent.count" do
        result = CreatesWebhookEvent.call(
          provider: "stripe",
          event_id: event_id,
          event_type: "customer.subscription.updated"
        )
      end
    end

    assert result.success?
    assert_nil result.data
    assert_match(/webhook_event_duplicate_ignored/, log_output)
  end

  test "returns failure without creating a row when event_id is blank" do
    result = nil

    log_output = capture_logs do
      assert_no_difference "WebhookEvent.count" do
        result = CreatesWebhookEvent.call(
          provider: "stripe",
          event_id: "",
          event_type: "customer.subscription.updated"
        )
      end
    end

    refute result.success?
    assert_equal "Missing event_id", result.error
    assert_match(/webhook_event_missing_event_id/, log_output)
  end

  test "handles RecordNotUnique from a DB race as a duplicate" do
    result = with_create_bang_raising(ActiveRecord::RecordNotUnique.new("duplicate key")) do
      CreatesWebhookEvent.call(
        provider: "resend",
        event_id: "msg_race",
        event_type: "email.received"
      )
    end

    assert result.success?
    assert_nil result.data
  end

  test "re-raises RecordInvalid for non-uniqueness validation errors" do
    invalid_record = WebhookEvent.new
    invalid_record.errors.add(:provider, :invalid, message: "is not recognized")

    with_create_bang_raising(ActiveRecord::RecordInvalid.new(invalid_record)) do
      assert_raises(ActiveRecord::RecordInvalid) do
        CreatesWebhookEvent.call(
          provider: "bogus",
          event_id: "evt_123",
          event_type: "something"
        )
      end
    end
  end

  private

  # Overrides WebhookEvent.create! to raise the given exception for the
  # duration of the block, then restores the original method. Used to
  # simulate DB-level race conditions the app validation wouldn't catch.
  def with_create_bang_raising(exception)
    singleton = WebhookEvent.singleton_class
    original = WebhookEvent.method(:create!)
    singleton.send(:define_method, :create!) { |**_kwargs| raise exception }
    yield
  ensure
    singleton.send(:define_method, :create!, original)
  end

  def capture_logs
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end
