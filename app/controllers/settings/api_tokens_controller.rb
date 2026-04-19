module Settings
  class ApiTokensController < ApplicationController
    before_action :require_authentication

    # Self-serve Personal Access Token management. Scoped to the current
    # user AND to source=user so the Chrome-extension tokens (source=extension)
    # stay managed by Settings::ExtensionsController, not exposed or revocable
    # from here.

    def index
      @api_tokens = Current.user
        .api_tokens
        .source_user
        .active
        .order(created_at: :desc)
    end

    def create
      api_token = GeneratesApiToken.call(user: Current.user, source: "user")
      # PRG (POST → redirect → GET) so a browser refresh on the reveal page
      # does NOT re-submit and create a duplicate token. The plain token
      # rides along in flash (encrypted + signed session, cleared after the
      # next request), which is acceptable as a one-shot transport.
      flash[:reveal_plain_token] = api_token.plain_token
      flash[:reveal_token_prefix] = api_token.token_prefix
      redirect_to settings_api_token_reveal_path
    end

    def destroy
      token = Current.user.api_tokens.source_user.find(params[:id])
      RevokesApiToken.call(token: token)
      redirect_to settings_api_tokens_path, notice: "Token revoked."
    end
  end
end
