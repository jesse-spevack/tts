# frozen_string_literal: true

class ResolvesPostLoginDestination
  include Rails.application.routes.url_helpers

  # Resolves the post-login redirect path based on the plan selected.
  # Input: plan (string, may be nil or unknown for no-plan signups)
  # Output: a path string for known plans, or nil when the caller should
  # fall back to its own default destination (e.g. after_authentication_url).
  def self.call(plan:)
    new(plan: plan).call
  end

  def initialize(plan:)
    @plan = plan
  end

  def call
    case @plan
    when "premium_monthly"
      checkout_path(price_id: AppConfig::Stripe::PRICE_ID_MONTHLY)
    when "premium_annual"
      checkout_path(price_id: AppConfig::Stripe::PRICE_ID_ANNUAL)
    when "credit_pack"
      checkout_path(pack_size: AppConfig::Credits::PACKS.first[:size])
    end
  end
end
