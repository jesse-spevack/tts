# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  validates :provider, presence: true, inclusion: { in: %w[stripe resend] }
  validates :event_id, presence: true, uniqueness: { scope: :provider }
end
