# frozen_string_literal: true

require "test_helper"

class ChecksAudioCircuitBreakerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "yields block when below threshold" do
    Rails.cache.write("audio_failures:#{@user.id}", 2, expires_in: 1.hour)

    called = false
    ChecksAudioCircuitBreaker.call(user: @user) { called = true }

    assert called
  end

  test "raises Tripped at threshold without yielding" do
    Rails.cache.write("audio_failures:#{@user.id}", 3, expires_in: 1.hour)

    called = false
    error = assert_raises(ChecksAudioCircuitBreaker::Tripped) do
      ChecksAudioCircuitBreaker.call(user: @user) { called = true }
    end

    refute called
    assert_match(/temporarily unavailable/, error.message)
  end

  test "resets failure count on successful block" do
    Rails.cache.write("audio_failures:#{@user.id}", 2, expires_in: 1.hour)

    ChecksAudioCircuitBreaker.call(user: @user) { "success" }

    assert_nil Rails.cache.read("audio_failures:#{@user.id}")
  end

  test "does not reset on block failure" do
    Rails.cache.write("audio_failures:#{@user.id}", 1, expires_in: 1.hour)

    assert_raises(StandardError) do
      ChecksAudioCircuitBreaker.call(user: @user) { raise StandardError, "boom" }
    end

    assert_equal 1, Rails.cache.read("audio_failures:#{@user.id}")
  end

  test "works with no prior failures" do
    called = false
    ChecksAudioCircuitBreaker.call(user: @user) { called = true }

    assert called
  end

  test "increment tracks failure count" do
    ChecksAudioCircuitBreaker.increment(@user)
    assert_equal 1, Rails.cache.read("audio_failures:#{@user.id}")

    ChecksAudioCircuitBreaker.increment(@user)
    assert_equal 2, Rails.cache.read("audio_failures:#{@user.id}")
  end
end
