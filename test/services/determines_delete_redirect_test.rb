# frozen_string_literal: true

require "test_helper"

class DeterminesDeleteRedirectTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:one)
    @episode = episodes(:one)
  end

  test "returns redirect_needed false when on page 1" do
    result = DeterminesDeleteRedirect.call(
      podcast: @podcast,
      episode: @episode,
      current_page: 1
    )

    assert result.success?
    assert_equal false, result.data[:redirect_needed]
  end

  test "returns redirect_needed false when current_page is nil" do
    result = DeterminesDeleteRedirect.call(
      podcast: @podcast,
      episode: @episode,
      current_page: nil
    )

    assert result.success?
    assert_equal false, result.data[:redirect_needed]
  end

  test "returns redirect_needed false when current_page is empty string" do
    result = DeterminesDeleteRedirect.call(
      podcast: @podcast,
      episode: @episode,
      current_page: ""
    )

    assert result.success?
    assert_equal false, result.data[:redirect_needed]
  end

  test "returns redirect_needed false when page will still have episodes after deletion" do
    # With 12 pagination episodes + 2 other episodes = 14 episodes for podcast one
    # Page 2 would have 4 episodes, deleting one leaves 3 - still valid
    result = DeterminesDeleteRedirect.call(
      podcast: @podcast,
      episode: episodes(:pagination_ep_11),
      current_page: 2
    )

    assert result.success?
    assert_equal false, result.data[:redirect_needed]
  end

  test "returns redirect_needed true when deleting last episode on page would leave page empty" do
    # Soft delete all but 1 episode to create scenario where only page 1 exists
    @podcast.episodes.where.not(id: @episode.id).update_all(deleted_at: Time.current)

    # Now we have 1 episode on page 1, check if we're on "page 2" (out of range)
    result = DeterminesDeleteRedirect.call(
      podcast: @podcast,
      episode: @episode,
      current_page: 2
    )

    assert result.success?
    assert_equal true, result.data[:redirect_needed]
    assert_equal 1, result.data[:redirect_page]
  end

  test "redirects to correct last page when multiple pages would remain" do
    # With 12 pagination episodes + 2 other episodes = 14 total
    # After deleting 1, we have 13 episodes = 2 pages (10 + 3)
    # If on page 5, should redirect to page 2
    result = DeterminesDeleteRedirect.call(
      podcast: @podcast,
      episode: @episode,
      current_page: 5
    )

    assert result.success?
    assert_equal true, result.data[:redirect_needed]
    assert_equal 2, result.data[:redirect_page]
  end
end
