require "test_helper"

class ProcessUrlEpisodeJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessUrlEpisodeJob) do
      ProcessUrlEpisodeJob.perform_later(@episode.id)
    end
  end

  test "finds episode by id" do
    # Stub the URL fetch to avoid real HTTP call
    stub_request(:get, "https://example.com/article")
      .to_return(status: 404)

    # Job should run without error (episode will fail due to 404, but that's expected)
    ProcessUrlEpisodeJob.perform_now(@episode.id)

    @episode.reload
    assert_equal "failed", @episode.status
  end
end
