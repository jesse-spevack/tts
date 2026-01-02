class BillingController < ApplicationController
  before_action :require_authentication

  def show
    redirect_to upgrade_path and return if Current.user.free?
    @subscription = Current.user.subscription
  end

  def upgrade
    redirect_to billing_path and return unless Current.user.free?
    @usage = EpisodeUsage.current_for(Current.user)
  end
end
