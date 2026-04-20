# frozen_string_literal: true

require "test_helper"

class VerifiesResendSignatureTest < ActiveSupport::TestCase
  WEBHOOK_SECRET = "whsec_test_secret_key_for_testing"

  test "returns success for valid signature" do
    payload = { type: "email.received" }.to_json
    svix_id = "msg_#{SecureRandom.hex(8)}"
    svix_timestamp = Time.now.to_i.to_s
    signature = compute_signature(svix_id, svix_timestamp, payload)

    result = VerifiesResendSignature.call(
      headers: {
        "svix-id" => svix_id,
        "svix-timestamp" => svix_timestamp,
        "svix-signature" => "v1,#{signature}"
      },
      raw_payload: payload,
      secret: WEBHOOK_SECRET
    )

    assert result.success?
  end

  test "returns failure when secret is blank" do
    payload = "{}"

    result = VerifiesResendSignature.call(
      headers: { "svix-id" => "msg_1", "svix-timestamp" => Time.now.to_i.to_s, "svix-signature" => "v1,sig" },
      raw_payload: payload,
      secret: nil
    )

    assert result.failure?
  end

  test "returns failure when svix headers are missing" do
    result = VerifiesResendSignature.call(
      headers: { "svix-id" => nil, "svix-timestamp" => nil, "svix-signature" => nil },
      raw_payload: "{}",
      secret: WEBHOOK_SECRET
    )

    assert result.failure?
  end

  test "returns failure for expired timestamp" do
    payload = "{}"
    svix_id = "msg_1"
    old_timestamp = (Time.now.to_i - 600).to_s # 10 minutes ago
    signature = compute_signature(svix_id, old_timestamp, payload)

    result = VerifiesResendSignature.call(
      headers: {
        "svix-id" => svix_id,
        "svix-timestamp" => old_timestamp,
        "svix-signature" => "v1,#{signature}"
      },
      raw_payload: payload,
      secret: WEBHOOK_SECRET
    )

    assert result.failure?
  end

  test "returns failure for invalid signature" do
    result = VerifiesResendSignature.call(
      headers: {
        "svix-id" => "msg_1",
        "svix-timestamp" => Time.now.to_i.to_s,
        "svix-signature" => "v1,invalid_signature"
      },
      raw_payload: "{}",
      secret: WEBHOOK_SECRET
    )

    assert result.failure?
  end

  test "returns failure when signature header has no v1 prefix" do
    payload = "{}"
    svix_id = "msg_1"
    svix_timestamp = Time.now.to_i.to_s
    signature = compute_signature(svix_id, svix_timestamp, payload)

    result = VerifiesResendSignature.call(
      headers: {
        "svix-id" => svix_id,
        "svix-timestamp" => svix_timestamp,
        "svix-signature" => "v2,#{signature}"
      },
      raw_payload: payload,
      secret: WEBHOOK_SECRET
    )

    assert result.failure?
  end

  test "accepts any of multiple space-separated signatures" do
    payload = "{}"
    svix_id = "msg_1"
    svix_timestamp = Time.now.to_i.to_s
    valid_signature = compute_signature(svix_id, svix_timestamp, payload)

    result = VerifiesResendSignature.call(
      headers: {
        "svix-id" => svix_id,
        "svix-timestamp" => svix_timestamp,
        "svix-signature" => "v1,bogus v1,#{valid_signature}"
      },
      raw_payload: payload,
      secret: WEBHOOK_SECRET
    )

    assert result.success?
  end

  private

  def compute_signature(svix_id, timestamp, payload)
    secret = Base64.decode64(WEBHOOK_SECRET.sub(/^whsec_/, ""))
    signed_content = "#{svix_id}.#{timestamp}.#{payload}"
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, signed_content))
  end
end
