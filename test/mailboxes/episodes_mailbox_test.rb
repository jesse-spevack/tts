# frozen_string_literal: true

require "test_helper"

class EpisodesMailboxTest < ActionMailbox::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
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
        to: "readtome+invalidtoken123@tts.verynormal.dev",
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

  test "does not route emails without token suffix" do
    assert_raises(ActionMailbox::Router::RoutingError) do
      receive_inbound_email_from_mail(
        to: "readtome@tts.verynormal.dev",
        from: "sender@example.com",
        subject: "No token",
        body: "A" * 150
      )
    end
  end

  private

  def email_address_for(user)
    GeneratesEmailIngestAddress.call(user: user)
  end
end
