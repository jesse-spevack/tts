module Api
  module V1
    module Auth
      class MagicLinksController < BaseController
        skip_before_action :authenticate_token!
        rate_limit to: 10, within: 3.minutes, only: :create,
          with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }

        def create
          email = params[:email_address].to_s.strip

          if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
            render json: { error: "invalid_email" }, status: :unprocessable_entity
            return
          end

          SendsMagicLink.call(email_address: email)
          render json: { ok: true }, status: :ok
        end
      end
    end
  end
end
