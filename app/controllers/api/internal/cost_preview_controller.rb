# frozen_string_literal: true

module Api
  module Internal
    # Web-only cost preview endpoint (agent-team-gq88). Session-authenticated
    # (cookie-based), used by the Stimulus cost_preview_controller on the
    # new-episode form to reactively show "This will cost N credits" as the
    # user types, switches voice, or picks a file.
    class CostPreviewController < ApplicationController
      # Session-authenticated JSON endpoint called by same-origin JS. The
      # Stimulus controller forwards the Rails CSRF token in the
      # X-CSRF-Token header, so standard forgery protection applies.

      ALLOWED_SOURCE_TYPES = %w[paste url upload].freeze

      def create
        # Defense-in-depth (agent-team-yx53): this endpoint returns per-user
        # balance data, so forbid any intermediary (CDN, proxy, browser
        # shared cache) from storing the response. Rails defaults are safe
        # for session-authed JSON today; this makes the contract explicit.
        response.set_header("Cache-Control", "private, no-store")

        source_type = params[:source_type].to_s
        return render_invalid unless ALLOWED_SOURCE_TYPES.include?(source_type)
        return render_invalid unless required_field_present?(source_type)

        voice = ResolvesVoice.call(requested_key: nil, user: Current.user).data

        if Current.user.on_credit_path?
          render json: credit_user_payload(source_type: source_type, voice: voice)
        else
          render json: free_tier_payload(voice: voice)
        end
      end

      private

      def required_field_present?(source_type)
        case source_type
        when "paste"  then params[:text].present?
        when "url"    then params[:url].present?
        when "upload" then params[:upload_length].present?
        end
      end

      def credit_user_payload(source_type:, voice:)
        cost = CalculatesAnticipatedEpisodeCost.call(
          EpisodeCostRequest.new(
            user: Current.user,
            source_type: source_type,
            text: params[:text],
            url: params[:url],
            source_text_length: source_type == "upload" ? params[:upload_length].to_i : nil
          )
        ).data
        balance = Current.user.credits_remaining

        # cost.credits is nil for URL previews — the client renders a
        # "cost shown after fetch" placeholder. Cost#sufficient_for? is true
        # for deferred so preview never blocks; the async job debits the
        # true cost and fails there if balance is short.
        {
          cost: cost.credits,
          balance: balance,
          sufficient: cost.sufficient_for?(balance),
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
