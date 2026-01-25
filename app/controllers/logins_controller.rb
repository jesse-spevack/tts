class LoginsController < ApplicationController
  allow_unauthenticated_access

  def new
    return redirect_to new_episode_path if authenticated?

    @return_to = params[:return_to]
  end
end
