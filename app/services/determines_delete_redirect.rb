# frozen_string_literal: true

class DeterminesDeleteRedirect
  def self.call(podcast:, episode:, current_page:)
    new(podcast: podcast, episode: episode, current_page: current_page).call
  end

  def initialize(podcast:, episode:, current_page:)
    @podcast = podcast
    @episode = episode
    @current_page = current_page.to_i
  end

  def call
    return Result.success(redirect_needed: false) if current_page <= 1

    remaining_count = podcast.episodes.where.not(id: episode.id).count
    last_valid_page = (remaining_count.to_f / items_per_page).ceil
    last_valid_page = 1 if last_valid_page < 1

    if current_page > last_valid_page
      Result.success(redirect_needed: true, redirect_page: last_valid_page)
    else
      Result.success(redirect_needed: false)
    end
  end

  private

  attr_reader :podcast, :episode, :current_page

  def items_per_page
    Pagy::DEFAULT[:limit]
  end
end
