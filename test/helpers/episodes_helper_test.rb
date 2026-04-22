require "test_helper"

class EpisodesHelperTest < ActionView::TestCase
  test "status_badge returns processing text without dot" do
    result = status_badge("processing")
    assert_includes result, "Processing"
    refute_includes result, "●"
  end

  test "status_dot returns pulse animation for processing" do
    result = status_dot("processing")
    assert_includes result, "animate-pulse"
    assert_includes result, "bg-yellow-500"
  end

  test "status_dot returns simple dot for other statuses" do
    result = status_dot("complete")
    assert_includes result, "bg-green-500"
    assert_includes result, "rounded-full"
    refute_includes result, "animate-ping"
  end

  test "status_badge returns completed badge with checkmark" do
    result = status_badge("complete")
    assert_includes result, "Completed"
    assert_includes result, "✓"
    assert_includes result, "text-green-600"
  end

  test "status_badge returns failed badge with X" do
    result = status_badge("failed")
    assert_includes result, "Failed"
    assert_includes result, "✗"
    assert_includes result, "text-red-600"
  end

  test "status_badge returns preparing text" do
    result = status_badge("preparing")
    assert_includes result, "Preparing"
  end

  test "status_dot returns pulse animation for preparing" do
    result = status_dot("preparing")
    assert_includes result, "animate-pulse"
    assert_includes result, "bg-yellow-500"
  end

  test "status_badge returns pending badge" do
    result = status_badge("pending")
    assert_includes result, "Pending"
    assert_includes result, "text-yellow-500"
  end

  test "format_duration formats seconds as MM:SS" do
    assert_equal "12:34", format_duration(754)
    assert_equal "0:05", format_duration(5)
    assert_equal "60:00", format_duration(3600)
  end

  test "format_duration returns nil for nil input" do
    assert_nil format_duration(nil)
  end

  test "processing_eta returns estimated seconds for episode with source_text_length" do
    episode = Episode.new(source_text_length: 10_000)
    result = processing_eta(episode)
    assert_kind_of Integer, result
    assert result > 0
  end

  test "processing_eta returns nil when source_text_length is nil" do
    episode = Episode.new(source_text_length: nil)
    assert_nil processing_eta(episode)
  end

  # --- episode_cost_label (agent-team-gafe) ----------------------------------
  #
  # Branches by account state + Episode#cost (backed by credit_cost column):
  #   - complimentary / unlimited           → "Included"
  #   - credit_cost IS NULL (URL deferred)  → "Checking credit cost..."
  #   - credit_cost == 0 (free tier)        → "Free tier episode"
  #   - credit_cost > 0                     → "1 credit" / "2 credits"

  test "episode_cost_label returns 'Checking credit cost...' for deferred URL episode" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "Pending URL", author: "Author",
      description: "desc", source_type: :url,
      source_url: "https://example.com/article", status: :preparing
    )
    # credit_cost defaults to NULL on a fresh URL episode pre-extract.
    assert_nil episode.credit_cost

    assert_equal "Checking credit cost...", episode_cost_label(episode)
  end

  test "episode_cost_label returns 'Included' for unlimited user regardless of credit_cost" do
    unlimited = users(:unlimited_user)
    episode = unlimited.primary_podcast.episodes.create!(
      user: unlimited, title: "Whatever", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 120, status: :complete, credit_cost: 0
    )

    assert_equal "Included", episode_cost_label(episode)
  end
end
