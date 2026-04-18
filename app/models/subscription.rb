class Subscription < ApplicationRecord
  belongs_to :user

  enum :status, { active: 0, past_due: 1, canceled: 2 }

  validates :stripe_subscription_id, presence: true, uniqueness: true
  validates :stripe_price_id, presence: true
  validates :current_period_end, presence: true

  def canceling?
    cancel_at.present?
  end

  def plan_name
    plan_info&.dig(:name)
  end

  def plan_display_price
    plan_info&.dig(:display)
  end

  private

  def plan_info
    AppConfig::Stripe::PLAN_INFO[stripe_price_id]
  end
end
