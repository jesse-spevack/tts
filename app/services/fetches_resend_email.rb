# frozen_string_literal: true

class FetchesResendEmail
  include StructuredLogging

  API_BASE_URL = "https://api.resend.com/emails/receiving"

  def self.call(email_id:)
    new(email_id: email_id).call
  end

  def initialize(email_id:)
    @email_id = email_id
  end

  def call
    api_key = ENV["RESEND_API_KEY"]
    return Result.failure("Missing Resend API key") if api_key.blank?

    uri = URI("#{API_BASE_URL}/#{email_id}")
    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{api_key}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    if response.is_a?(Net::HTTPSuccess)
      Result.success(JSON.parse(response.body))
    else
      log_error "resend_api_error", status: response.code, body: response.body.to_s.truncate(200)
      Result.failure("Resend API returned #{response.code}")
    end
  end

  private

  attr_reader :email_id
end
