class ValidatesPrice
  VALID_PRICE_IDS = [
    AppConfig::Stripe::PRICE_ID_MONTHLY,
    AppConfig::Stripe::PRICE_ID_ANNUAL
  ].freeze

  def self.call(price_id)
    VALID_PRICE_IDS.include?(price_id)
  end
end
