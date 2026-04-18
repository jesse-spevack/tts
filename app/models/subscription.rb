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

  def status_pill_label
    return "Canceling" if active? && canceling?
    return "Active" if active?
    return "Past Due" if past_due?
    "Canceled"
  end

  def status_pill_classes
    case status_pill_label
    when "Active"
      "bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-400"
    when "Canceling", "Past Due"
      "bg-yellow-50 text-yellow-700 dark:bg-yellow-500/10 dark:text-yellow-400"
    else # "Canceled"
      "bg-mist-100 text-mist-600 dark:bg-mist-500/10 dark:text-mist-400"
    end
  end

  def manage_billing_cta_label
    canceled? ? "Resubscribe" : "Manage Billing"
  end

  private

  def plan_info
    AppConfig::Stripe::PLAN_INFO[stripe_price_id]
  end
end
