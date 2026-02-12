# frozen_string_literal: true

class CreditBalance < ApplicationRecord
  belongs_to :user

  validates :balance, numericality: { greater_than_or_equal_to: 0 }

  def self.for(user)
    find_or_create_by(user: user)
  end

  def sufficient?
    balance > 0
  end

  def deduct!
    with_lock do
      raise InsufficientCreditsError if balance <= 0
      decrement!(:balance)
    end
  end

  def add!(amount)
    with_lock do
      increment!(:balance, amount)
    end
  end

  class InsufficientCreditsError < StandardError; end
end
