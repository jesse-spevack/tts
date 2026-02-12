class BillingController < ApplicationController
  before_action :require_authentication

  def show
    redirect_to upgrade_path and return if Current.user.free?
    @subscription = Current.user.subscription
  end
end
