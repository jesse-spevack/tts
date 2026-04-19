# frozen_string_literal: true

module Api
  module V1
    module Mpp
      # Anonymous MPP narration endpoint.
      #
      # - GET  /api/v1/mpp/narrations/:id — public status + audio URL lookup
      # - POST /api/v1/mpp/narrations     — anonymous-pay-to-create flow
      #
      # The POST flow never authenticates a user. The caller either provides
      # a Payment credential (RFC 9110 auth scheme) whose challenge matches
      # the resolved voice's tier price, or they receive a 402 challenge.
      #
      # NOTE on namespacing: Api::V1::Mpp::* shadows top-level ::Mpp::* for
      # constant lookup inside this class, so every reference to the top-level
      # MPP service module must use the ::Mpp:: prefix explicitly.
      class NarrationsController < ActionController::API
        include StructuredLogging

        def show
          narration = Narration.find_by_prefix_id!(params[:id])

          if narration.expired?
            head :not_found
            return
          end

          response = {
            id: narration.prefix_id,
            status: narration.status,
            title: narration.title,
            author: narration.author,
            duration_seconds: narration.duration_seconds
          }

          if narration.complete?
            response[:audio_url] = GeneratesNarrationAudioUrl.call(narration)
          end

          render json: response
        rescue ActiveRecord::RecordNotFound
          head :not_found
        end

        def create
          # Step 1: resolve voice BEFORE touching the Payment header. A bad
          # voice is a 422 regardless of payment state — otherwise a client
          # holding a valid credential but sending a bad voice would loop
          # on 402 forever.
          voice_result = ResolvesVoice.call(requested_key: params[:voice], user: nil)
          if voice_result.failure?
            render json: { error: "Invalid voice: #{params[:voice]}" }, status: :unprocessable_entity
            return
          end

          voice = voice_result.data
          amount_cents = voice.price_cents
          voice_tier = voice.tier

          # Step 2: no credential → issue 402 challenge at the tier price.
          credential = extract_payment_credential
          if credential.blank?
            render_402_challenge(amount_cents: amount_cents, voice_tier: voice_tier)
            return
          end

          # Step 3: verify credential. Any failure → fresh 402 challenge.
          verification = ::Mpp::VerifiesCredential.call(credential: credential)
          unless verification.success?
            log_warn "mpp_anonymous_payment_rejected", error: verification.error
            render_402_challenge(amount_cents: amount_cents, voice_tier: voice_tier)
            return
          end

          # Step 4: tier-mismatch check. Attacker could buy a Standard
          # challenge and retry for a Premium voice. The HMAC-signed
          # request blob embeds voice_tier, so a mismatch here means the
          # credential was provisioned for a different tier than the
          # current request resolves to — re-challenge.
          credential_tier = verification.data[:voice_tier]
          if credential_tier.present? && credential_tier != voice_tier
            log_warn "mpp_tier_mismatch",
              credential_tier: credential_tier,
              request_tier: voice_tier
            render_402_challenge(amount_cents: amount_cents, voice_tier: voice_tier)
            return
          end

          # Step 5: atomically flip the pending MppPayment to completed AND
          # create the Narration via Mpp::FinalizesNarration. The service
          # serializes concurrent racers at the SQL layer (see
          # agent-team-kzq) so exactly one caller creates a Narration per
          # MppPayment — losers return the winner's Narration for
          # idempotent retry semantics.
          mpp_payment = MppPayment.find_by!(challenge_id: verification.data[:challenge_id])
          result = ::Mpp::FinalizesNarration.call(
            mpp_payment: mpp_payment,
            tx_hash: verification.data[:tx_hash],
            # Pass the resolved voice key explicitly (not the raw request
            # param) so default-voice callers don't land on the Premium
            # Chirp3-HD fallback inside Voice.google_voice_for while only
            # paying the Standard price.
            params: narration_params.merge(voice: voice.key)
          )

          unless result.success?
            log_error "mpp_narration_creation_failed",
              mpp_payment_id: mpp_payment.prefix_id,
              error: result.error
            render json: { error: result.error }, status: :unprocessable_entity
            return
          end

          narration = result.data[:narration]

          log_info "mpp_anonymous_payment_verified",
            mpp_payment_id: mpp_payment.prefix_id,
            tx_hash: verification.data[:tx_hash],
            outcome: result.data[:outcome]

          log_info "mpp_narration_created",
            narration_id: narration.prefix_id,
            mpp_payment_id: mpp_payment.prefix_id,
            outcome: result.data[:outcome]

          # Step 6: emit Payment-Receipt header + unified 201 body.
          # Loser branch still gets a receipt — the caller's payment DID
          # settle; the receipt just points at the already-created
          # Narration.
          receipt = ::Mpp::GeneratesReceipt.call(
            tx_hash: verification.data[:tx_hash],
            mpp_payment: mpp_payment
          )
          response.headers["Payment-Receipt"] = receipt.data[:header_value]
          render json: { id: narration.prefix_id }, status: :created
        end

        private

        def narration_params
          params.permit(:title, :author, :description, :content, :text, :url, :voice, :source_type)
        end

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

        def render_402_challenge(amount_cents:, voice_tier:)
          currency = AppConfig::Mpp::CURRENCY

          result = ::Mpp::ProvisionsChallenge.call(
            amount_cents: amount_cents,
            currency: currency,
            voice_tier: voice_tier
          )

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
            currency: currency,
            voice_tier: voice_tier

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
    end
  end
end
