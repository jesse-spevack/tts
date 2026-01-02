class Subscription < ApplicationRecord
  belongs_to :user

  enum :status, { active: 0, past_due: 1, canceled: 2 }

  validates :stripe_subscription_id, presence: true, uniqueness: true
  validates :stripe_price_id, presence: true
  validates :current_period_end, presence: true

  def canceling?
    cancel_at.present?
  end
end
