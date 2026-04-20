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
          result = ProcessesMppRequest.call(
            finalizer: ::Mpp::FinalizesEpisode,
            user: current_user,
            params: params,
            request: request
          )
          render_mpp_result(result)
        end
      end
    end
  end
end
