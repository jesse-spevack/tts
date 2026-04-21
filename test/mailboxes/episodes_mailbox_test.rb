# frozen_string_literal: true

require "test_helper"

class EpisodesMailboxTest < ActionMailbox::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = User.create!(email_address: "mailbox-test-#{SecureRandom.hex(4)}@example.com", email_episode_confirmation: true)
    @podcast = CreatesDefaultPodcast.call(user: @user)
    EnablesEmailEpisodes.call(user: @user)
  end

  test "routes readtome+token@ emails to episodes mailbox" do
    inbound_email = receive_inbound_email_from_mail(
      to: email_address_for(@user),
      from: "sender@example.com",
      subject: "Newsletter content",
      body: "A" * 150
    )

    assert inbound_email.delivered?
  end

  test "creates episode for valid token" do
    assert_enqueued_with(job: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: email_address_for(@user),
        from: "sender@example.com",
        subject: "My newsletter",
        body: "A" * 150
      )
    end
  end

  test "does not create episode for invalid token" do
    assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: "readtome+invalidtoken123@example.com",
        from: "sender@example.com",
        subject: "Spam",
        body: "Content that should be ignored"
      )
    end
  end

  test "does not create episode for disabled user" do
    DisablesEmailEpisodes.call(user: @user)

    # Re-enable to get address, then disable again
    EnablesEmailEpisodes.call(user: @user)
    address = email_address_for(@user)
    DisablesEmailEpisodes.call(user: @user)

    assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: address,
        from: "sender@example.com",
        subject: "Newsletter",
        body: "A" * 150
      )
    end
  end

  test "sends success notification when user has confirmation enabled" do
    @user.update!(email_episode_confirmation: true)

    assert_enqueued_emails 1 do
      receive_inbound_email_from_mail(
        to: email_address_for(@user),
        from: "sender@example.com",
        subject: "My newsletter",
        body: "A" * 150
      )
    end
  end

  test "does not send success notification when user has confirmation disabled" do
    @user.update!(email_episode_confirmation: false)

    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      receive_inbound_email_from_mail(
        to: email_address_for(@user),
        from: "sender@example.com",
        subject: "My newsletter",
        body: "A" * 150
      )
    end
  end

  test "sends failure notification on creation error" do
    # Email too short to create episode
    assert_enqueued_emails 1 do
      receive_inbound_email_from_mail(
        to: email_address_for(@user),
        from: "sender@example.com",
        subject: "Short email",
        body: "Too short"
      )
    end
  end

  test "sends failure notification when user is rate limited" do
    # Clear any existing episodes so we have a clean slate for rate limit test
    @user.episodes.unscoped.delete_all
    create_recent_episodes(20)

    assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
      assert_enqueued_emails 1 do
        receive_inbound_email_from_mail(
          to: email_address_for(@user),
          from: "sender@example.com",
          subject: "Rate limited newsletter",
          body: "A" * 150
        )
      end
    end
  end

  test "creates episode when user is under rate limit" do
    # Clear any existing episodes so we have a clean slate for rate limit test
    @user.episodes.unscoped.delete_all
    create_recent_episodes(19)

    assert_enqueued_with(job: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: email_address_for(@user),
        from: "sender@example.com",
        subject: "Under limit newsletter",
        body: "A" * 150
      )
    end
  end

  test "does not route emails without token suffix" do
    assert_raises(ActionMailbox::Router::RoutingError) do
      receive_inbound_email_from_mail(
        to: "readtome@example.com",
        from: "sender@example.com",
        subject: "No token",
        body: "A" * 150
      )
    end
  end

  test "does not route emails with empty token" do
    assert_raises(ActionMailbox::Router::RoutingError) do
      receive_inbound_email_from_mail(
        to: "readtome+@example.com",
        from: "sender@example.com",
        subject: "Empty token",
        body: "A" * 150
      )
    end
  end

  test "does not create episode for deactivated user" do
    address = email_address_for(@user)
    @user.update!(active: false)

    assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: address,
        from: "sender@example.com",
        subject: "Newsletter",
        body: "A" * 150
      )
    end
  end

  # === Credit gate + debit parity with other create paths (agent-team-7231) ===
  #
  # The web, API v1, extension, MCP, and URL-async paths all gate via
  # ChecksEpisodeCreationPermission and debit via DebitsEpisodeCredit/
  # RecordsEpisodeUsage. The email-ingest path must match that behavior:
  #
  #   * Free-tier users past their monthly quota must be rejected — no episode
  #     persisted (mirrors EpisodesController#require_can_create_episode).
  #   * Credit users must be debited for the episode's anticipated cost.
  #   * Free-tier users within quota must have their monthly usage incremented
  #     (RecordsEpisodeUsage side effect).
  #
  # These tests assert on real side effects (Episode.count, credit balance,
  # EpisodeUsage counter) rather than stubbing the gate services, so they
  # remain valid regardless of whether the fix routes through CreatesEpisode
  # or inlines the gates in ProcessesEmailEpisode.

  test "does not create episode for free-tier user past monthly quota" do
    free_user = users(:free_user)
    EnablesEmailEpisodes.call(user: free_user)
    CreatesDefaultPodcast.call(user: free_user)
    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES
    )

    assert_no_difference -> { Episode.where(user: free_user).count } do
      assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
        assert_enqueued_emails 1 do
          receive_inbound_email_from_mail(
            to: email_address_for(free_user),
            from: "sender@example.com",
            subject: "Over-quota newsletter",
            body: "A" * 150
          )
        end
      end
    end
  end

  test "debits credit user's balance when email episode is created" do
    credit_user = users(:credit_user)
    EnablesEmailEpisodes.call(user: credit_user)
    CreatesDefaultPodcast.call(user: credit_user)
    starting_balance = credit_user.credits_remaining
    assert starting_balance > 0, "credit_user fixture must start with credits"

    assert_difference -> { Episode.where(user: credit_user).count }, 1 do
      assert_difference -> { CreditTransaction.where(user: credit_user, transaction_type: "usage").count }, 1 do
        receive_inbound_email_from_mail(
          to: email_address_for(credit_user),
          from: "sender@example.com",
          subject: "Paid-tier newsletter",
          body: "A" * 150
        )
      end
    end

    # 150 chars is well under the 20k threshold, so cost is 1 credit regardless
    # of voice tier (CalculatesEpisodeCreditCost).
    assert_equal starting_balance - 1, credit_user.reload.credits_remaining

    transaction = CreditTransaction.where(user: credit_user, transaction_type: "usage").order(:created_at).last
    assert_equal(-1, transaction.amount)
  end

  test "increments free-tier monthly usage counter when email episode is created" do
    free_user = users(:free_user)
    EnablesEmailEpisodes.call(user: free_user)
    CreatesDefaultPodcast.call(user: free_user)

    assert_difference -> { EpisodeUsage.current_for(free_user).episode_count }, 1 do
      receive_inbound_email_from_mail(
        to: email_address_for(free_user),
        from: "sender@example.com",
        subject: "Under-quota newsletter",
        body: "A" * 150
      )
    end

    assert_equal 1, Episode.where(user: free_user).count
  end

  private

  def email_address_for(user)
    user.email_ingest_address
  end

  def create_recent_episodes(count)
    podcast = @user.podcasts.first || CreatesDefaultPodcast.call(user: @user)

    count.times do |i|
      Episode.create!(
        user: @user,
        podcast: podcast,
        title: "Rate limit test episode #{i}",
        author: "Test Author",
        description: "Test description",
        source_type: :url,
        source_url: "https://example.com/article-#{i}",
        status: :pending
      )
    end
  end
end
