module Settings
  # Displays the plaintext of a just-minted API token exactly once, read from
  # flash populated by Settings::ApiTokensController#create. Distinct resource
  # because the reveal page is semantically not "show the token with this id"
  # (the plaintext is never persisted, never retrievable by id) — it's a
  # one-shot display of an ephemeral secret.
  class ApiTokenRevealsController < ApplicationController
    before_action :require_authentication

    def show
      @plain_token = flash[:reveal_plain_token]
      @token_prefix = flash[:reveal_token_prefix]

      if @plain_token.blank?
        redirect_to settings_api_tokens_path
      end
    end
  end
end
