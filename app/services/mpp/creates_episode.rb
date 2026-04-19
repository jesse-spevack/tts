# frozen_string_literal: true

module Mpp
  # Creates an Episode for an authenticated user paying via MPP.
  #
  # The user here is a bearer-authenticated user who hit their paywall
  # (subscription inactive, credits exhausted, free tier used) and is
  # paying via MPP to unlock this one episode. Keeping the user at the
  # service boundary makes the dependency explicit — the /mpp/episodes
  # controller does not have to reason about current_user plumbing.
  class CreatesEpisode
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, params:, voice_override: nil)
      @user = user
      @params = params
      @voice_override = voice_override
    end

    def call
      podcast = GetsDefaultPodcastForUser.call(user: user)

      case params[:source_type]
      when "url"
        CreatesUrlEpisode.call(
          podcast: podcast,
          user: user,
          url: params[:url],
          voice_override: voice_override
        )
      when "text"
        CreatesPasteEpisode.call(
          podcast: podcast,
          user: user,
          text: params[:text],
          title: params[:title],
          author: params[:author],
          voice_override: voice_override
        )
      when "extension"
        CreatesExtensionEpisode.call(
          podcast: podcast,
          user: user,
          title: params[:title],
          content: params[:content],
          url: params[:url],
          author: params[:author],
          description: params[:description],
          voice_override: voice_override
        )
      else
        Result.failure("source_type is required. Use 'url', 'text', or 'extension'.")
      end
    end

    private

    attr_reader :user, :params, :voice_override
  end
end
