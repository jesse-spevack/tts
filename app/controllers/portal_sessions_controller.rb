class PortalSessionsController < ApplicationController
  before_action :require_authentication

  def create
    result = CreatesBillingPortalSession.call(
      user: Current.user,
      return_url: billing_url
    )

    if result.success?
      redirect_to result.data, allow_other_host: true
    else
      redirect_to billing_path, alert: result.error
    end
  end
end
