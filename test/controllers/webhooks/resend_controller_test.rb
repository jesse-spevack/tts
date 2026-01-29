# frozen_string_literal: true

require "test_helper"

module Webhooks
  class ResendControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @user.update!(email_episodes_enabled: true, email_ingest_token: "test_token_123")
      ENV["RESEND_API_KEY"] = "test_api_key"
    end

    teardown do
      ENV.delete("RESEND_API_KEY")
    end

    test "processes email.received webhook and creates episode" do
      email_data = {
        "from" => "sender@example.com",
        "to" => [ "readtome+test_token_123@tts.verynormal.dev" ],
        "subject" => "Test Article",
        "html" => "<p>This is the article content.</p>",
        "text" => "This is the article content.",
        "message_id" => "<test123@example.com>"
      }

      # Mock the Resend API call
      stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
        .to_return(status: 200, body: email_data.to_json, headers: { "Content-Type" => "application/json" })

      payload = {
        type: "email.received",
        data: {
          email_id: "email_abc123",
          from: "sender@example.com",
          to: [ "readtome+test_token_123@tts.verynormal.dev" ],
          subject: "Test Article"
        }
      }.to_json

      assert_difference "ActionMailbox::InboundEmail.count", 1 do
        post webhooks_resend_inbound_url,
          params: payload,
          headers: { "Content-Type" => "application/json" }

        assert_response :ok, "Expected :ok but got #{response.status}: #{response.body}"
      end
    end

    test "ignores non-email.received events" do
      payload = {
        type: "email.sent",
        data: { email_id: "email_abc123" }
      }.to_json

      assert_no_difference "ActionMailbox::InboundEmail.count" do
        post webhooks_resend_inbound_url,
          params: payload,
          headers: { "Content-Type" => "application/json" }
      end

      assert_response :ok
    end

    test "returns bad_request for missing email_id" do
      payload = {
        type: "email.received",
        data: {}
      }.to_json

      post webhooks_resend_inbound_url,
        params: payload,
        headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "returns bad_request for invalid JSON" do
      post webhooks_resend_inbound_url,
        params: "not valid json",
        headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "returns unprocessable_entity when Resend API fails" do
      stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
        .to_return(status: 404, body: { error: "Not found" }.to_json)

      payload = {
        type: "email.received",
        data: { email_id: "email_abc123" }
      }.to_json

      post webhooks_resend_inbound_url,
        params: payload,
        headers: { "Content-Type" => "application/json" }

      assert_response :unprocessable_entity
    end
  end
end
