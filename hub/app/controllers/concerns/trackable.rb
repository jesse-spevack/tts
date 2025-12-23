module Trackable
  extend ActiveSupport::Concern

  BOT_PATTERNS = /bot|crawler|spider|scraper|curl|wget/i

  included do
    before_action :track_page_view
  end

  private

  def track_page_view
    return if authenticated?
    return if bot_request?
    return unless request.get?

    PageView.insert({
      path: request.path,
      referrer: request.referer,
      referrer_host: extract_host(request.referer),
      visitor_hash: generate_visitor_hash,
      user_agent: request.user_agent,
      created_at: Time.current,
      updated_at: Time.current
    })
  end

  def bot_request?
    request.user_agent&.match?(BOT_PATTERNS)
  end

  def generate_visitor_hash
    daily_salt = Date.current.to_s
    data = "#{request.remote_ip}#{request.user_agent}#{daily_salt}"
    Digest::SHA256.hexdigest(data)
  end

  def extract_host(url)
    return nil if url.blank?
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
