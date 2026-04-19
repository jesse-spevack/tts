# frozen_string_literal: true

require "test_helper"

class Mpp::VerifiesHmacTest < ActiveSupport::TestCase
  setup do
    @challenge = build_signed_challenge
  end

  test "returns success for a correctly signed challenge" do
    result = Mpp::VerifiesHmac.call(challenge: @challenge)

    assert result.success?
  end

  test "returns failure when id does not match" do
    tampered = @challenge.merge("id" => "0" * 64)

    result = Mpp::VerifiesHmac.call(challenge: tampered)

    refute result.success?
    assert_match(/HMAC verification failed/, result.error)
  end

  test "returns failure when realm is tampered" do
    tampered = @challenge.merge("realm" => "attacker.example.com")

    result = Mpp::VerifiesHmac.call(challenge: tampered)

    refute result.success?
  end

  test "returns failure when request payload is tampered" do
    tampered = @challenge.merge("request" => Base64.encode64('{"amount":"99"}'))

    result = Mpp::VerifiesHmac.call(challenge: tampered)

    refute result.success?
  end

  test "returns failure when expires is tampered" do
    tampered = @challenge.merge("expires" => "2099-01-01T00:00:00+00:00")

    result = Mpp::VerifiesHmac.call(challenge: tampered)

    refute result.success?
  end

  private

  def build_signed_challenge
    realm = "test.example.com"
    method = "tempo"
    intent = "charge"
    request_json = '{"amount":"1000000","currency":"0xtoken","recipient":"0xabc"}'
    request_b64 = Base64.encode64(request_json)
    expires = 5.minutes.from_now.iso8601

    hmac_data = "#{realm}|#{method}|#{intent}|#{request_json}|#{expires}"
    id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

    {
      "id" => id,
      "realm" => realm,
      "method" => method,
      "intent" => intent,
      "request" => request_b64,
      "expires" => expires
    }
  end
end
