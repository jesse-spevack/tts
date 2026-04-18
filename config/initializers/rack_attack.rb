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

  # Rate limit: 60 narration polls per minute per IP
  # Prevents enumeration of public_ids
  throttle("api/v1/narrations/show", limit: 60, period: 1.minute) do |req|
    if req.path.start_with?("/api/v1/narrations/") && req.get?
      req.ip
    end
  end

  # Rate limit: 10 unauthenticated episode creations per minute per IP
  # Protects the MPP 402 challenge endpoint from being flooded with requests
  # that each create a Stripe PaymentIntent and pending MppPayment row.
  # Authenticated requests (valid Bearer token) are excluded — they have their
  # own per-token throttle above.
  throttle("api/v1/episodes/create/unauthenticated", limit: 10, period: 1.minute) do |req|
    if req.path == "/api/v1/episodes" && req.post?
      auth_header = req.get_header("HTTP_AUTHORIZATION")
      has_bearer = auth_header&.match?(/\ABearer\s+\S/)

      req.ip unless has_bearer
    end
  end

  # Rate limit: 5 device code creations per minute per IP
  throttle("api/v1/auth/device_codes/create", limit: 5, period: 1.minute) do |req|
    if req.path == "/api/v1/auth/device_codes" && req.post?
      req.ip
    end
  end

  # Rate limit: 30 device token polls per minute per IP
  # RFC 8628 suggests 5-second intervals (~12 polls/min), so 30 gives headroom
  throttle("api/v1/auth/device_tokens/create", limit: 30, period: 1.minute) do |req|
    if req.path == "/api/v1/auth/device_tokens" && req.post?
      req.ip
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
