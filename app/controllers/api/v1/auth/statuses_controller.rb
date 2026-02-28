module Api
  module V1
    module Auth
      class StatusesController < BaseController
        def show
          render json: {
            email: current_user.email_address,
            tier: current_user.effective_tier,
            credits_remaining: current_user.credits_remaining,
            character_limit: current_user.character_limit
          }
        end
      end
    end
  end
end
