require "test_helper"

class EpisodeSourceTest < ActiveSupport::TestCase
  test "source_type defaults to file" do
    episode = Episode.new
    assert_equal "file", episode.source_type
  end

  test "source_type can be url" do
    episode = Episode.new(source_type: :url)
    assert episode.url?
    assert_not episode.file?
  end

  test "url source requires source_url" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Test Author",
      description: "Test description",
      source_type: :url,
      source_url: nil
    )
    assert_not episode.valid?
    assert_includes episode.errors[:source_url], "can't be blank"
  end

  test "url source with source_url is valid" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Test Author",
      description: "Test description",
      source_type: :url,
      source_url: "https://example.com/article"
    )
    assert episode.valid?
  end

  test "file source does not require source_url" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Test Author",
      description: "Test description",
      source_type: :file,
      source_text: "A" * 100
    )
    assert episode.valid?
  end
end
