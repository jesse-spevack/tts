# frozen_string_literal: true

class MppPayment < ApplicationRecord
  has_one :narration
  has_one :episode

  belongs_to :user, optional: true

  enum :status, { pending: "pending", completed: "completed", failed: "failed", refunded: "refunded" }

  validates :public_id, presence: true, uniqueness: true
  validates :amount_cents, presence: true
  validates :currency, presence: true

  before_validation :generate_public_id, on: :create

  private

  def generate_public_id
    self.public_id ||= "mpp_#{SecureRandom.hex(12)}"
  end
end
