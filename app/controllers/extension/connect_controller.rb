module Extension
  class ConnectController < ApplicationController
    def show
      # Generate a new API token for the current user
      @api_token = ApiToken.generate_for(Current.user)
    end
  end
end
