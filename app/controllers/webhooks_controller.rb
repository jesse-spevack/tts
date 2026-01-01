class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :stripe
  allow_unauthenticated_access only: :stripe

  def stripe
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, signature, AppConfig::Stripe::WEBHOOK_SECRET
    )

    RoutesStripeWebhook.call(event: event)
    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  end
end
