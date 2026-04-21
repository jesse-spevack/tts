# frozen_string_literal: true

# Dedup layer for inbound webhooks. Inserts a WebhookEvent row keyed on
# (provider, event_id). Used by WebhooksController (Stripe) and
# Webhooks::ResendController.
#
# Outcomes:
# - success with data = WebhookEvent    → first-time delivery; caller proceeds
# - success with data = nil             → duplicate; caller returns 200 and stops
# - failure("Missing event_id")         → caller returns 400; we cannot dedupe
class CreatesWebhookEvent
  include StructuredLogging

  def self.call(provider:, event_id:, event_type:)
    new(provider:, event_id:, event_type:).call
  end

  def initialize(provider:, event_id:, event_type:)
    @provider = provider
    @event_id = event_id
    @event_type = event_type
  end

  def call
    if event_id.blank?
      log_error "webhook_event_missing_event_id", provider: provider, event_type: event_type
      return Result.failure("Missing event_id")
    end

    webhook_event = WebhookEvent.create!(
      provider: provider,
      event_id: event_id,
      event_type: event_type,
      received_at: Time.current
    )

    Result.success(webhook_event)
  rescue ActiveRecord::RecordNotUnique
    log_duplicate
    Result.success
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record&.errors&.of_kind?(:event_id, :taken)

    log_duplicate
    Result.success
  end

  private

  attr_reader :provider, :event_id, :event_type

  def log_duplicate
    log_info "webhook_event_duplicate_ignored",
      provider: provider,
      event_id: event_id,
      event_type: event_type
  end
end
