module Extension
  class ConnectController < ApplicationController
    allow_unauthenticated_access

    def show
      unless authenticated?
        redirect_to login_path(return_to: extension_connect_path)
        return
      end

      # Generate a new API token for the current user
      @api_token = GeneratesApiToken.call(user: Current.user)
    end
  end
end
