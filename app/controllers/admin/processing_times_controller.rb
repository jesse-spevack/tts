module Admin
  class ProcessingTimesController < ApplicationController
    before_action :require_admin

    def show
      @total_episode_count = Episode.unscoped
        .where(status: "complete")
        .where.not(processing_started_at: nil)
        .where.not(processing_completed_at: nil)
        .where.not(source_text_length: nil)
        .count

      @episodes = Episode.unscoped
        .where(status: "complete")
        .where.not(processing_started_at: nil)
        .where.not(processing_completed_at: nil)
        .where.not(source_text_length: nil)
        .select(:id, :source_text_length, :processing_started_at, :processing_completed_at, :title)
        .order(processing_completed_at: :desc)
        .limit(500)

      @chart_points = @episodes.map do |ep|
        seconds = (ep.processing_completed_at - ep.processing_started_at).to_f
        { length: ep.source_text_length, seconds: seconds, title: ep.title }
      end

      @current_estimate = ProcessingEstimate.order(created_at: :desc).first
      @estimate_history = ProcessingEstimate.order(created_at: :desc).limit(10)
    end

    private

    def require_admin
      head :not_found unless Current.user_admin?
    end
  end
end
