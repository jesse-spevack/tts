module Api
  module V1
    class ExtensionTokensController < ApplicationController
      # This endpoint uses session auth (user logged in via web)
      # NOT token auth - users need to be logged in to generate a token

      def create
        unless Current.user
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        token = ApiToken.generate_for(Current.user)

        render json: {
          token: token.plain_token
        }
      end
    end
  end
end
