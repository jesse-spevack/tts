# frozen_string_literal: true

require "test_helper"

class Tts::ChunkedSynthesizerTest < ActiveSupport::TestCase
  # Stand-in for Tts::ApiClient. We don't use Mocktail here because
  # ChunkedSynthesizer runs chunks through Concurrent::FixedThreadPool, and
  # Mocktail stubbings live in Thread.current — worker threads can't see them.
  # A plain object avoids that trap.
  class FakeApiClient
    def initialize(&block)
      @block = block
    end

    def call(text:, voice:)
      @block.call(text, voice)
    end
  end

  # Long articles ALWAYS take the chunked path. When one chunk trips Google's
  # content filter, #process_chunk swallows the error and returns nil audio for
  # that chunk. #sum_billed_characters must skip those — we weren't billed for
  # characters Google refused to synthesize. This test covers that branch.
  test "billed_characters sums only successful chunks when content filter skips one" do
    config = Tts::Config.new

    successful_chunk = "x" * 30
    skipped_chunk    = "y" * 99
    chunks           = [ successful_chunk, skipped_chunk ]

    api_client = FakeApiClient.new do |text, _voice|
      if text == skipped_chunk
        raise StandardError, "Request triggered: #{Tts::Constants::CONTENT_FILTER_ERROR}"
      else
        "audio"
      end
    end

    synthesizer = Tts::ChunkedSynthesizer.new(api_client: api_client, config: config)
    synthesizer.synthesize(chunks, "en-GB-Chirp3-HD-Enceladus")

    # Only the 30-char chunk was actually synthesized; the 99-char chunk hit the
    # content filter and was skipped. Assert 30, NOT 129 — that's the whole point.
    assert_equal 30, synthesizer.billed_characters
  end
end
