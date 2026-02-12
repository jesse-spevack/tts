# frozen_string_literal: true

class CreditTransaction < ApplicationRecord
  belongs_to :user
  belongs_to :episode, optional: true

  validates :amount, presence: true
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :transaction_type, presence: true, inclusion: { in: %w[purchase usage] }
  validates :stripe_session_id, uniqueness: true, allow_nil: true
end
