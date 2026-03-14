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

  test "does not raise below threshold" do
    Rails.cache.write("audio_failures:#{@user.id}", 2, expires_in: 1.hour)

    assert_nothing_raised do
      ChecksAudioCircuitBreaker.check!(@user)
    end
  end

  test "raises Tripped at threshold" do
    Rails.cache.write("audio_failures:#{@user.id}", 3, expires_in: 1.hour)

    error = assert_raises(ChecksAudioCircuitBreaker::Tripped) do
      ChecksAudioCircuitBreaker.check!(@user)
    end
    assert_match(/temporarily unavailable/, error.message)
  end

  test "does not raise with no prior failures" do
    assert_nothing_raised do
      ChecksAudioCircuitBreaker.check!(@user)
    end
  end

  test "increment tracks failure count" do
    ChecksAudioCircuitBreaker.increment(@user)
    assert_equal 1, Rails.cache.read("audio_failures:#{@user.id}")

    ChecksAudioCircuitBreaker.increment(@user)
    assert_equal 2, Rails.cache.read("audio_failures:#{@user.id}")
  end

  test "reset clears failure count" do
    Rails.cache.write("audio_failures:#{@user.id}", 2, expires_in: 1.hour)

    ChecksAudioCircuitBreaker.reset(@user)

    assert_nil Rails.cache.read("audio_failures:#{@user.id}")
  end
end
