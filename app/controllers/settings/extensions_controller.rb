module Settings
  class ExtensionsController < ApplicationController
    before_action :require_authentication

    def show
      @api_token = ApiToken.active_token_for(Current.user)
    end
  end
end
