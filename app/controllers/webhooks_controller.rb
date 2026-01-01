class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :stripe
  allow_unauthenticated_access only: :stripe

  def stripe
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, signature, AppConfig::Stripe::WEBHOOK_SECRET
    )

    result = RoutesStripeWebhook.call(event: event)

    if result&.failure?
      Rails.logger.error("[Stripe Webhook] Failed to process #{event.type}: #{result.error}")
    end

    head :ok
  rescue Stripe::SignatureVerificationError => e
    Rails.logger.warn("[Stripe Webhook] Invalid signature: #{e.message}")
    head :bad_request
  rescue StandardError => e
    Rails.logger.error("[Stripe Webhook] Unexpected error: #{e.class} - #{e.message}")
    raise
  end
end
