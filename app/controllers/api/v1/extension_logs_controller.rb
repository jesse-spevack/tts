module Api
  module V1
    class ExtensionLogsController < BaseController
      def create
        # Log the extension failure for debugging/analytics
        # Sanitize input to prevent log injection (strip newlines, limit length)
        error_type = params[:error_type].to_s.gsub(/[\r\n]/, " ")[0, 100]
        url = params[:url].to_s.gsub(/[\r\n]/, " ")[0, 500]

        Rails.logger.error "[ExtensionLog] User #{current_user.id}: #{error_type} - #{url}"

        render json: { logged: true }, status: :created
      end
    end
  end
end
