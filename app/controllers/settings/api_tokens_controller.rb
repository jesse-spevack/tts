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
      @api_token = GeneratesApiToken.call(user: Current.user, source: "user")
      # Renders create.html.erb with the plain token visible once. The plain
      # token lives only on the service's @api_token.plain_token attr_accessor
      # in memory for this request — never persisted, never retrievable again.
    end

    def destroy
      token = Current.user.api_tokens.source_user.find(params[:id])
      RevokesApiToken.call(token: token)
      redirect_to settings_api_tokens_path, notice: "Token revoked."
    end
  end
end
