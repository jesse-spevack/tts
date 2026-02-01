# frozen_string_literal: true

require "test_helper"

class ProcessedWebhookEmailTest < ActiveSupport::TestCase
  test "process_if_new returns true for new email" do
    result = ProcessedWebhookEmail.process_if_new(
      email_id: "email_#{SecureRandom.hex(8)}",
      source: "resend"
    )

    assert result
  end

  test "process_if_new returns false for duplicate email" do
    email_id = "email_#{SecureRandom.hex(8)}"

    first_result = ProcessedWebhookEmail.process_if_new(
      email_id: email_id,
      source: "resend"
    )
    second_result = ProcessedWebhookEmail.process_if_new(
      email_id: email_id,
      source: "resend"
    )

    assert first_result
    assert_not second_result
  end

  test "process_if_new allows same email_id from different sources" do
    email_id = "email_#{SecureRandom.hex(8)}"

    first_result = ProcessedWebhookEmail.process_if_new(
      email_id: email_id,
      source: "resend"
    )
    second_result = ProcessedWebhookEmail.process_if_new(
      email_id: email_id,
      source: "other_provider"
    )

    assert first_result
    assert second_result
  end

  test "validates presence of email_id" do
    record = ProcessedWebhookEmail.new(source: "resend", processed_at: Time.current)
    assert_not record.valid?
    assert_includes record.errors[:email_id], "can't be blank"
  end

  test "validates presence of source" do
    record = ProcessedWebhookEmail.new(email_id: "test", processed_at: Time.current)
    assert_not record.valid?
    assert_includes record.errors[:source], "can't be blank"
  end

  test "validates presence of processed_at" do
    record = ProcessedWebhookEmail.new(email_id: "test", source: "resend")
    assert_not record.valid?
    assert_includes record.errors[:processed_at], "can't be blank"
  end
end
