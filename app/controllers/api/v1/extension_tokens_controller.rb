module Api
  module V1
    class ExtensionTokensController < ApplicationController
      # This endpoint uses session auth (user logged in via web)
      # NOT token auth - users need to be logged in to generate a token

      def create
        token = ApiToken.generate_for(Current.user)

        render json: {
          token: token.plain_token,
          prefix: token.token_prefix
        }
      end
    end
  end
end
