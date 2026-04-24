module Admin
  class MetricsController < ApplicationController
    before_action :require_admin

    def show
      @report = BuildsAdminMetricsReport.call
    end

    private

    def require_admin
      head :not_found unless Current.user_admin?
    end
  end
end
