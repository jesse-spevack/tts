require "test_helper"

class ProcessUrlEpisodeJobTest < ActiveSupport::TestCase
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
      status: :processing
    )

    Mocktail.replace(UrlFetcher)
  end

  teardown do
    Mocktail.reset
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessUrlEpisodeJob) do
      ProcessUrlEpisodeJob.perform_later(@episode.id)
    end
  end

  test "finds episode by id" do
    # Stub the URL fetch to return an error
    stubs { |m| UrlFetcher.call(url: m.any) }.with { UrlFetcher::Result.failure("Could not fetch URL") }

    # Job should run without error (episode will fail due to fetch error, but that's expected)
    ProcessUrlEpisodeJob.perform_now(@episode.id)

    @episode.reload
    assert_equal "failed", @episode.status
  end
end
