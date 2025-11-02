require "builder"
require "time"

class RSSGenerator
  # Initialize RSS generator with podcast config and episodes
  # @param podcast_config [Hash] Podcast-level metadata
  # @param episodes [Array] Array of episode hashes
  def initialize(podcast_config, episodes)
    @podcast_config = podcast_config
    @episodes = episodes
  end

  # Generate RSS 2.0 XML feed with iTunes tags
  # @return [String] RSS XML as string
  def generate
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

  def add_podcast_metadata(xml)
    xml.title @podcast_config["title"]
    xml.description @podcast_config["description"]
    xml.link @podcast_config["link"] if @podcast_config["link"]
    if @podcast_config["feed_url"]
      xml.tag! "atom:link", href: @podcast_config["feed_url"], rel: "self",
                            type: "application/rss+xml"
    end
    xml.language @podcast_config["language"]
    xml.tag! "itunes:author", @podcast_config["author"]
    xml.tag! "itunes:email", @podcast_config["email"] if @podcast_config["email"]
    xml.tag! "itunes:explicit", @podcast_config["explicit"].to_s
    xml.tag! "itunes:category", text: @podcast_config["category"]

    add_artwork(xml) if @podcast_config["artwork_url"]
  end

  def add_artwork(xml)
    xml.tag! "itunes:image", href: @podcast_config["artwork_url"]
  end

  def add_episodes(xml)
    @episodes.each do |episode|
      add_episode_item(xml, episode)
    end
  end

  def add_episode_item(xml, episode)
    xml.item do
      xml.title episode["title"]
      xml.description episode["description"]

      author = episode["author"] || @podcast_config["author"]
      xml.tag! "itunes:author", author

      xml.enclosure url: episode["mp3_url"],
                    type: "audio/mpeg",
                    length: episode["file_size_bytes"]

      xml.guid episode["guid"], isPermaLink: "false"

      pubdate = Time.parse(episode["published_at"])
      xml.pubDate pubdate.rfc2822
    end
  end
end
