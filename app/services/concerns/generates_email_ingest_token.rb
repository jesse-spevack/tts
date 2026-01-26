# frozen_string_literal: true

module GeneratesEmailIngestToken
  extend ActiveSupport::Concern

  private

  def generate_email_ingest_token
    SecureRandom.urlsafe_base64(16).downcase
  end
end
