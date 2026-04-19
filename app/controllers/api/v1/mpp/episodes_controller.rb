# frozen_string_literal: true

module Api
  module V1
    module Mpp
      # Authenticated MPP episode endpoint.
      #
      # - POST /api/v1/mpp/episodes — bearer-authenticated-pay-to-create flow.
      #
      # Requires a Bearer token (Api::V1::BaseController#authenticate_token!
      # handles 401 if missing/invalid). Once authenticated, the caller either
      # provides a Payment credential whose challenge matches the resolved
      # voice's tier price, or they receive a 402 challenge.
      #
      # Mirror of Api::V1::Mpp::NarrationsController#create, but:
      #   1. Bearer required (Narrations is anonymous)
      #   2. Creates an Episode attached to the user's default podcast
      #      (GetsDefaultPodcastForUser) — not an ephemeral Narration
      #   3. MppPayment rows link to the user after completion
      #
      # NOTE on namespacing: Api::V1::Mpp::* shadows top-level ::Mpp::* for
      # constant lookup inside this class, so every reference to the top-level
      # MPP service module must use the ::Mpp:: prefix explicitly.
      class EpisodesController < Api::V1::BaseController
        def create
          # Step 1: resolve voice BEFORE touching the Payment header. A bad
          # voice is a 422 regardless of payment state — otherwise a client
          # holding a valid credential but sending a bad voice would loop
          # on 402 forever.
          voice_result = ResolvesVoice.call(requested_key: params[:voice], user: current_user)
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
            log_warn "mpp_authenticated_payment_rejected",
              user_id: current_user.id,
              error: verification.error
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
              user_id: current_user.id,
              credential_tier: credential_tier,
              request_tier: voice_tier
            render_402_challenge(amount_cents: amount_cents, voice_tier: voice_tier)
            return
          end

          # Step 5: mark the pending MppPayment completed AND link the user.
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

          # Step 6: create the Episode. The resolved voice's google_voice
          # string flows via voice_override into the processing job — this
          # is the sidecar path (Option A) that keeps Episode#voice delegation
          # to User#voice unchanged while still synthesizing the paid-for
          # voice. Translating key → google_voice happens here (once) so the
          # job doesn't need to know Voice.google_voice_for.
          google_voice = Voice.google_voice_for(voice.key, is_premium: voice.tier == :premium)

          result = ::Mpp::CreatesEpisode.call(
            user: current_user,
            params: episode_params,
            voice_override: google_voice
          )

          unless result.success?
            log_error "mpp_episode_creation_failed",
              user_id: current_user.id,
              mpp_payment_id: mpp_payment.prefix_id,
              error: result.error
            render json: { error: result.error }, status: :unprocessable_entity
            return
          end

          log_info "mpp_episode_created",
            user_id: current_user.id,
            episode_id: result.data.prefix_id,
            mpp_payment_id: mpp_payment.prefix_id

          # Step 7: emit Payment-Receipt header + unified 201 body.
          receipt = ::Mpp::GeneratesReceipt.call(
            tx_hash: verification.data[:tx_hash],
            mpp_payment: mpp_payment
          )
          response.headers["Payment-Receipt"] = receipt.data[:header_value]
          render json: { id: result.data.prefix_id }, status: :created
        end

        private

        def episode_params
          params.permit(:title, :author, :description, :content, :text, :url, :voice, :source_type)
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
            user_id: current_user&.id,
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
