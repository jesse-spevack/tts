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

  # Returns the PLAN_INFO entry for this subscription's stripe_price_id, or
  # nil when AppConfig::Stripe::PLAN_INFO has drifted from live Stripe price
  # IDs (e.g. a price ID was rotated or a new plan was added without
  # updating AppConfig). agent-team-01q.1: emit a structured warning on
  # miss so drift surfaces in logs instead of silently returning nil.
  def plan_info
    info = AppConfig::Stripe::PLAN_INFO[stripe_price_id]
    if info.nil?
      Rails.logger.warn(
        "event=subscription_plan_info_miss user_id=#{user_id} stripe_price_id=#{stripe_price_id}"
      )
    end
    info
  end
end
