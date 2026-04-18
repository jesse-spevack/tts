# frozen_string_literal: true

module Mpp
  # Creates a Narration for an anonymous MPP caller and enqueues its
  # processing job. Narration is the ephemeral, userless audio output
  # used when there is no bearer-authenticated user — distinct from
  # the Episode path used by authenticated MPP callers.
  class CreatesNarration
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(mpp_payment:, params:)
      @mpp_payment = mpp_payment
      @params = params
    end

    def call
      narration = Narration.create!(
        mpp_payment: mpp_payment,
        title: params[:title] || "Untitled",
        author: params[:author],
        description: params[:description],
        source_url: params[:url],
        source_text: params[:content] || params[:text],
        source_type: source_type_for(params[:source_type]),
        expires_at: 24.hours.from_now
      )

      ProcessesNarrationJob.perform_later(narration_id: narration.id)

      Result.success(narration)
    end

    private

    attr_reader :mpp_payment, :params

    def source_type_for(type)
      case type
      when "url" then :url
      else :text
      end
    end
  end
end
