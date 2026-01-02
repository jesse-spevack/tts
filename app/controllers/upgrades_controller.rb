class UpgradesController < ApplicationController
  before_action :require_authentication

  def show
    redirect_to billing_path and return unless Current.user.free?
    @usage = EpisodeUsage.current_for(Current.user)
  end
end
