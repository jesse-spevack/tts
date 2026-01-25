class LoginsController < ApplicationController
  allow_unauthenticated_access

  def new
    if authenticated?
      redirect_to params[:return_to].presence || new_episode_path
      return
    end

    @return_to = params[:return_to]
  end
end
