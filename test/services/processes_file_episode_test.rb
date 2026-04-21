# frozen_string_literal: true

require "test_helper"

class ProcessesFileEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @long_content = "# Test Header\n\n" + ("Some **bold** content here. " * 9) + "Some **bold** content here."
    @episode.update!(
      source_type: :file,
      source_text: @long_content,
      title: "Test Title",
      author: "Test Author"
    )

    Mocktail.replace(SubmitsEpisodeForProcessing)
  end

  test "strips markdown and submits for processing" do
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any, voice_override: m.any) }.with { nil }

    ProcessesFileEpisode.call(episode: @episode)

    calls = Mocktail.calls(SubmitsEpisodeForProcessing, :call)
    assert_equal 1, calls.size
    expected_plain = "Test Header\n\n" + ("Some bold content here. " * 9) + "Some bold content here."
    assert_equal expected_plain, calls.first.kwargs[:content]
  end

  test "marks episode as failed on error" do
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any, voice_override: m.any) }.with { raise StandardError, "Upload failed" }

    ProcessesFileEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Upload failed", @episode.error_message
  end

  # === Credit refund on file-path failure (agent-team-uoqd round 2) ===
  #
  # File episodes debit at CreatesEpisode#call. ProcessesFileEpisode is
  # the thinnest of the four processors — no LLM, no character limit
  # (that's enforced at the Episode model via content_within_tier_limit).
  # When SubmitsEpisodeForProcessing raises, fail_episode must refund.

  test "refunds debited credit when file episode fails during submission" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)

    episode = Episode.create!(
      podcast: podcasts(:one),
      user: credit_user,
      title: "Test Title",
      author: "Test Author",
      description: "Test description",
      source_type: :file,
      source_text: @long_content,
      status: :processing
    )

    DeductsCredit.call(user: credit_user, episode: episode, cost_in_credits: 1)
    assert_equal 2, credit_user.reload.credits_remaining

    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any, voice_override: m.any) }.with {
      raise StandardError, "Upload failed"
    }

    ProcessesFileEpisode.call(episode: episode)

    episode.reload
    assert_equal "failed", episode.status
    assert_equal 3, credit_user.reload.credits_remaining,
      "Credit should be refunded when file episode fails after debit"
  end
end
