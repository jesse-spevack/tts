# frozen_string_literal: true

class ProcessedWebhookEmail < ApplicationRecord
  validates :email_id, presence: true
  validates :source, presence: true
  validates :processed_at, presence: true
  validates :email_id, uniqueness: { scope: :source }

  # Atomically checks if an email has been processed and marks it if not.
  # Returns true if this is a new email that should be processed.
  # Returns false if this email was already processed (duplicate).
  def self.process_if_new(email_id:, source:)
    create!(email_id: email_id, source: source, processed_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end
end
