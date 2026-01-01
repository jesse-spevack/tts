class PortalSessionsController < ApplicationController
  before_action :require_authentication

  def create
    subscription = Current.user.subscription

    unless subscription&.stripe_customer_id
      redirect_to billing_path, alert: "No active subscription"
      return
    end

    result = CreatesBillingPortalSession.call(
      stripe_customer_id: subscription.stripe_customer_id,
      return_url: billing_url
    )

    if result.success?
      redirect_to result.data, allow_other_host: true
    else
      redirect_to billing_path, alert: result.error
    end
  end
end
