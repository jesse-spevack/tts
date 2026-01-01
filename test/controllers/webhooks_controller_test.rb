require "test_helper"
require "ostruct"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    Stripe.api_key = "sk_test_fake"
  end

  test "returns 400 when signature verification fails" do
    # WebMock will let the request through to Stripe which will fail signature verification
    # But we can't easily mock Stripe::Webhook.construct_event
    # Instead, we'll test with an invalid signature and expect 400

    # The controller catches SignatureVerificationError and returns 400
    # We need to trigger this - the simplest way is to just send a request
    # with no valid signature when Stripe tries to verify

    post webhooks_stripe_path,
      params: "{}",
      headers: { "Stripe-Signature" => "invalid", "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
  end

  test "returns 200 for valid webhook with unhandled event type" do
    # For a properly signed webhook, we need to generate a valid signature
    # This is complex, so instead we'll test the controller exists and routes work
    # The RoutesStripeWebhook service is already tested

    # Create a valid test signature
    payload = { type: "customer.created", data: { object: {} } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    post webhooks_stripe_path,
      params: payload,
      headers: {
        "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
        "CONTENT_TYPE" => "application/json"
      }

    assert_response :success
  end

  private

  def generate_stripe_signature(payload, timestamp)
    secret = AppConfig::Stripe::WEBHOOK_SECRET
    signed_payload = "#{timestamp}.#{payload}"
    OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
  end
end
