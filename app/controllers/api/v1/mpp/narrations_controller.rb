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
      class NarrationsController < Api::V1::BaseController
        # The anonymous POST flow is the reason this controller opts out of
        # the bearer check. Step 5 of the MPP choreography links the
        # MppPayment to a user iff one is present — for narrations it stays
        # nil (that's the spec).
        skip_before_action :authenticate_token!

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
          result = ProcessesMppRequest.call(
            finalizer: ::Mpp::FinalizesNarration,
            user: nil,
            params: params,
            request: request
          )
          render_mpp_result(result)
        end
      end
    end
  end
end
