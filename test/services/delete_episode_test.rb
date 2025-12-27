# frozen_string_literal: true

require "test_helper"

class DeleteEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:complete)
    Mocktail.replace(CloudStorage)
    Mocktail.replace(GenerateRssFeed)
  end

  test "deletes MP3 from cloud storage" do
    mock_storage = Mocktail.of(CloudStorage)
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_storage }
    stubs { |m| mock_storage.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_storage.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    DeleteEpisode.call(episode: @episode)

    assert_equal 1, Mocktail.calls(mock_storage, :delete_file).size
  end

  test "regenerates RSS feed" do
    mock_storage = Mocktail.of(CloudStorage)
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_storage }
    stubs { |m| mock_storage.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_storage.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss>feed content</rss>" }

    DeleteEpisode.call(episode: @episode)

    assert_equal 1, Mocktail.calls(GenerateRssFeed, :call).size
    assert_equal 1, Mocktail.calls(mock_storage, :upload_content).size
  end

  test "skips MP3 deletion if no gcs_episode_id" do
    @episode.update!(gcs_episode_id: nil)

    mock_storage = Mocktail.of(CloudStorage)
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_storage }
    stubs { |m| mock_storage.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    DeleteEpisode.call(episode: @episode)

    assert_equal 0, Mocktail.calls(mock_storage, :delete_file).size
  end

  test "soft deletes episode by setting deleted_at" do
    @episode.update_column(:deleted_at, nil)
    assert_nil @episode.deleted_at

    mock_storage = Mocktail.of(CloudStorage)
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_storage }
    stubs { |m| mock_storage.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_storage.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    DeleteEpisode.call(episode: @episode)

    assert_not_nil Episode.unscoped.find(@episode.id).deleted_at
  end
end
