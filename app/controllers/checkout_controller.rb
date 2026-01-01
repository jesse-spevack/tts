class CheckoutController < ApplicationController
  before_action :require_authentication

  def create
    price_result = ValidatesPrice.call(params[:price_id])
    unless price_result.success?
      redirect_to billing_path, alert: price_result.error
      return
    end

    result = CreatesCheckoutSession.call(
      user: Current.user,
      price_id: price_result.data,
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
end
