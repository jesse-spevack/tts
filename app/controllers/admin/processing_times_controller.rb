module Admin
  class ProcessingTimesController < ApplicationController
    before_action :require_admin

    def show
      report = BuildsProcessingTimesReport.call

      @chart_points = report.chart_points
      @max_length = report.max_length
      @max_seconds = report.max_seconds
      @total_episode_count = report.total_episode_count
      @current_estimate = report.current_estimate
      @estimate_history = report.estimate_history
    end

    private

    def require_admin
      head :not_found unless Current.user_admin?
    end
  end
end
