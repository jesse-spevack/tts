# frozen_string_literal: true

require "test_helper"

module Webhooks
  class ResendControllerTest < ActionDispatch::IntegrationTest
    WEBHOOK_SECRET = "whsec_test_secret_key_for_testing"

    setup do
      @user = users(:one)
      @user.update!(email_episodes_enabled: true, email_ingest_token: "test_token_123")
      ENV["RESEND_API_KEY"] = "test_api_key"
      ENV["RESEND_WEBHOOK_SECRET"] = WEBHOOK_SECRET
    end

    teardown do
      ENV.delete("RESEND_API_KEY")
      ENV.delete("RESEND_WEBHOOK_SECRET")
    end

    test "processes email.received webhook with valid signature" do
      email_data = {
        "from" => "sender@example.com",
        "to" => [ "readtome+test_token_123@example.com" ],
        "subject" => "Test Article",
        "html" => "<p>This is the article content.</p>",
        "text" => "This is the article content.",
        "message_id" => "<test123@example.com>"
      }

      stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
        .to_return(status: 200, body: email_data.to_json, headers: { "Content-Type" => "application/json" })

      payload = {
        type: "email.received",
        data: {
          email_id: "email_abc123",
          from: "sender@example.com",
          to: [ "readtome+test_token_123@example.com" ],
          subject: "Test Article"
        }
      }.to_json

      assert_difference "ActionMailbox::InboundEmail.count", 1 do
        post_with_signature(payload)
        assert_response :ok
      end
    end

    test "returns unauthorized for missing signature" do
      payload = { type: "email.received", data: { email_id: "email_abc123" } }.to_json

      post webhooks_resend_inbound_url,
        params: payload,
        headers: { "Content-Type" => "application/json" }

      assert_response :unauthorized
    end

    test "returns unauthorized for invalid signature" do
      payload = { type: "email.received", data: { email_id: "email_abc123" } }.to_json

      post webhooks_resend_inbound_url,
        params: payload,
        headers: {
          "Content-Type" => "application/json",
          "svix-id" => "msg_123",
          "svix-timestamp" => Time.now.to_i.to_s,
          "svix-signature" => "v1,invalid_signature"
        }

      assert_response :unauthorized
    end

    test "returns unauthorized for expired timestamp" do
      payload = { type: "email.received", data: { email_id: "email_abc123" } }.to_json
      old_timestamp = (Time.now.to_i - 600).to_s # 10 minutes ago

      svix_id = "msg_#{SecureRandom.hex(8)}"
      signature = generate_svix_signature(svix_id, old_timestamp, payload)

      post webhooks_resend_inbound_url,
        params: payload,
        headers: {
          "Content-Type" => "application/json",
          "svix-id" => svix_id,
          "svix-timestamp" => old_timestamp,
          "svix-signature" => "v1,#{signature}"
        }

      assert_response :unauthorized
    end

    test "ignores non-email.received events" do
      payload = { type: "email.sent", data: { email_id: "email_abc123" } }.to_json

      assert_no_difference "ActionMailbox::InboundEmail.count" do
        post_with_signature(payload)
      end

      assert_response :ok
    end

    test "returns bad_request for missing email_id" do
      payload = { type: "email.received", data: {} }.to_json

      post_with_signature(payload)

      assert_response :bad_request
    end

    test "returns bad_request for invalid JSON" do
      post webhooks_resend_inbound_url,
        params: "not valid json",
        headers: svix_headers("not valid json").merge("Content-Type" => "application/json")

      assert_response :bad_request
    end

    test "returns unprocessable_entity when Resend API fails" do
      stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
        .to_return(status: 404, body: { error: "Not found" }.to_json)

      payload = { type: "email.received", data: { email_id: "email_abc123" } }.to_json

      post_with_signature(payload)

      assert_response :unprocessable_entity
    end

    private

    def post_with_signature(payload)
      post webhooks_resend_inbound_url,
        params: payload,
        headers: svix_headers(payload).merge("Content-Type" => "application/json")
    end

    def svix_headers(payload)
      svix_id = "msg_#{SecureRandom.hex(8)}"
      svix_timestamp = Time.now.to_i.to_s
      signature = generate_svix_signature(svix_id, svix_timestamp, payload)

      {
        "svix-id" => svix_id,
        "svix-timestamp" => svix_timestamp,
        "svix-signature" => "v1,#{signature}"
      }
    end

    def generate_svix_signature(svix_id, timestamp, payload)
      secret = Base64.decode64(WEBHOOK_SECRET.sub(/^whsec_/, ""))
      signed_content = "#{svix_id}.#{timestamp}.#{payload}"
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, signed_content))
    end
  end
end
