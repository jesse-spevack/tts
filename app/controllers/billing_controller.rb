class BillingController < ApplicationController
  before_action :require_authentication

  def show
    @subscription = Current.user.subscription
    @usage = EpisodeUsage.current_for(Current.user) if Current.user.free?
  end
end
