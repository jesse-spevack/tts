# frozen_string_literal: true

class MppPayment < ApplicationRecord
  has_prefix_id :mpp

  has_one :narration
  has_one :episode

  belongs_to :user, optional: true

  enum :status, { pending: "pending", completed: "completed", failed: "failed", refunded: "refunded" }

  validates :amount_cents, presence: true
  validates :currency, presence: true
end
