class PageView < ApplicationRecord
  before_validation :extract_referrer_host

  validates :path, presence: true
  validates :visitor_hash, presence: true

  class << self
    def stats(since:)
      views = where("created_at >= ?", since)
      {
        total_views: views.count,
        unique_visitors: views.distinct.count(:visitor_hash),
        views_by_page: views.group(:path).order("count_all DESC").count
      }
    end

    def top_referrers(since:, limit: 10)
      where("created_at >= ?", since)
        .group(:referrer_host)
        .order("count_all DESC")
        .limit(limit)
        .count
    end

    def daily_views(since:)
      where("created_at >= ?", since)
        .group("date(created_at)")
        .order("date(created_at) DESC")
        .count
    end
  end

  private

  def extract_referrer_host
    return if referrer.blank?

    uri = URI.parse(referrer)
    self.referrer_host = uri.host
  rescue URI::InvalidURIError
    self.referrer_host = nil
  end
end
