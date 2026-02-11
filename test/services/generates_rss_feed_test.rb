# frozen_string_literal: true

require "test_helper"

class GeneratesRssFeedTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:default)
    @episode = episodes(:complete)
  end

  test "generates valid RSS XML with podcast metadata" do
    result = GeneratesRssFeed.call(podcast: @podcast)

    assert result.include?('<?xml version="1.0" encoding="UTF-8"?>')
    assert result.include?("<rss")
    assert result.include?("xmlns:itunes")
    assert result.include?("<title>PodRead Podcast</title>")
  end

  test "includes completed episodes in feed" do
    result = GeneratesRssFeed.call(podcast: @podcast)

    assert result.include?("<item>")
    assert result.include?("<title>#{@episode.title}</title>")
    assert result.include?("<enclosure")
  end

  test "excludes pending and failed episodes" do
    pending_episode = episodes(:pending)
    failed_episode = episodes(:failed)

    result = GeneratesRssFeed.call(podcast: @podcast)

    refute result.include?(pending_episode.title)
    refute result.include?(failed_episode.title)
  end

  test "excludes deleted episodes" do
    @episode.update!(deleted_at: Time.current)

    result = GeneratesRssFeed.call(podcast: @podcast)

    refute result.include?(@episode.title)
  end

  test "orders episodes by created_at descending" do
    older_episode = Episode.create!(
      podcast: @podcast,
      user: @episode.user,
      title: "Older Episode",
      author: "Test",
      description: "Older",
      source_type: :url,
      source_url: "https://example.com/older-article",
      status: :complete,
      gcs_episode_id: "older-episode",
      created_at: 1.day.ago
    )

    result = GeneratesRssFeed.call(podcast: @podcast)

    # Newer episode should appear first in the XML
    newer_pos = result.index(@episode.title)
    older_pos = result.index(older_episode.title)
    assert newer_pos < older_pos, "Newer episode should appear before older episode"
  end

  test "atom:link self references public feed URL" do
    result = GeneratesRssFeed.call(podcast: @podcast)

    expected_url = "https://example.com/feeds/#{@podcast.podcast_id}.xml"
    assert result.include?(%(href="#{expected_url}"))
    assert result.include?('rel="self"')
  end
end
