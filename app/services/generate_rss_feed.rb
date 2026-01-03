# frozen_string_literal: true

require "builder"

class GenerateRssFeed
  PODCAST_DEFAULTS = {
    "title" => "Very normal podcast",
    "description" => "Readings turned to audio by text to speech app.",
    "author" => "Very Normal TTS",
    "email" => "noreply@tts.verynormal.dev",
    "link" => "https://tts.verynormal.dev",
    "language" => "en-us",
    "category" => "Technology",
    "explicit" => false,
    "artwork_url" => "https://verynormal.info/content/images/2022/11/verynormallogo2.png"
  }.freeze

  def self.call(podcast:)
    new(podcast: podcast).call
  end

  def initialize(podcast:)
    @podcast = podcast
  end

  def call
    xml = Builder::XmlMarkup.new(indent: 2)
    xml.instruct! :xml, version: "1.0", encoding: "UTF-8"

    xml.rss version: "2.0",
            "xmlns:itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd",
            "xmlns:content" => "http://purl.org/rss/1.0/modules/content/",
            "xmlns:atom" => "http://www.w3.org/2005/Atom" do
      xml.channel do
        add_podcast_metadata(xml)
        add_episodes(xml)
      end
    end

    xml.target!
  end

  private

  def podcast_config
    @podcast_config ||= PODCAST_DEFAULTS.merge(
      "title" => @podcast.title || PODCAST_DEFAULTS["title"],
      "description" => @podcast.description || PODCAST_DEFAULTS["description"],
      "feed_url" => feed_url
    )
  end

  def feed_url
    AppConfig::Storage.public_feed_url(@podcast.podcast_id)
  end

  def episodes
    @episodes ||= @podcast.episodes
                          .where(status: "complete")
                          .where(deleted_at: nil)
                          .order(created_at: :desc)
  end

  def add_podcast_metadata(xml)
    xml.title podcast_config["title"]
    xml.description podcast_config["description"]
    xml.link podcast_config["link"]
    if podcast_config["feed_url"]
      xml.tag! "atom:link", href: podcast_config["feed_url"], rel: "self", type: "application/rss+xml"
    end
    xml.language podcast_config["language"]
    xml.tag! "itunes:author", podcast_config["author"]
    xml.tag! "itunes:email", podcast_config["email"]
    xml.tag! "itunes:explicit", podcast_config["explicit"].to_s
    xml.tag! "itunes:category", text: podcast_config["category"]
    xml.tag! "itunes:image", href: podcast_config["artwork_url"]
  end

  def add_episodes(xml)
    episodes.each do |episode|
      add_episode_item(xml, episode)
    end
  end

  def add_episode_item(xml, episode)
    xml.item do
      xml.title episode.title
      xml.description episode.description
      xml.tag! "itunes:author", episode.author

      xml.enclosure url: episode_mp3_url(episode),
                    type: "audio/mpeg",
                    length: episode.audio_size_bytes || 0

      xml.guid episode.gcs_episode_id, isPermaLink: "false"
      xml.pubDate episode.created_at.rfc2822

      add_duration(xml, episode.duration_seconds)
    end
  end

  def episode_mp3_url(episode)
    AppConfig::Storage.episode_audio_url(@podcast.podcast_id, episode.gcs_episode_id)
  end

  def add_duration(xml, duration_seconds)
    return unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    xml.tag! "itunes:duration", format("%<min>d:%<sec>02d", min: minutes, sec: seconds)
  end
end
