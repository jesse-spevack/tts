class ValidatesPrice
  VALID_PRICE_IDS = [
    AppConfig::Stripe::PRICE_ID_MONTHLY,
    AppConfig::Stripe::PRICE_ID_ANNUAL
  ].freeze

  def self.call(price_id)
    if VALID_PRICE_IDS.include?(price_id)
      Result.success(price_id)
    else
      Result.failure("Invalid price selected")
    end
  end
end
