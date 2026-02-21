# frozen_string_literal: true

class SearchesEpisodes
  def self.call(podcast:, query:)
    new(podcast: podcast, query: query).call
  end

  def initialize(podcast:, query:)
    @podcast = podcast
    @query = query
  end

  def call
    episodes = if query.blank?
      podcast.episodes.newest_first
    else
      sanitized = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      # NOTE: SQLite LIKE is case-insensitive for ASCII. On Postgres, change LIKE to ILIKE.
      podcast.episodes.newest_first.where(
        "title LIKE :term ESCAPE '\\' OR author LIKE :term ESCAPE '\\' OR source_url LIKE :term ESCAPE '\\' OR source_text LIKE :term ESCAPE '\\'",
        term: sanitized
      )
    end

    episodes
  end

  private

  attr_reader :podcast, :query
end
