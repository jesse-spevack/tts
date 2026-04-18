module Extension
  class ConnectController < ApplicationController
    allow_unauthenticated_access

    def show
      unless authenticated?
        redirect_to login_path(return_to: extension_connect_path)
        return
      end

      # Reconnect rotates the extension's token. Revoke only source=extension
      # tokens — a user's personally-created API tokens (source=user) are
      # managed from /settings and must not be touched here.
      Current.user.api_tokens.active.source_extension.find_each do |token|
        RevokesApiToken.call(token: token)
      end

      @api_token = GeneratesApiToken.call(user: Current.user, source: "extension")
    end
  end
end
