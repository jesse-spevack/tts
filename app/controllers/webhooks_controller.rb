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
  rescue ActiveRecord::RecordNotFound => e
    # Most common cause: the user/subscription was soft-deleted or never
    # existed. We return 200 so Stripe stops retrying — but we must log
    # enough context to reconcile manually if a charge leaked through.
    stripe_customer_id = event&.data&.object&.respond_to?(:customer) ? event.data.object.customer : nil
    Rails.logger.warn(
      "event=stripe_webhook_record_not_found " \
      "event_type=#{event&.type || 'unknown'} " \
      "stripe_customer_id=#{stripe_customer_id || 'unknown'} " \
      "reason=user_soft_deleted_or_missing " \
      "error=#{e.message}"
    )
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
