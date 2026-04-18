# frozen_string_literal: true

require "test_helper"

class Mpp::CreatesEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:default)
    @episode = episodes(:one)

    Mocktail.replace(GetsDefaultPodcastForUser)
    stubs { |m| GetsDefaultPodcastForUser.call(user: m.any) }.with { @podcast }
  end

  test "returns failure for missing source_type" do
    result = Mpp::CreatesEpisode.call(user: @user, params: {})

    refute result.success?
    assert_match(/source_type is required/, result.error)
  end

  test "returns failure for unknown source_type" do
    result = Mpp::CreatesEpisode.call(user: @user, params: { source_type: "bogus" })

    refute result.success?
    assert_match(/source_type is required/, result.error)
  end

  test "dispatches to CreatesUrlEpisode for url source_type" do
    Mocktail.replace(CreatesUrlEpisode)
    stubs { |_m| CreatesUrlEpisode.call(podcast: @podcast, user: @user, url: "https://example.com/article") }
      .with { Result.success(@episode) }

    result = Mpp::CreatesEpisode.call(
      user: @user,
      params: { source_type: "url", url: "https://example.com/article" }
    )

    assert result.success?
    assert_equal @episode, result.data
  end

  test "dispatches to CreatesPasteEpisode for text source_type" do
    Mocktail.replace(CreatesPasteEpisode)
    stubs { |_m|
      CreatesPasteEpisode.call(
        podcast: @podcast, user: @user, text: "Article body", title: "Title", author: "Author"
      )
    }.with { Result.success(@episode) }

    result = Mpp::CreatesEpisode.call(
      user: @user,
      params: { source_type: "text", text: "Article body", title: "Title", author: "Author" }
    )

    assert result.success?
  end

  test "dispatches to CreatesExtensionEpisode for extension source_type" do
    Mocktail.replace(CreatesExtensionEpisode)
    stubs { |_m|
      CreatesExtensionEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Title",
        content: "Content body",
        url: "https://example.com",
        author: "Author",
        description: "Description"
      )
    }.with { Result.success(@episode) }

    result = Mpp::CreatesEpisode.call(
      user: @user,
      params: {
        source_type: "extension",
        title: "Title",
        content: "Content body",
        url: "https://example.com",
        author: "Author",
        description: "Description"
      }
    )

    assert result.success?
  end
end
