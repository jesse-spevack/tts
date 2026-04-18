# frozen_string_literal: true

module Mpp
  # Creates an Episode for an authenticated user paying via MPP.
  #
  # The user here is a bearer-authenticated user who hit their paywall
  # (subscription inactive, credits exhausted, free tier used) and is
  # paying via MPP to unlock this one episode. Keeping the user at the
  # service boundary makes the dependency explicit — the MppPayable
  # controller concern does not have to reason about current_user.
  class CreatesEpisode
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      podcast = GetsDefaultPodcastForUser.call(user: user)

      case params[:source_type]
      when "url"
        CreatesUrlEpisode.call(podcast: podcast, user: user, url: params[:url])
      when "text"
        CreatesPasteEpisode.call(
          podcast: podcast,
          user: user,
          text: params[:text],
          title: params[:title],
          author: params[:author]
        )
      when "extension"
        CreatesExtensionEpisode.call(
          podcast: podcast,
          user: user,
          title: params[:title],
          content: params[:content],
          url: params[:url],
          author: params[:author],
          description: params[:description]
        )
      else
        Result.failure("source_type is required. Use 'url', 'text', or 'extension'.")
      end
    end

    private

    attr_reader :user, :params
  end
end
