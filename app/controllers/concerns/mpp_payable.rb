# frozen_string_literal: true

# Controller concern that adds MPP (Micropayment Protocol) as a third
# authorization path alongside bearer tokens (API + OAuth).
#
# Authorization decision tree:
#   Request arrives at POST /api/v1/episodes
#     ├─ Bearer token present?
#     │    ├─ Yes → Authenticate user (existing flow)
#     │    │    ├─ Subscriber? → Allow (existing flow, no changes)
#     │    │    ├─ Has credits? → Allow (existing flow, no changes)
#     │    │    └─ Not subscriber, no credits, free tier exhausted?
#     │    │         ├─ Payment credential in header? → Verify MPP → create Episode for user
#     │    │         └─ No credential → Return 402 challenge
#     │    └─ Auth fails → fall through to MPP check
#     │
#     ├─ No Bearer token (or auth failed)
#     │    ├─ Payment credential present? → Verify MPP → create Narration (no user)
#     │    └─ No credential → Return 402 challenge
module MppPayable
  extend ActiveSupport::Concern

  # Inner module that gets prepended so its methods take priority over the
  # including controller's own method definitions.
  module Overrides
    private

    # Override the episodes controller's permission check to return 402
    # instead of 403 when the user has exhausted free tier but could pay via MPP.
    def check_episode_creation_permission
      result = ChecksEpisodeCreationPermission.call(user: current_user)
      return if result.success?

      # Permission denied — but if there's a Payment credential, try MPP
      if @mpp_payment_credential.present?
        handle_authenticated_mpp_payment(@mpp_payment_credential)
      else
        render_402_challenge
      end
    end
  end

  included do
    prepend Overrides

    # Run before authenticate_token! to intercept MPP-only requests
    prepend_before_action :handle_mpp_auth, only: [ :create ]
  end

  private

  # Main entry point. Runs before authenticate_token!.
  #
  # For requests with no bearer token (or invalid bearer token), this method
  # handles the full MPP flow or returns a 402 challenge, halting the chain
  # so authenticate_token! never fires a 401.
  #
  # For requests WITH a valid bearer token, we let the normal auth flow run,
  # but we override check_episode_creation_permission to return 402 instead
  # of 403 when the user can pay via MPP.
  def handle_mpp_auth
    bearer_token = extract_bearer_token_from_header
    payment_credential = extract_payment_credential

    if bearer_token.present?
      # Try authenticating the bearer token
      if authenticate_bearer(bearer_token)
        # User is authenticated. Let the existing flow handle subscribers/credit users.
        # We only intervene at the permission check stage (see override below).
        @mpp_payment_credential = payment_credential
        return # continue the before_action chain
      end
    end

    # No valid bearer token — this is an anonymous or unauthenticated request
    if payment_credential.present?
      handle_anonymous_mpp_payment(payment_credential)
    else
      render_402_challenge
    end
  end

  # ── Bearer token parsing ──────────────────────────────────────────────

  # Parse bearer token from potentially comma-separated Authorization header.
  # Per RFC 9110: Authorization: Bearer <token>, Payment <credential>
  def extract_bearer_token_from_header
    header = request.headers["Authorization"]
    return nil if header.blank?

    header.split(",").each do |part|
      part = part.strip
      if part.start_with?("Bearer ")
        return part.split(" ", 2).last
      end
    end

    nil
  end

  # Parse Payment credential from Authorization header.
  def extract_payment_credential
    header = request.headers["Authorization"]
    return nil if header.blank?

    header.split(",").each do |part|
      part = part.strip
      if part.start_with?("Payment ")
        return part.split(" ", 2).last
      end
    end

    nil
  end

  # Authenticate a bearer token via the existing base controller methods.
  def authenticate_bearer(token)
    if authenticate_via_api_token(token)
      true
    elsif authenticate_via_doorkeeper(token)
      true
    else
      false
    end
  end

  # ── MPP payment flows ─────────────────────────────────────────────────

  # Anonymous user with Payment credential: verify and create Narration
  def handle_anonymous_mpp_payment(credential)
    verification = Mpp::VerifiesCredential.call(credential: credential)

    unless verification.success?
      render_402_challenge
      return
    end

    mpp_payment = MppPayment.find_by!(challenge_id: verification.data[:challenge_id])
    mpp_payment.update!(
      status: :completed,
      tx_hash: verification.data[:tx_hash]
    )

    narration = create_narration(mpp_payment)
    receipt = generate_receipt(verification.data[:tx_hash], mpp_payment)

    response.headers["Payment-Receipt"] = receipt.data[:header_value]
    render json: { narration_id: narration.public_id }, status: :created
  end

  # Authenticated user (free tier exhausted) with Payment credential:
  # verify and create Episode
  def handle_authenticated_mpp_payment(credential)
    verification = Mpp::VerifiesCredential.call(credential: credential)

    unless verification.success?
      render_402_challenge
      return
    end

    mpp_payment = MppPayment.find_by!(challenge_id: verification.data[:challenge_id])
    mpp_payment.update!(
      status: :completed,
      tx_hash: verification.data[:tx_hash],
      user_id: current_user.id
    )

    # Create the episode using the existing controller flow
    create_episode_via_mpp(mpp_payment, verification)
  end

  # ── Episode creation (authenticated + paid) ───────────────────────────

  def create_episode_via_mpp(mpp_payment, verification)
    podcast = GetsDefaultPodcastForUser.call(user: current_user)

    result = case episode_params[:source_type]
    when "url"
      create_from_url(podcast)
    when "text"
      create_from_text(podcast)
    when "extension"
      create_from_extension(podcast)
    else
      render json: { error: "source_type is required. Use 'url', 'text', or 'extension'." }, status: :unprocessable_entity
      return
    end

    if result.success?
      receipt = generate_receipt(verification.data[:tx_hash], mpp_payment)
      response.headers["Payment-Receipt"] = receipt.data[:header_value]
      render json: { id: result.data.prefix_id }, status: :created
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  # ── Narration creation (anonymous + paid) ─────────────────────────────

  def create_narration(mpp_payment)
    source_type = map_source_type(episode_params[:source_type])

    Narration.create!(
      mpp_payment: mpp_payment,
      title: episode_params[:title] || "Untitled",
      author: episode_params[:author],
      description: episode_params[:description],
      source_url: episode_params[:url],
      source_text: episode_params[:content] || episode_params[:text],
      source_type: source_type,
      expires_at: 24.hours.from_now
    )
  end

  def map_source_type(type)
    case type
    when "url" then :url
    when "text", "extension" then :text
    else :text
    end
  end

  # ── Receipt generation ────────────────────────────────────────────────

  def generate_receipt(tx_hash, mpp_payment)
    Mpp::GeneratesReceipt.call(tx_hash: tx_hash, mpp_payment: mpp_payment)
  end

  # ── 402 Challenge response ────────────────────────────────────────────

  def render_402_challenge
    amount_cents = AppConfig::Mpp::PRICE_CENTS
    currency = AppConfig::Mpp::CURRENCY
    placeholder_recipient = AppConfig::Mpp::RECIPIENT_ADDRESS.presence ||
      "0x0000000000000000000000000000000000000000"

    # Step 1: generate the HMAC challenge. The challenge's recipient field
    # is a placeholder (hashed into the HMAC for integrity); the real on-chain
    # recipient is the Stripe-issued deposit_address below, which the verifier
    # looks up via cache at verification time.
    challenge_result = Mpp::GeneratesChallenge.call(
      amount_cents: amount_cents,
      currency: currency,
      recipient: placeholder_recipient
    )
    challenge = challenge_result.data

    # Step 2: provision a Stripe PaymentIntent + deposit address, cache it,
    # and persist a pending MppPayment row linked to this challenge_id so
    # refunds can find the stripe_payment_intent_id later (B3).
    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: amount_cents,
      currency: currency,
      challenge_id: challenge[:id]
    )

    unless deposit_result.success?
      render json: { error: "Payment provisioning failed: #{deposit_result.error}" },
        status: :service_unavailable
      return
    end

    deposit_address = deposit_result.data[:deposit_address]

    response.headers["WWW-Authenticate"] = challenge[:header_value]

    render json: {
      error: "Payment required",
      challenge: {
        id: challenge[:id],
        amount: amount_cents,
        currency: currency,
        methods: [ "tempo" ],
        realm: challenge[:realm],
        expires: challenge[:expires],
        deposit_address: deposit_address
      }
    }, status: :payment_required
  end
end
