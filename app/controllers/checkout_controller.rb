class CheckoutController < ApplicationController
  before_action :require_authentication

  def create
    price_id = params[:price_id]

    unless valid_price?(price_id)
      redirect_to billing_path, alert: "Invalid price selected"
      return
    end

    result = CreatesCheckoutSession.call(
      user: Current.user,
      price_id: price_id,
      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url
    )

    if result.success?
      redirect_to result.data, allow_other_host: true
    else
      redirect_to billing_path, alert: result.error
    end
  end

  def success
  end

  def cancel
    redirect_to billing_path
  end

  private

  def valid_price?(price_id)
    [AppConfig::Stripe::PRICE_ID_MONTHLY, AppConfig::Stripe::PRICE_ID_ANNUAL].include?(price_id)
  end
end
