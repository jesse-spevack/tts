module Extension
  class ConnectController < ApplicationController
    allow_unauthenticated_access

    def show
      unless authenticated?
        redirect_to login_path(return_to: extension_connect_path)
        return
      end

      @api_token = RotatesExtensionToken.call(user: Current.user)
    end
  end
end
