# frozen_string_literal: true

require "test_helper"

class FetchesResendEmailTest < ActiveSupport::TestCase
  setup do
    ENV["RESEND_API_KEY"] = "test_api_key"
  end

  teardown do
    ENV.delete("RESEND_API_KEY")
  end

  test "returns success with parsed JSON on 200 response" do
    email_data = {
      "from" => "sender@example.com",
      "to" => [ "recipient@example.com" ],
      "subject" => "Test",
      "html" => "<p>hi</p>",
      "text" => "hi"
    }

    stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
      .with(headers: { "Authorization" => "Bearer test_api_key" })
      .to_return(status: 200, body: email_data.to_json, headers: { "Content-Type" => "application/json" })

    result = FetchesResendEmail.call(email_id: "email_abc123")

    assert result.success?
    assert_equal "sender@example.com", result.data["from"]
    assert_equal "Test", result.data["subject"]
  end

  test "sends bearer token auth header from ENV" do
    stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
      .with(headers: { "Authorization" => "Bearer test_api_key" })
      .to_return(status: 200, body: "{}")

    result = FetchesResendEmail.call(email_id: "email_abc123")

    assert result.success?
  end

  test "returns failure when API key is blank" do
    ENV.delete("RESEND_API_KEY")

    result = FetchesResendEmail.call(email_id: "email_abc123")

    assert result.failure?
  end

  test "returns failure on non-success response" do
    stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
      .to_return(status: 404, body: { error: "Not found" }.to_json)

    result = FetchesResendEmail.call(email_id: "email_abc123")

    assert result.failure?
  end

  test "returns failure on 500 response" do
    stub_request(:get, "https://api.resend.com/emails/receiving/email_abc123")
      .to_return(status: 500, body: "Internal Server Error")

    result = FetchesResendEmail.call(email_id: "email_abc123")

    assert result.failure?
  end
end
