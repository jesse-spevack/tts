require "test_helper"

class ProcessesUrlEpisodeJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Mocktail::DSL

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Placeholder",
      author: "Placeholder",
      description: "Placeholder",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :pending
    )

    Mocktail.replace(FetchesUrl)
  end

  teardown do
    Mocktail.reset
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
      ProcessesUrlEpisodeJob.perform_later(episode_id: @episode.id, user_id: @user.id)
    end
  end

  test "finds episode by id" do
    # Stub the URL fetch to return an error
    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.failure("Could not fetch URL") }

    # Job should run without error (episode will fail due to fetch error, but that's expected)
    ProcessesUrlEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)

    @episode.reload
    assert_equal "failed", @episode.status
  end

  test "marks episode failed and skips processing when user is soft-deleted" do
    stubs { |m| FetchesUrl.call(url: m.any) }.with { raise "should not be called" }
    @user.update!(deleted_at: Time.current)
    @episode.reload

    logs = capture_logs do
      ProcessesUrlEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)
    end

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Account was deleted", @episode.error_message
    assert_match(/event=processes_url_episode_job_skipped .*reason=user_missing_or_soft_deleted/, logs)
    assert_equal 0, Mocktail.calls(FetchesUrl, :call).size
  end

  private

  def capture_logs
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    yield
    output.string
  ensure
    Rails.logger = original_logger
  end
end
