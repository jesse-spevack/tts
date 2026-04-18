module Api
  module V1
    module Auth
      class ExtensionTokensController < ApplicationController
        # This endpoint uses session auth (user logged in via web)
        # NOT token auth - users need to be logged in to generate a token

        def create
          unless Current.user
            render json: { error: "Unauthorized" }, status: :unauthorized
            return
          end

          # Same rotation semantics as Extension::ConnectController — only
          # revoke source=extension tokens so user-created tokens survive.
          Current.user.api_tokens.active.source_extension.find_each do |t|
            RevokesApiToken.call(token: t)
          end

          token = GeneratesApiToken.call(user: Current.user, source: "extension")

          render json: {
            token: token.plain_token
          }
        end
      end
    end
  end
end
