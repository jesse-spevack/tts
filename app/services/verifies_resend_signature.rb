# frozen_string_literal: true

class VerifiesResendSignature
  TIMESTAMP_TOLERANCE_SECONDS = 300

  def self.call(headers:, raw_payload:, secret:)
    new(headers: headers, raw_payload: raw_payload, secret: secret).call
  end

  def initialize(headers:, raw_payload:, secret:)
    @headers = headers
    @raw_payload = raw_payload
    @secret = secret
  end

  def call
    return Result.failure("Missing webhook secret") if secret.blank?

    svix_id = headers["svix-id"]
    svix_timestamp = headers["svix-timestamp"]
    svix_signature = headers["svix-signature"]

    return Result.failure("Missing svix headers") unless svix_id && svix_timestamp && svix_signature
    return Result.failure("Timestamp outside tolerance window") if timestamp_expired?(svix_timestamp)

    if signature_matches?(svix_id, svix_timestamp, svix_signature)
      Result.success
    else
      Result.failure("Signature mismatch")
    end
  end

  private

  attr_reader :headers, :raw_payload, :secret

  def timestamp_expired?(svix_timestamp)
    (Time.now.to_i - svix_timestamp.to_i).abs > TIMESTAMP_TOLERANCE_SECONDS
  end

  def signature_matches?(svix_id, svix_timestamp, svix_signature)
    signed_content = "#{svix_id}.#{svix_timestamp}.#{raw_payload}"
    expected = expected_signature(signed_content)

    svix_signature.split(" ").any? do |versioned_sig|
      version, signature = versioned_sig.split(",", 2)
      next false unless version == "v1" && signature

      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end

  def expected_signature(signed_content)
    Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", decoded_secret, signed_content)
    )
  end

  def decoded_secret
    Base64.decode64(secret.sub(/^whsec_/, ""))
  end
end
