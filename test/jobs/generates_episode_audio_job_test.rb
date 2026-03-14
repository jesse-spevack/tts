# frozen_string_literal: true

require "test_helper"

class GeneratesEpisodeAudioJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Mocktail::DSL

  setup do
    @episode = episodes(:one)
    @episode.update!(source_text: "Test content", status: :processing)
    @user = @episode.user
    Mocktail.replace(GeneratesEpisodeAudio)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Mocktail.reset
    Rails.cache = @original_cache
  end

  test "can be enqueued" do
    assert_enqueued_with(job: GeneratesEpisodeAudioJob) do
      GeneratesEpisodeAudioJob.perform_later(episode_id: @episode.id)
    end
  end

  test "calls GeneratesEpisodeAudio with episode" do
    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with { nil }

    GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)

    assert_equal 1, Mocktail.calls(GeneratesEpisodeAudio, :call).size
    call = Mocktail.calls(GeneratesEpisodeAudio, :call).first
    assert_equal @episode.id, call.kwargs[:episode].id
  end

  test "sets Current.action_id when provided" do
    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with { nil }

    GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id, action_id: "test-action-123")

    assert_equal "test-action-123", Current.action_id
  end

  # --- Retry behavior ---

  test "retries on transient Google Cloud error" do
    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with {
      raise Google::Cloud::DeadlineExceededError, "timeout"
    }

    assert_enqueued_with(job: GeneratesEpisodeAudioJob) do
      GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)
    end

    @episode.reload
    assert_equal "processing", @episode.status
  end

  test "retries on Faraday timeout" do
    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with {
      raise Faraday::TimeoutError, "connection timed out"
    }

    assert_enqueued_with(job: GeneratesEpisodeAudioJob) do
      GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)
    end
  end

  test "does not retry on permanent error" do
    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with {
      raise Google::Cloud::InvalidArgumentError, "bad voice"
    }

    assert_no_enqueued_jobs(only: GeneratesEpisodeAudioJob) do
      assert_raises(Google::Cloud::InvalidArgumentError) do
        GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)
      end
    end
  end

  # --- Retry exhaustion ---

  test "marks episode failed when retries exhausted" do
    job = GeneratesEpisodeAudioJob.new(episode_id: @episode.id)
    error = Google::Cloud::DeadlineExceededError.new("timeout")

    job.handle_retries_exhausted(error)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_match(/after retries/, @episode.error_message)
  end

  test "increments circuit breaker when retries exhausted" do
    job = GeneratesEpisodeAudioJob.new(episode_id: @episode.id)
    error = Google::Cloud::DeadlineExceededError.new("timeout")

    job.handle_retries_exhausted(error)

    count = Rails.cache.read("audio_failures:#{@user.id}")
    assert_equal 1, count
  end

  # --- Circuit breaker ---

  test "circuit breaker trips after threshold failures" do
    Rails.cache.write("audio_failures:#{@user.id}", 3, expires_in: 1.hour)

    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with { nil }

    GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_match(/temporarily unavailable/, @episode.error_message)
    assert_equal 0, Mocktail.calls(GeneratesEpisodeAudio, :call).size
  end

  test "circuit breaker allows synthesis below threshold" do
    Rails.cache.write("audio_failures:#{@user.id}", 2, expires_in: 1.hour)

    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with { nil }

    GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)

    assert_equal 1, Mocktail.calls(GeneratesEpisodeAudio, :call).size
  end

  test "circuit breaker resets on success" do
    Rails.cache.write("audio_failures:#{@user.id}", 2, expires_in: 1.hour)

    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with { nil }

    GeneratesEpisodeAudioJob.perform_now(episode_id: @episode.id)

    assert_nil Rails.cache.read("audio_failures:#{@user.id}")
  end
end
