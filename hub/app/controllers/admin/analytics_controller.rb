module Admin
  class AnalyticsController < ApplicationController
    before_action :require_admin

    def show
      @stats_7_days = PageView.stats(since: 7.days.ago)
      @stats_30_days = PageView.stats(since: 30.days.ago)
      @top_referrers = PageView.top_referrers(since: 30.days.ago)
      @daily_views = PageView.daily_views(since: 30.days.ago)
    end

    private

    def require_admin
      head :not_found unless Current.session&.user&.admin?
    end
  end
end
