class ValidatesPrice
  SUBSCRIPTION_PRICE_IDS = [
    AppConfig::Stripe::PRICE_ID_MONTHLY,
    AppConfig::Stripe::PRICE_ID_ANNUAL
  ].freeze

  VALID_PRICE_IDS = (SUBSCRIPTION_PRICE_IDS + [
    AppConfig::Stripe::PRICE_ID_CREDIT_PACK
  ]).freeze

  def self.call(price_id)
    if VALID_PRICE_IDS.include?(price_id)
      Result.success(price_id)
    else
      Result.failure("Invalid price selected")
    end
  end

  def self.credit_pack?(price_id)
    price_id == AppConfig::Stripe::PRICE_ID_CREDIT_PACK
  end

  def self.subscription?(price_id)
    SUBSCRIPTION_PRICE_IDS.include?(price_id)
  end
end
