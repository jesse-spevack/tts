# frozen_string_literal: true

require "test_helper"

class EpisodeSourceTypeTest < ActiveSupport::TestCase
  test "source_type includes paste" do
    assert_includes Episode.source_types.keys, "paste"
  end

  test "paste source_type has integer value 2" do
    assert_equal 2, Episode.source_types["paste"]
  end

  test "paste episode requires source_text" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: nil
    )

    assert_not episode.valid?
    assert_includes episode.errors[:source_text], "cannot be empty"
  end

  test "paste episode is valid with source_text" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: "A" * 100
    )

    assert episode.valid?
  end
end
