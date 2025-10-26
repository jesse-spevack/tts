require "minitest/autorun"
require "rexml/document"
require_relative "../lib/rss_generator"

class TestRSSGenerator < Minitest::Test
  def setup
    @podcast_config = {
      "title" => "Test Podcast",
      "description" => "A test podcast description",
      "author" => "Test Author",
      "email" => "test@example.com",
      "language" => "en-us",
      "category" => "Technology",
      "explicit" => false,
      "artwork_url" => "https://example.com/artwork.jpg"
    }

    @episodes = [
      {
        "id" => "20251026-episode-1",
        "title" => "First Episode",
        "description" => "First episode description",
        "author" => "Episode Author",
        "mp3_url" => "https://storage.googleapis.com/bucket/episodes/episode1.mp3",
        "file_size_bytes" => 5000000,
        "published_at" => "2025-10-26T10:00:00Z",
        "guid" => "20251026-100000-first-episode"
      },
      {
        "id" => "20251027-episode-2",
        "title" => "Second Episode",
        "description" => "Second episode description",
        "mp3_url" => "https://storage.googleapis.com/bucket/episodes/episode2.mp3",
        "file_size_bytes" => 3000000,
        "published_at" => "2025-10-27T14:30:00Z",
        "guid" => "20251027-143000-second-episode"
      }
    ]
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
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    channel = doc.root.elements["channel"]

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

  def test_omits_artwork_when_not_provided
    config_without_artwork = @podcast_config.dup
    config_without_artwork.delete("artwork_url")

    generator = RSSGenerator.new(config_without_artwork, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    channel = doc.root.elements["channel"]
    image = channel.elements["itunes:image"]

    assert_nil image
  end

  def test_includes_all_episodes_as_items
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    items = doc.root.elements.to_a("channel/item")

    assert_equal 2, items.length
  end

  def test_includes_episode_metadata
    generator = RSSGenerator.new(@podcast_config, @episodes)
    xml = generator.generate

    doc = REXML::Document.new(xml)
    item = doc.root.elements["channel/item[1]"]

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

  def test_uses_podcast_author_when_episode_author_missing
    episodes_without_author = [
      {
        "title" => "Episode Without Author",
        "description" => "Description",
        "mp3_url" => "https://example.com/episode.mp3",
        "file_size_bytes" => 1000000,
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

  def test_handles_empty_episodes_array
    generator = RSSGenerator.new(@podcast_config, [])
    xml = generator.generate

    doc = REXML::Document.new(xml)
    items = doc.root.elements.to_a("channel/item")

    assert_equal 0, items.length
  end
end
