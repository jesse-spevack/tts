# frozen_string_literal: true

require "test_helper"

class GenerateAudioJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:pending)
    Mocktail.replace(GenerateEpisodeAudio)
  end

  test "calls GenerateEpisodeAudio service" do
    stubs { |m| GenerateEpisodeAudio.call(episode: m.any) }.with { nil }

    GenerateAudioJob.perform_now(@episode)

    assert_equal 1, Mocktail.calls(GenerateEpisodeAudio, :call).size
  end
end
