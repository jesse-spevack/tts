# frozen_string_literal: true

class Rack::Attack
  # Use Rails cache by default; tests can override with memory store
  Rack::Attack.cache.store = Rails.cache
  # Rate limit: 20 episode creations per hour per user (identified by token)
  throttle("api/v1/episodes/create", limit: 20, period: 1.hour) do |req|
    if req.path == "/api/v1/episodes" && req.post?
      # Extract bearer token from Authorization header
      auth_header = req.get_header("HTTP_AUTHORIZATION")
      if auth_header&.start_with?("Bearer ")
        auth_header.split(" ", 2).last
      end
    end
  end

  # Custom response for throttled requests (429 with Retry-After)
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s
      },
      [ { error: "Rate limit exceeded. Please try again later." }.to_json ]
    ]
  end
end
