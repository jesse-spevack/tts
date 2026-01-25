module Settings
  class ExtensionsController < ApplicationController
    before_action :require_authentication

    def show
      @api_token = ApiToken.active_token_for(Current.user)
    end

    def destroy
      api_token = ApiToken.active_token_for(Current.user)

      if api_token
        RevokesApiToken.call(token: api_token)
        redirect_to settings_extensions_path, notice: "Extension disconnected successfully."
      else
        redirect_to settings_extensions_path, alert: "No active extension connection found."
      end
    end
  end
end
