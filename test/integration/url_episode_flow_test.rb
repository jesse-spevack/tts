# frozen_string_literal: true

require "test_helper"

# Full URL episode flow from form submission through async job completion,
# mirroring test/integration/paste_episode_flow_test.rb. Added for brick 3
# (agent-team-7i24) — the Researcher pass flagged that no URL-variant
# flow test existed, leaving a gap between the per-component tests
# (ProcessesUrlEpisode, CreatesUrlEpisode, EpisodesController) and the
# integration surface users actually hit.
#
# Covers:
#   1. Web form POST with source_type: "url" (EpisodesController#create)
#   2. ProcessesUrlEpisodeJob enqueued
#   3. Job runs ProcessesUrlEpisode → fetch → extract → deduct → LLM → submit
#   4. Correct debit for Premium + >20k article (2 credits) and for short
#      article (1 credit).
#
# The pre-check path (EpisodesController#anticipated_cost at
# controllers/episodes_controller.rb:138-145) currently calls
# CalculatesAnticipatedEpisodeCost with source_type: "url" and relies on
# the '→ 1' sentinel to return 1. Post-brick-3 that returns nil, and
# ChecksEpisodeCreationPermission#check_credit_balance (line 44) already
# handles nil by skipping the balance gate — verified by these tests.
class UrlEpisodeFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @credit_user = users(:credit_user)
    @credit_user.update!(voice_preference: "callum") # Premium
    CreditBalance.for(@credit_user).update!(balance: 3)
    CreatesDefaultPodcast.call(user: @credit_user) unless @credit_user.podcasts.any?
    sign_in_as(@credit_user)

    Mocktail.replace(FetchesUrl)
    Mocktail.replace(ProcessesWithLlm)
    Mocktail.replace(SubmitsEpisodeForProcessing)
  end

  teardown do
    Mocktail.reset
  end

  # --- Happy path: POST → job → debit ----------------------------------------

  test "full URL episode flow from form to completion debits 2 credits for premium + long article" do
    # Submit the URL form — pre-check cost is deferred (nil post-brick-3),
    # so ChecksEpisodeCreationPermission allows through without checking
    # balance. Debit is deferred to the async job.
    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
      post episodes_url, params: { url: "https://example.com/long-article" }
    end
    assert_redirected_to episodes_path

    episode = Episode.last
    assert_equal "url", episode.source_type
    assert_equal "pending", episode.status

    # Stub a long article (>20k chars) so Premium voice → 2 credits.
    long_html = "<article><h1>Long Title</h1><p>#{"A" * 40_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(long_html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with {
      Result.success(ProcessesWithLlm::LlmData.new(
        title: "Long Title",
        author: "Author",
        description: "A long article.",
        content: "Cleaned long content."
      ))
    }
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    # Run the job — triggers fetch → extract → deduct → LLM → submit.
    assert_difference -> { CreditTransaction.where(user: @credit_user, transaction_type: "usage").count }, 1 do
      perform_enqueued_jobs
    end

    transaction = CreditTransaction.where(user: @credit_user, transaction_type: "usage").order(:created_at).last
    assert_equal(-2, transaction.amount,
      "Premium + >20k URL must debit 2 credits — pre-brick-3 this was mis-priced at 1")
    assert_equal 1, @credit_user.reload.credits_remaining
  end

  test "short URL article debits 1 credit for premium voice" do
    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
      post episodes_url, params: { url: "https://example.com/short-article" }
    end

    short_html = "<article><h1>Short</h1><p>#{"A" * 5_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(short_html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with {
      Result.success(ProcessesWithLlm::LlmData.new(
        title: "Short", author: "Author", description: "Short.", content: "Short."
      ))
    }
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    perform_enqueued_jobs

    transaction = CreditTransaction.where(user: @credit_user, transaction_type: "usage").order(:created_at).last
    assert_equal(-1, transaction.amount,
      "≤20k URL (even Premium) must debit 1 credit")
  end

  # --- Deferred cost contract -----------------------------------------------
  #
  # Post-brick-3: the anticipated cost for URL at controller-submit time is
  # nil (deferred). ChecksEpisodeCreationPermission#check_credit_balance
  # handles nil by skipping the balance gate
  # (checks_episode_creation_permission.rb:43-44). The real charge happens
  # in the async job after FetchesArticleContent knows the length.
  #
  # This test pins the full deferred contract end-to-end: submit without
  # a known cost, enqueue the job, let the job compute the actual cost
  # from the extracted length, and debit accordingly.

  test "URL submission defers cost calculation to async job (controller sees nil)" do
    # Spy on ChecksEpisodeCreationPermission to verify the controller
    # actually receives nil for the anticipated_cost when source_type is
    # URL. This is the direct assertion of brick 3's sentinel kill at the
    # controller boundary.
    Mocktail.replace(ChecksEpisodeCreationPermission)
    stubs { |m| ChecksEpisodeCreationPermission.call(user: m.any, anticipated_cost: m.any) }.with {
      Result.success
    }

    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
      post episodes_url, params: { url: "https://example.com/article" }
    end

    # Assert the pre-check was called with nil cost (deferred) for URL.
    # Pre-brick-3 it was called with 1 (the sentinel).
    verify { |m| ChecksEpisodeCreationPermission.call(user: m.any, anticipated_cost: nil) }
  end
end
