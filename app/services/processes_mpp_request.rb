# frozen_string_literal: true

# Orchestrates the six-step MPP (Machine Payment Protocol) payment flow
# for creating a Narration (anonymous) or Episode (authenticated). Single
# source of truth for the choreography that used to live duplicated in
# Api::V1::Mpp::NarrationsController#create and ::EpisodesController#create.
#
# Steps:
#
#   1. Resolve voice BEFORE touching the Payment header. Invalid voice is
#      always 422, regardless of payment state — otherwise a caller with a
#      good credential but bad voice loops on 402.
#   2. Extract Payment credential. Missing → 402 challenge.
#   3. Verify credential. Any failure → fresh 402 challenge.
#   4. Tier-mismatch check. Credential tier != request tier → fresh 402.
#   5. Finalize: atomic pending→completed MppPayment flip + record creation
#      via the finalizer (::Mpp::FinalizesNarration or ::Mpp::FinalizesEpisode).
#   6. Emit Payment-Receipt header + 201 (or 409 for Episode losers).
#
# Returns a Result whose .data is a Result::Outcome carrying:
#
#   outcome: Symbol — :invalid_voice | :challenge_issued |
#                     :challenge_provisioning_failed | :created |
#                     :loser_conflict | :creation_failed
#   record:          the Narration or Episode (when :created), else nil
#   challenge:       challenge Hash (for :challenge_issued)
#   deposit_address: deposit String (for :challenge_issued)
#   amount_cents:    Integer (for :challenge_issued — needed in body)
#   voice_tier:      Symbol (for :challenge_issued — logged)
#   receipt_header:  String (for :created — Payment-Receipt value)
#   error:           String (for :creation_failed, :challenge_provisioning_failed)
#
# Controller renders via Api::V1::BaseController#render_mpp_result.
class ProcessesMppRequest
  include StructuredLogging

  Outcome = Data.define(
    :outcome,
    :record,
    :challenge,
    :deposit_address,
    :amount_cents,
    :voice_tier,
    :receipt_header,
    :error
  )

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(finalizer:, user:, params:, request:)
    @finalizer = finalizer
    @user = user
    @params = params
    @request = request
  end

  def call
    # Step 1: voice resolution.
    voice_result = ResolvesVoice.call(requested_key: params[:voice], user: user)
    return invalid_voice(params[:voice]) if voice_result.failure?

    voice = voice_result.data
    amount_cents = voice.price_cents
    voice_tier = voice.tier

    # Step 2: no credential → 402.
    credential = extract_payment_credential
    return challenge_response(amount_cents: amount_cents, voice_tier: voice_tier) if credential.blank?

    # Step 3: verify credential. Any failure → 402.
    verification = ::Mpp::VerifiesCredential.call(credential: credential)
    unless verification.success?
      log_warn payment_rejected_event, user_id: user&.id, error: verification.error
      return challenge_response(amount_cents: amount_cents, voice_tier: voice_tier)
    end

    # Step 4: tier-mismatch check.
    credential_tier = verification.data[:voice_tier]
    if credential_tier.present? && credential_tier != voice_tier
      log_warn "mpp_tier_mismatch",
        user_id: user&.id,
        credential_tier: credential_tier,
        request_tier: voice_tier
      return challenge_response(amount_cents: amount_cents, voice_tier: voice_tier)
    end

    # Step 5: finalize (atomic flip + create).
    mpp_payment = MppPayment.find_by!(challenge_id: verification.data[:challenge_id])
    result = call_finalizer(
      voice: voice,
      mpp_payment: mpp_payment,
      tx_hash: verification.data[:tx_hash]
    )

    unless result.success?
      log_error creation_failed_event,
        user_id: user&.id,
        mpp_payment_id: mpp_payment.prefix_id,
        error: result.error
      return outcome(:creation_failed, error: result.error)
    end

    record = result.data[record_key]
    outcome_symbol = result.data[:outcome]

    # Episode loser path: no record available → 409 Conflict. Narration
    # loser path returns the winner's record → 201 (idempotent retry).
    if outcome_symbol == :loser && record.nil?
      log_warn "mpp_authenticated_payment_double_spend_blocked",
        user_id: user&.id,
        mpp_payment_id: mpp_payment.prefix_id,
        tx_hash: verification.data[:tx_hash]
      return outcome(:loser_conflict)
    end

    log_info payment_verified_event,
      user_id: user&.id,
      mpp_payment_id: mpp_payment.prefix_id,
      tx_hash: verification.data[:tx_hash],
      outcome: outcome_symbol

    log_info record_created_event(record),
      user_id: user&.id,
      record_id: record.prefix_id,
      mpp_payment_id: mpp_payment.prefix_id,
      outcome: outcome_symbol

    # Step 6: emit Payment-Receipt.
    receipt = ::Mpp::GeneratesReceipt.call(
      tx_hash: verification.data[:tx_hash],
      mpp_payment: mpp_payment
    )

    outcome(:created, record: record, receipt_header: receipt.data[:header_value])
  end

  private

  attr_reader :finalizer, :user, :params, :request

  # Parse "Payment <credential>" from Authorization. RFC 9110 permits
  # multiple auth schemes comma-separated; we only care about Payment.
  def extract_payment_credential
    header = request.headers["Authorization"]
    return nil if header.blank?

    header.split(",").each do |part|
      part = part.strip
      return part.split(" ", 2).last if part.start_with?("Payment ")
    end
    nil
  end

  # Dispatch to the right finalizer with the right kwargs. Narration and
  # Episode finalizers have different signatures by design — keep them
  # separate and let this service pick.
  def call_finalizer(voice:, mpp_payment:, tx_hash:)
    if narration_flow?
      # CreatesNarration uses params[:voice] to look up the google voice
      # itself. Pass the RESOLVED voice key (not the raw request param)
      # so default-voice callers don't land on the Premium Chirp3-HD
      # fallback inside Voice.google_voice_for while only paying Standard.
      finalizer.call(
        mpp_payment: mpp_payment,
        tx_hash: tx_hash,
        params: permitted_params.merge(voice: voice.key)
      )
    else
      # CreatesEpisode takes voice_override as a pre-resolved google
      # voice string. Translating key → google_voice here (once) so
      # the job doesn't need to know Voice.google_voice_for.
      google_voice = Voice.google_voice_for(voice.key, is_premium: voice.tier == :premium)

      finalizer.call(
        user: user,
        mpp_payment: mpp_payment,
        tx_hash: tx_hash,
        params: permitted_params,
        voice_override: google_voice
      )
    end
  end

  PERMITTED_PARAMS = %i[title author description content text url voice source_type].freeze

  def permitted_params
    if params.respond_to?(:permit)
      params.permit(*PERMITTED_PARAMS)
    else
      ActionController::Parameters.new(params.to_h).permit(*PERMITTED_PARAMS)
    end
  end

  def challenge_response(amount_cents:, voice_tier:)
    currency = AppConfig::Mpp::CURRENCY

    result = ::Mpp::ProvisionsChallenge.call(
      amount_cents: amount_cents,
      currency: currency,
      voice_tier: voice_tier
    )

    unless result.success?
      log_error "mpp_challenge_provisioning_failed", error: result.error
      return outcome(:challenge_provisioning_failed, error: result.error)
    end

    challenge = result.data.challenge
    deposit_address = result.data.deposit_address

    log_info "mpp_challenge_issued",
      user_id: user&.id,
      challenge_id: challenge[:id],
      amount_cents: amount_cents,
      currency: currency,
      voice_tier: voice_tier

    outcome(
      :challenge_issued,
      challenge: challenge,
      deposit_address: deposit_address,
      amount_cents: amount_cents,
      voice_tier: voice_tier
    )
  end

  def invalid_voice(requested)
    outcome(:invalid_voice, error: "Invalid voice: #{requested}")
  end

  def outcome(symbol, **kwargs)
    Result.success(
      Outcome.new(
        outcome: symbol,
        record: kwargs[:record],
        challenge: kwargs[:challenge],
        deposit_address: kwargs[:deposit_address],
        amount_cents: kwargs[:amount_cents],
        voice_tier: kwargs[:voice_tier],
        receipt_header: kwargs[:receipt_header],
        error: kwargs[:error]
      )
    )
  end

  # --- Flow discriminators ------------------------------------------------

  def narration_flow?
    finalizer == ::Mpp::FinalizesNarration
  end

  def record_key
    narration_flow? ? :narration : :episode
  end

  # Log event names differ between anonymous and authenticated paths so
  # ops dashboards can filter. Preserve existing names byte-for-byte.
  def payment_rejected_event
    narration_flow? ? "mpp_anonymous_payment_rejected" : "mpp_authenticated_payment_rejected"
  end

  def payment_verified_event
    narration_flow? ? "mpp_anonymous_payment_verified" : "mpp_authenticated_payment_verified"
  end

  def creation_failed_event
    narration_flow? ? "mpp_narration_creation_failed" : "mpp_episode_creation_failed"
  end

  def record_created_event(_record)
    narration_flow? ? "mpp_narration_created" : "mpp_episode_created"
  end
end
