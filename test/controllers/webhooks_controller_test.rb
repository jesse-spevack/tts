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
    payload = { id: "evt_unhandled_#{SecureRandom.hex(6)}", type: "customer.created", data: { object: {} } }.to_json
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

  test "returns 200 for RecordNotFound (non-retryable)" do
    payload = { id: "evt_missing_#{SecureRandom.hex(6)}", type: "checkout.session.completed", data: { object: { id: "cs_missing" } } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    Mocktail.replace(RoutesStripeWebhook)
    stubs { |m| RoutesStripeWebhook.call(event: m.any) }.with { raise ActiveRecord::RecordNotFound, "User not found" }

    post webhooks_stripe_path,
      params: payload,
      headers: {
        "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
        "CONTENT_TYPE" => "application/json"
      }

    assert_response :ok
  end

  test "returns 200 for RecordInvalid (non-retryable)" do
    payload = { id: "evt_invalid_#{SecureRandom.hex(6)}", type: "checkout.session.completed", data: { object: { id: "cs_invalid" } } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    Mocktail.replace(RoutesStripeWebhook)
    stubs { |m| RoutesStripeWebhook.call(event: m.any) }.with { raise ActiveRecord::RecordInvalid.new(User.new) }

    post webhooks_stripe_path,
      params: payload,
      headers: {
        "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
        "CONTENT_TYPE" => "application/json"
      }

    assert_response :ok
  end

  test "returns 500 for Stripe errors (retryable)" do
    payload = { id: "evt_stripe_err_#{SecureRandom.hex(6)}", type: "checkout.session.completed", data: { object: { id: "cs_stripe_err" } } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    Mocktail.replace(RoutesStripeWebhook)
    stubs { |m| RoutesStripeWebhook.call(event: m.any) }.with { raise Stripe::APIConnectionError, "Connection failed" }

    post webhooks_stripe_path,
      params: payload,
      headers: {
        "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
        "CONTENT_TYPE" => "application/json"
      }

    assert_response :internal_server_error
  end

  test "returns 500 for unexpected errors (retryable)" do
    payload = { id: "evt_unexpected_#{SecureRandom.hex(6)}", type: "checkout.session.completed", data: { object: { id: "cs_unexpected" } } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    Mocktail.replace(RoutesStripeWebhook)
    stubs { |m| RoutesStripeWebhook.call(event: m.any) }.with { raise RuntimeError, "Something unexpected" }

    post webhooks_stripe_path,
      params: payload,
      headers: {
        "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
        "CONTENT_TYPE" => "application/json"
      }

    assert_response :internal_server_error
  end

  # Idempotency (agent-team-qy30): duplicate Stripe deliveries must not re-run
  # handlers. Stripe retries on 5xx and under pause/resume and can deliver the
  # same event.id more than once. Without deduping on event.id, the second
  # delivery re-runs GrantsCreditFromCheckout/SyncsSubscription side effects
  # (welcome emails, subscription reprocessing, etc.) even though the
  # CreditTransaction uniqueness validation prevents a duplicate credit row.
  test "duplicate checkout.session.completed for credit pack invokes GrantsCreditFromCheckout exactly once (agent-team-qy30)" do
    event_id = "evt_dup_credit_#{SecureRandom.hex(6)}"
    payload = {
      id: event_id,
      type: "checkout.session.completed",
      data: { object: { id: "cs_test_dup_credit", subscription: nil } }
    }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)
    headers = {
      "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
      "CONTENT_TYPE" => "application/json"
    }

    Mocktail.replace(GrantsCreditFromCheckout)
    stubs { |m| GrantsCreditFromCheckout.call(session: m.any) }.with { Result.success }

    post webhooks_stripe_path, params: payload, headers: headers
    assert_response :ok

    post webhooks_stripe_path, params: payload, headers: headers
    assert_response :ok

    verify(times: 1) { |m| GrantsCreditFromCheckout.call(session: m.any) }
  end

  test "duplicate checkout.session.completed invokes GrantsCreditFromCheckout exactly once (agent-team-qy30)" do
    event_id = "evt_dup_chk_#{SecureRandom.hex(6)}"
    payload = {
      id: event_id,
      type: "checkout.session.completed",
      data: { object: { id: "cs_dup_chk" } }
    }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)
    headers = {
      "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
      "CONTENT_TYPE" => "application/json"
    }

    Mocktail.replace(GrantsCreditFromCheckout)
    stubs { |m| GrantsCreditFromCheckout.call(session: m.any) }.with { Result.success }

    post webhooks_stripe_path, params: payload, headers: headers
    assert_response :ok

    post webhooks_stripe_path, params: payload, headers: headers
    assert_response :ok

    verify(times: 1) { |m| GrantsCreditFromCheckout.call(session: m.any) }
  end

  test "first-time Stripe delivery persists a WebhookEvent row and runs the handler once (agent-team-qy30)" do
    event_id = "evt_first_#{SecureRandom.hex(6)}"
    payload = {
      id: event_id,
      type: "checkout.session.completed",
      data: { object: { id: "cs_first" } }
    }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)
    headers = {
      "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
      "CONTENT_TYPE" => "application/json"
    }

    Mocktail.replace(GrantsCreditFromCheckout)
    stubs { |m| GrantsCreditFromCheckout.call(session: m.any) }.with { Result.success }

    post webhooks_stripe_path, params: payload, headers: headers

    assert_response :ok
    verify(times: 1) { |m| GrantsCreditFromCheckout.call(session: m.any) }
    assert_equal 1, WebhookEvent.where(provider: "stripe", event_id: event_id).count
  end

  test "returns 400 when Stripe payload is missing event.id (agent-team-qy30)" do
    # Fail-closed guard: without an event.id we cannot dedupe. Silently
    # swallowing (200) would allow Stripe to stop retrying while we
    # effectively dropped the event. Return 400 with an error log so Stripe
    # marks the delivery as failed and the operator sees the breakage.
    payload = { type: "checkout.session.completed", data: { object: { id: "cs_no_id" } } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    log_output = capture_logs do
      post webhooks_stripe_path,
        params: payload,
        headers: {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
          "CONTENT_TYPE" => "application/json"
        }
    end

    assert_response :bad_request
    assert_match(/webhook_event_missing_event_id/, log_output)
    assert_equal 0, WebhookEvent.where(provider: "stripe").count
  end

  test "logs 'Unknown credit pack price id' when checkout carries a non-pack price_id (agent-team-sz2e)" do
    # Regression guard: GrantsCreditFromCheckout returns Result.failure with
    # error="Unknown credit pack price id" when a subscription price_id
    # lands on the checkout.session.completed path. WebhooksController logs
    # that error string; a silent log-message refactor would hide the
    # user-visible pain (charged but no credits granted).
    payload = { id: "evt_unknown_price_#{SecureRandom.hex(6)}", type: "checkout.session.completed", data: { object: { id: "cs_unknown_price" } } }.to_json
    timestamp = Time.now.to_i
    signature = generate_stripe_signature(payload, timestamp)

    Mocktail.replace(RoutesStripeWebhook)
    stubs { |m| RoutesStripeWebhook.call(event: m.any) }.with { Result.failure("Unknown credit pack price id") }

    log_output = capture_logs do
      post webhooks_stripe_path,
        params: payload,
        headers: {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
          "CONTENT_TYPE" => "application/json"
        }
    end

    assert_response :ok
    assert_match(/Unknown credit pack price id/, log_output)
  end

  private

  def generate_stripe_signature(payload, timestamp)
    secret = AppConfig::Stripe::WEBHOOK_SECRET
    signed_payload = "#{timestamp}.#{payload}"
    OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
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
