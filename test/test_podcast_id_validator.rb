# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/podcast_id_validator"

class TestPodcastIdValidator < Minitest::Test
  def test_valid_podcast_id
    valid_id = "podcast_a1b2c3d4e5f6a7b8"
    assert PodcastIdValidator.valid?(valid_id)
    assert_silent { PodcastIdValidator.validate!(valid_id) }
  end

  def test_valid_with_all_hex_chars
    valid_id = "podcast_0123456789abcdef"
    assert PodcastIdValidator.valid?(valid_id)
  end

  def test_invalid_too_short
    invalid_id = "podcast_abc123"
    refute PodcastIdValidator.valid?(invalid_id)

    error = assert_raises(ArgumentError) { PodcastIdValidator.validate!(invalid_id) }
    assert_match(/Invalid podcast_id format/, error.message)
    assert_match(/podcast_abc123/, error.message)
  end

  def test_invalid_too_long
    invalid_id = "podcast_a1b2c3d4e5f6a7b8extra"
    refute PodcastIdValidator.valid?(invalid_id)
  end

  def test_invalid_wrong_prefix
    invalid_id = "pod_a1b2c3d4e5f6a7b8"
    refute PodcastIdValidator.valid?(invalid_id)
  end

  def test_invalid_uppercase_hex
    invalid_id = "podcast_A1B2C3D4E5F6A7B8"
    refute PodcastIdValidator.valid?(invalid_id)
  end

  def test_invalid_non_hex_chars
    invalid_id = "podcast_g1h2i3j4k5l6m7n8"
    refute PodcastIdValidator.valid?(invalid_id)
  end

  def test_invalid_nil
    refute PodcastIdValidator.valid?(nil)

    error = assert_raises(ArgumentError) { PodcastIdValidator.validate!(nil) }
    assert_match(/Invalid podcast_id format/, error.message)
  end

  def test_invalid_empty_string
    refute PodcastIdValidator.valid?("")
  end

  def test_error_message_includes_example
    error = assert_raises(ArgumentError) { PodcastIdValidator.validate!("invalid") }
    assert_match(/podcast_a1b2c3d4e5f6a7b8/, error.message)
    assert_match(/openssl rand -hex 8/, error.message)
  end
end
