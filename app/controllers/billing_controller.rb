class BillingController < ApplicationController
  before_action :require_authentication

  def show
    @subscription = Current.user.subscription
  end
end
