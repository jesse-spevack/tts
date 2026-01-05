# frozen_string_literal: true

require "test_helper"

class GeneratesEpisodeAudioJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Mocktail::DSL

  setup do
    @episode = episodes(:one)
    @episode.update!(source_text: "Test content", status: :processing)
    Mocktail.replace(GeneratesEpisodeAudio)
  end

  teardown do
    Mocktail.reset
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
end
