# frozen_string_literal: true

# Controller concern that adds MPP (Machine Payments Protocol,
# http://mpp.dev/) as a third authorization path alongside bearer
# tokens (API + OAuth).
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
  include StructuredLogging

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
    bearer_token = extract_bearer_token
    payment_credential = extract_payment_credential

    if bearer_token.present?
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
      log_warn "mpp_anonymous_payment_rejected", error: verification.error
      render_402_challenge
      return
    end

    mpp_payment = MppPayment.find_by!(challenge_id: verification.data[:challenge_id])
    mpp_payment.update!(
      status: :completed,
      tx_hash: verification.data[:tx_hash]
    )

    log_info "mpp_anonymous_payment_verified",
      mpp_payment_id: mpp_payment.prefix_id,
      tx_hash: verification.data[:tx_hash]

    result = Mpp::CreatesNarration.call(mpp_payment: mpp_payment, params: episode_params)

    unless result.success?
      log_error "mpp_narration_creation_failed", mpp_payment_id: mpp_payment.prefix_id, error: result.error
      render json: { error: result.error }, status: :unprocessable_entity
      return
    end

    log_info "mpp_narration_created",
      narration_id: result.data.prefix_id,
      mpp_payment_id: mpp_payment.prefix_id

    receipt = Mpp::GeneratesReceipt.call(tx_hash: verification.data[:tx_hash], mpp_payment: mpp_payment)

    response.headers["Payment-Receipt"] = receipt.data[:header_value]
    render json: { narration_id: result.data.prefix_id }, status: :created
  end

  # Authenticated user (free tier exhausted) with Payment credential:
  # verify and create Episode
  def handle_authenticated_mpp_payment(credential)
    verification = Mpp::VerifiesCredential.call(credential: credential)

    unless verification.success?
      log_warn "mpp_authenticated_payment_rejected",
        user_id: current_user.id, error: verification.error
      render_402_challenge
      return
    end

    mpp_payment = MppPayment.find_by!(challenge_id: verification.data[:challenge_id])
    mpp_payment.update!(
      status: :completed,
      tx_hash: verification.data[:tx_hash],
      user_id: current_user.id
    )

    log_info "mpp_authenticated_payment_verified",
      user_id: current_user.id,
      mpp_payment_id: mpp_payment.prefix_id,
      tx_hash: verification.data[:tx_hash]

    create_episode_via_mpp(mpp_payment, verification)
  end

  # ── Episode creation (authenticated + paid) ───────────────────────────

  def create_episode_via_mpp(mpp_payment, verification)
    result = Mpp::CreatesEpisode.call(user: current_user, params: episode_params)

    if result.success?
      log_info "mpp_episode_created",
        episode_id: result.data.prefix_id,
        mpp_payment_id: mpp_payment.prefix_id,
        user_id: current_user.id
      receipt = Mpp::GeneratesReceipt.call(tx_hash: verification.data[:tx_hash], mpp_payment: mpp_payment)
      response.headers["Payment-Receipt"] = receipt.data[:header_value]
      render json: { id: result.data.prefix_id }, status: :created
    else
      log_error "mpp_episode_creation_failed",
        mpp_payment_id: mpp_payment.prefix_id,
        user_id: current_user.id,
        error: result.error
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  # ── 402 Challenge response ────────────────────────────────────────────

  def render_402_challenge
    amount_cents = AppConfig::Mpp::PRICE_CENTS
    currency = AppConfig::Mpp::CURRENCY

    result = Mpp::ProvisionsChallenge.call(amount_cents: amount_cents, currency: currency)

    unless result.success?
      log_error "mpp_challenge_provisioning_failed", error: result.error
      render json: { error: "Payment provisioning failed: #{result.error}" },
        status: :service_unavailable
      return
    end

    challenge = result.data.challenge
    deposit_address = result.data.deposit_address

    log_info "mpp_challenge_issued",
      challenge_id: challenge[:id],
      amount_cents: amount_cents,
      currency: currency

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
