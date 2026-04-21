class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :stripe
  allow_unauthenticated_access only: :stripe

  def stripe
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, signature, AppConfig::Stripe::WEBHOOK_SECRET
    )

    begin
      WebhookEvent.create!(
        provider: "stripe",
        event_id: event.id,
        event_type: event.type,
        received_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info("[Stripe Webhook] Duplicate delivery ignored: event_id=#{event.id} type=#{event.type}")
      return head :ok
    rescue ActiveRecord::RecordInvalid => e
      if e.record&.errors&.of_kind?(:event_id, :taken)
        Rails.logger.info("[Stripe Webhook] Duplicate delivery ignored: event_id=#{event.id} type=#{event.type}")
        return head :ok
      end
      raise
    end

    result = RoutesStripeWebhook.call(event: event)

    if result&.failure?
      Rails.logger.error("[Stripe Webhook] Failed to process #{event.type}: #{result.error}")
    end

    head :ok
  rescue Stripe::SignatureVerificationError => e
    Rails.logger.warn("[Stripe Webhook] Invalid signature: #{e.message}")
    head :bad_request
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error("[Stripe Webhook] Record not found: #{e.message}")
    head :ok
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[Stripe Webhook] Validation failed: #{e.message}")
    head :ok
  rescue Stripe::StripeError => e
    Rails.logger.error("[Stripe Webhook] Stripe API error: #{e.message}")
    head :internal_server_error
  rescue StandardError => e
    Rails.logger.error("[Stripe Webhook] Unexpected error: #{e.class} - #{e.message}")
    head :internal_server_error
  end
end
