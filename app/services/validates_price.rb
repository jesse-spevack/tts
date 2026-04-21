class ValidatesPrice
  SUBSCRIPTION_PRICE_IDS = [
    AppConfig::Stripe::PRICE_ID_MONTHLY,
    AppConfig::Stripe::PRICE_ID_ANNUAL
  ].freeze

  def self.credit_pack_price_ids
    AppConfig::Credits::PACKS.map { |pack| pack[:stripe_price_id] }
  end

  def self.valid_price_ids
    credit_pack_price_ids
  end

  def self.call(price_id)
    if valid_price_ids.include?(price_id)
      Result.success(price_id)
    else
      Result.failure("Invalid price selected")
    end
  end

  def self.credit_pack?(price_id)
    credit_pack_price_ids.include?(price_id)
  end
end
