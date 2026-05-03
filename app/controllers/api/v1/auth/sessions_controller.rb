module Api
  module V1
    module Auth
      class SessionsController < BaseController
        skip_before_action :authenticate_token!

        def create
          result = AuthenticatesMagicLink.call(token: params[:token])

          if result.success?
            user = result.data
            api_token = GeneratesApiToken.call(user: user, source: "android")
            render json: {
              access_token: api_token.plain_token,
              user_email: user.email_address
            }, status: :ok
          else
            render json: { error: "invalid_or_expired" }, status: :unauthorized
          end
        end
      end
    end
  end
end
