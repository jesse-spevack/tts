module Api
  module V1
    class ExtensionLogsController < BaseController
      def create
        # Log the extension failure for debugging/analytics
        Rails.logger.info "[ExtensionLog] User #{current_user.id}: #{params[:error_type]} - #{params[:url]}"

        render json: { logged: true }, status: :created
      end
    end
  end
end
