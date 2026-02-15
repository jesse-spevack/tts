# frozen_string_literal: true

class FindsRecentlyChangedEpisodes
  DEFAULT_WINDOW = 30.seconds

  def self.call(podcast:, window: DEFAULT_WINDOW)
    new(podcast: podcast, window: window).call
  end

  def initialize(podcast:, window:)
    @podcast = podcast
    @window = window
  end

  def call
    podcast.episodes
      .includes(:podcast)
      .where(status: [ :pending, :preparing, :processing ])
      .or(podcast.episodes.where(updated_at: window.ago..))
  end

  private

  attr_reader :podcast, :window
end
