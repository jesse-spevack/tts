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
      #
      # Wrapped in a transaction so rotation is atomic: if any revoke raises
      # mid-loop, the aborted transaction leaves prior tokens un-revoked
      # rather than producing an inconsistent half-revoked-no-new-token state
      # that the user would see as "reconnect failed" without any indication
      # their token pool had drifted.
      ApiToken.transaction do
        Current.user.api_tokens.active.source_extension.find_each do |token|
          RevokesApiToken.call(token: token)
        end

        @api_token = GeneratesApiToken.call(user: Current.user, source: "extension")
      end
    end
  end
end
