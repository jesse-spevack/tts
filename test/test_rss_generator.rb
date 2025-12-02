require "minitest/autorun"
require "rexml/document"
require_relative "../lib/rss_generator"

class TestRSSGenerator < Minitest::Test
  def setup
    @podcast_config = podcast_config
    @episodes = sample_episodes
  end

  def test_generates_valid_xml
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    assert_instance_of String, xml
    # Should parse as valid XML
    doc = REXML::Document.new(xml)
    refute_nil doc
  end

  def test_includes_rss_version_and_namespaces
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    rss = doc.root

    assert_equal "rss", rss.name
    assert_equal "2.0", rss.attributes["version"]
    assert_includes rss.attributes["xmlns:itunes"], "itunes.com"
  end

  def test_includes_podcast_level_metadata
    xml = generate_rss
    channel = parse_channel(xml)

    assert_equal "Test Podcast", channel.elements["title"].text
    assert_equal "A test podcast description", channel.elements["description"].text
    assert_equal "en-us", channel.elements["language"].text
    assert_equal "Test Author", channel.elements["itunes:author"].text
    assert_equal "false", channel.elements["itunes:explicit"].text
  end

  def test_includes_itunes_category
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    channel = doc.root.elements["channel"]
    category = channel.elements["itunes:category"]

    assert_equal "Technology", category.attributes["text"]
  end

  def test_includes_artwork_url_when_provided
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    channel = doc.root.elements["channel"]
    image = channel.elements["itunes:image"]

    assert_equal "https://example.com/artwork.jpg", image.attributes["href"]
  end

  def test_includes_episode_metadata
    xml = generate_rss
    item = parse_first_item(xml)

    assert_equal "First Episode", item.elements["title"].text
    assert_equal "First episode description", item.elements["description"].text
    assert_equal "Episode Author", item.elements["itunes:author"].text
    assert_equal "20251026-100000-first-episode", item.elements["guid"].text
    assert_equal "false", item.elements["guid"].attributes["isPermaLink"]
  end

  def test_includes_enclosure_with_correct_attributes
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    item = doc.root.elements["channel/item[1]"]
    enclosure = item.elements["enclosure"]

    assert_equal "https://storage.googleapis.com/bucket/episodes/episode1.mp3", enclosure.attributes["url"]
    assert_equal "5000000", enclosure.attributes["length"]
    assert_equal "audio/mpeg", enclosure.attributes["type"]
  end

  def test_formats_pubdate_in_rfc822
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    item = doc.root.elements["channel/item[1]"]
    pubdate = item.elements["pubDate"].text

    # RFC 822 format: "Day, DD Mon YYYY HH:MM:SS +0000"
    assert_match(/\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}/, pubdate)
  end

  def test_includes_itunes_duration_when_provided
    episodes_with_duration = [
      {
        "title" => "Episode With Duration",
        "description" => "Description",
        "mp3_url" => "https://example.com/episode.mp3",
        "file_size_bytes" => 1_000_000,
        "published_at" => "2025-10-26T10:00:00Z",
        "guid" => "test-guid",
        "duration_seconds" => 754
      }
    ]

    generator = RSSGenerator.new(@podcast_config, episodes_with_duration)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    item = doc.root.elements["channel/item[1]"]
    duration = item.elements["itunes:duration"]

    assert_equal "12:34", duration.text
  end

  def test_uses_podcast_author_when_episode_author_missing
    episodes_without_author = [
      {
        "title" => "Episode Without Author",
        "description" => "Description",
        "mp3_url" => "https://example.com/episode.mp3",
        "file_size_bytes" => 1_000_000,
        "published_at" => "2025-10-26T10:00:00Z",
        "guid" => "test-guid"
      }
    ]

    generator = RSSGenerator.new(@podcast_config, episodes_without_author)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    item = doc.root.elements["channel/item[1]"]

    # Should fall back to podcast author
    assert_equal "Test Author", item.elements["itunes:author"].text
  end

  private

  def generate_rss
    generator = RSSGenerator.new(@podcast_config, @episodes)
    generator.generate
  end

  def parse_channel(xml)
    doc = REXML::Document.new(xml)
    doc.root.elements["channel"]
  end

  def parse_first_item(xml)
    doc = REXML::Document.new(xml)
    doc.root.elements["channel/item[1]"]
  end

  def podcast_config
    {
      "title" => "Test Podcast",
      "description" => "A test podcast description",
      "author" => "Test Author",
      "language" => "en-us",
      "category" => "Technology",
      "explicit" => false,
      "artwork_url" => "https://example.com/artwork.jpg"
    }
  end

  def sample_episodes
    [
      {
        "title" => "First Episode",
        "description" => "First episode description",
        "author" => "Episode Author",
        "mp3_url" => "https://storage.googleapis.com/bucket/episodes/episode1.mp3",
        "file_size_bytes" => 5_000_000,
        "published_at" => "2025-10-26T10:00:00Z",
        "guid" => "20251026-100000-first-episode"
      },
      {
        "title" => "Second Episode",
        "description" => "Second episode description",
        "mp3_url" => "https://storage.googleapis.com/bucket/episodes/episode2.mp3",
        "file_size_bytes" => 3_000_000,
        "published_at" => "2025-10-27T14:30:00Z",
        "guid" => "20251027-143000-second-episode"
      }
    ]
  end
end
