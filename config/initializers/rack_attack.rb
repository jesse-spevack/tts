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
  throttle("api/v1/mpp/narrations/show", limit: 60, period: 1.minute) do |req|
    if req.path.start_with?("/api/v1/mpp/narrations/") && req.get?
      req.ip
    end
  end

  # Rate limit: 10 anonymous MPP narration creations per minute per IP.
  #
  # POST /api/v1/mpp/narrations is the anonymous-pay-to-create endpoint.
  # Every request without a Payment credential triggers the 402 challenge
  # flow, which has a real cost per call:
  #   1. Stripe PaymentIntent creation (Stripe API call + account resource)
  #   2. HMAC challenge sign + cache write
  #   3. Pending MppPayment row inserted (cleaned up hourly by
  #      CleanupStaleMppPaymentsJob but accumulates inside that window)
  #
  # Why 10/minute per IP:
  # - A legitimate client paying with mppx typically makes 2 requests per
  #   narration (initial 402, retry with credential). 10/min gives 5× that
  #   headroom for retry-on-failure loops.
  # - An attacker flooding the endpoint would otherwise cost us Stripe API
  #   quota and DB bloat at zero cost to themselves (no wallet needed for
  #   the 402 path).
  # - 1-minute window is short enough to limit sustained abuse but long
  #   enough to accommodate bursty testing from a single integrator.
  #
  # There is no authenticated path on this route: all callers are
  # anonymous by design, so we throttle every POST.
  throttle("api/v1/mpp/narrations/create", limit: 10, period: 1.minute) do |req|
    if req.path == "/api/v1/mpp/narrations" && req.post?
      req.ip
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
