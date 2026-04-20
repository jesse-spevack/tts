# frozen_string_literal: true

module Api
  module Internal
    # Web-only cost preview endpoint (agent-team-gq88). Session-authenticated
    # (cookie-based), used by the Stimulus cost_preview_controller on the
    # new-episode form to reactively show "This will cost N credits" as the
    # user types, switches voice, or picks a file.
    #
    # NOT the same as Api::Internal::EpisodesController, which handles the
    # generator service's PATCH callback with X-Generator-Secret header auth.
    # Different auth model → different controller.
    class CostPreviewController < ApplicationController
      # Session-authenticated JSON endpoint called by same-origin JS. Rails'
      # default CSRF protection is driven by the session cookie being
      # presented — skipping forgery protection here keeps fetch() calls from
      # the Stimulus controller simple (no token wiring) while still
      # requiring a valid signed session cookie.
      skip_forgery_protection

      ALLOWED_SOURCE_TYPES = %w[paste url upload].freeze

      def create
        source_type = params[:source_type].to_s
        return render_invalid unless ALLOWED_SOURCE_TYPES.include?(source_type)
        return render_invalid unless required_field_present?(source_type)

        voice = ResolvesVoice.call(requested_key: nil, user: Current.user).data

        if credit_user_path?(Current.user)
          render json: credit_user_payload(source_type: source_type, voice: voice)
        else
          render json: free_tier_payload(voice: voice)
        end
      end

      private

      # A user is on the credit path if they have a credit_balance record
      # (even at zero). Complimentary and unlimited account types always
      # bypass, regardless of prior credit history. Free users (standard
      # account, no subscription, never purchased credits) have no balance
      # row and receive the free_tier marker.
      def credit_user_path?(user)
        return false if user.complimentary? || user.unlimited?
        user.credit_balance.present?
      end

      def required_field_present?(source_type)
        case source_type
        when "paste"  then params[:text].present?
        when "url"    then params[:url].present?
        when "upload" then params[:upload_length].present?
        end
      end

      def credit_user_payload(source_type:, voice:)
        length = length_for(source_type: source_type)
        cost = CalculatesEpisodeCreditCost.call(source_text_length: length, voice: voice)
        balance = Current.user.credits_remaining

        {
          cost: cost,
          balance: balance,
          sufficient: balance >= cost,
          voice_tier: voice.tier.to_s
        }
      end

      def free_tier_payload(voice:)
        {
          free_tier: true,
          cost: 0,
          voice_tier: voice.tier.to_s
        }
      end

      def length_for(source_type:)
        case source_type
        when "paste"  then params[:text].to_s.length
        when "url"    then 1
        when "upload" then params[:upload_length].to_i
        end
      end

      def render_invalid
        render json: { error: "invalid_request" }, status: :unprocessable_entity
      end

      # Override Authentication#request_authentication so JSON callers get a
      # proper 401 instead of a 302 redirect to /login.
      def request_authentication
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
