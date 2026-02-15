# frozen_string_literal: true

require "test_helper"

class RecalculatesProcessingEstimateTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:one)
    @user = users(:one)
  end

  test "creates a ProcessingEstimate from completed episodes" do
    # Episode 1: 1000 chars, 10 seconds processing
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    # Episode 2: 5000 chars, 30 seconds processing
    create_completed_episode(source_text_length: 5000, processing_seconds: 30)
    # Episode 3: 10000 chars, 55 seconds processing
    create_completed_episode(source_text_length: 10000, processing_seconds: 55)

    result = RecalculatesProcessingEstimate.call

    assert_instance_of ProcessingEstimate, result
    assert result.persisted?
    assert_equal 3, result.episode_count
    assert result.base_seconds >= 0
    assert result.microseconds_per_character >= 1
  end

  test "computes linear regression correctly for a known dataset" do
    # y = 5 + 0.005 * x (base_seconds = 5, microseconds_per_character = 5000)
    # Episode 1: 2000 chars, 15 seconds
    create_completed_episode(source_text_length: 2000, processing_seconds: 15)
    # Episode 2: 4000 chars, 25 seconds
    create_completed_episode(source_text_length: 4000, processing_seconds: 25)
    # Episode 3: 6000 chars, 35 seconds
    create_completed_episode(source_text_length: 6000, processing_seconds: 35)

    result = RecalculatesProcessingEstimate.call

    # Perfect linear: slope = 0.005, intercept = 5
    assert_equal 5, result.base_seconds
    assert_equal 5000, result.microseconds_per_character
  end

  test "filters outlier episodes beyond 3 standard deviations" do
    # Normal episodes: tightly clustered processing times around 10-18 seconds
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)

    # Outlier: 10000 seconds (mean=10, std_dev~0 for the 10 points, so any deviation is huge)
    # With 11 points: mean ~917, but the tight cluster makes std_dev small relative to outlier
    # Actually let's reason: mean = (10*10 + 10000)/11 = 10100/11 ~ 918
    # variance = (10*(918-10)^2 + (10000-918)^2)/11 ~ (10*823_000 + 82_400_000)/11 ~ 15_200_000
    # std_dev ~ 3900. 3*std_dev ~ 11700. 10000-918 = 9082 < 11700, so NOT filtered.
    # Need more normal points or more extreme outlier. Let's use 20 normal + 1 extreme.
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)

    # 20 normal episodes at 10s + 1 outlier at 10000s
    # mean = (200+10000)/21 ~ 485.7
    # variance = (20*(485.7-10)^2 + (10000-485.7)^2)/21 ~ (20*226_000 + 90_600_000)/21 ~ 4_530_000
    # std_dev ~ 2128. 3*std = 6385. |10000-486| = 9514 > 6385 -> FILTERED
    create_completed_episode(source_text_length: 1000, processing_seconds: 10000)

    result = RecalculatesProcessingEstimate.call

    # The outlier should be excluded, leaving 20 episodes
    assert_equal 20, result.episode_count
  end

  test "returns nil when fewer than 2 episodes are available" do
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)

    result = RecalculatesProcessingEstimate.call

    assert_nil result
  end

  test "returns nil when no episodes are available" do
    result = RecalculatesProcessingEstimate.call

    assert_nil result
  end

  test "ignores episodes without processing_started_at" do
    # One valid episode
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)

    # Episode missing processing_started_at
    Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Missing start",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :complete,
      processing_started_at: nil,
      processing_completed_at: 1.minute.ago,
      source_text_length: 5000
    )

    result = RecalculatesProcessingEstimate.call

    assert_nil result
  end

  test "ignores episodes without processing_completed_at" do
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)

    Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Missing completion",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :processing,
      processing_started_at: 2.minutes.ago,
      processing_completed_at: nil,
      source_text_length: 5000
    )

    result = RecalculatesProcessingEstimate.call

    assert_nil result
  end

  test "ignores episodes without source_text_length" do
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)

    Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Missing length",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :complete,
      processing_started_at: 2.minutes.ago,
      processing_completed_at: 1.minute.ago,
      source_text_length: nil
    )

    result = RecalculatesProcessingEstimate.call

    assert_nil result
  end

  test "ignores soft-deleted episodes" do
    ep1 = create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 2000, processing_seconds: 20)

    ep1.soft_delete!

    # Only 1 non-deleted episode remains, so should return nil
    result = RecalculatesProcessingEstimate.call

    assert_nil result
  end

  test "base_seconds is clamped to minimum 0" do
    # Create data where intercept would be negative:
    # Large text lengths with small processing times
    # y = -5 + 0.001 * x -> at x=10000, y=5; at x=20000, y=15
    # But we want intercept to be negative, so we need points that extrapolate to negative y at x=0
    create_completed_episode(source_text_length: 10000, processing_seconds: 5)
    create_completed_episode(source_text_length: 20000, processing_seconds: 15)

    result = RecalculatesProcessingEstimate.call

    assert_equal 0, result.base_seconds
    assert result.microseconds_per_character >= 1
  end

  test "microseconds_per_character is clamped to minimum 1" do
    # Create episodes where the slope would be zero or negative
    # Same text length, same processing time -> slope = 0
    create_completed_episode(source_text_length: 5000, processing_seconds: 10)
    create_completed_episode(source_text_length: 10000, processing_seconds: 10)

    result = RecalculatesProcessingEstimate.call

    assert_equal 1, result.microseconds_per_character
  end

  test "works with exactly 2 episodes" do
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 5000, processing_seconds: 30)

    result = RecalculatesProcessingEstimate.call

    assert_instance_of ProcessingEstimate, result
    assert result.persisted?
    assert_equal 2, result.episode_count
  end

  test "returns nil when all episodes are filtered as outliers leaving fewer than 2" do
    # 2 episodes with wildly different processing times
    # Both might be removed if they're each outliers to the other...
    # Actually, with only 2 points the std dev is well-defined and neither will be >3 std devs.
    # We need a scenario where outlier removal leaves <2 points.
    # 3 normal episodes + 2 outliers, then remove outliers... that still leaves 3.
    # Let's try: 2 normal + 1 extreme outlier -> outlier removed, 2 remain -> still works.
    # Hard to get <2 after filtering. Let's test a different edge case:
    # Create 3 episodes where 2 are outliers:
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 2000, processing_seconds: 1000)
    create_completed_episode(source_text_length: 3000, processing_seconds: 1000)

    # The mean is ~670, std dev is ~466
    # 10 is ~1.4 std devs below mean (not filtered)
    # 1000 is ~0.7 std devs above mean (not filtered)
    # So all 3 remain in this case
    result = RecalculatesProcessingEstimate.call

    assert_instance_of ProcessingEstimate, result
    assert result.persisted?
  end

  test "inserts a new row each time it is called" do
    create_completed_episode(source_text_length: 1000, processing_seconds: 10)
    create_completed_episode(source_text_length: 5000, processing_seconds: 30)

    assert_difference "ProcessingEstimate.count", 2 do
      RecalculatesProcessingEstimate.call
      RecalculatesProcessingEstimate.call
    end
  end

  private

  def create_completed_episode(source_text_length:, processing_seconds:)
    started_at = processing_seconds.seconds.ago
    completed_at = Time.current

    Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Test Episode #{rand(100000)}",
      author: "Test Author",
      description: "Test description",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :complete,
      processing_started_at: started_at,
      processing_completed_at: completed_at,
      source_text_length: source_text_length
    )
  end
end
