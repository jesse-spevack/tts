require "test_helper"
require "rake"

class FeedsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("feeds:rebrand_verynormal_defaults")
  end

  teardown do
    Rake::Task["feeds:rebrand_verynormal_defaults"].reenable
  end

  test "rewrites stale verynormal title and description on backfilled podcasts" do
    podcast = Podcast.create!(
      title: "stale@example.com's Very Normal Podcast",
      description: "My podcast created with tts.verynormal.dev"
    )

    capture_io { Rake::Task["feeds:rebrand_verynormal_defaults"].invoke }

    podcast.reload
    assert_equal "PodRead Podcast", podcast.title
    assert_equal "My podcast created with #{AppConfig::Domain::HOST}", podcast.description
  end

  test "leaves customized titles untouched" do
    podcast = Podcast.create!(
      title: "My Custom Podcast",
      description: "My podcast created with tts.verynormal.dev"
    )

    capture_io { Rake::Task["feeds:rebrand_verynormal_defaults"].invoke }

    podcast.reload
    assert_equal "My Custom Podcast", podcast.title,
      "rake task must not clobber a user-customized title"
    assert_equal "My podcast created with #{AppConfig::Domain::HOST}", podcast.description
  end

  test "leaves customized descriptions untouched" do
    podcast = Podcast.create!(
      title: "stale@example.com's Very Normal Podcast",
      description: "I have customized this description"
    )

    capture_io { Rake::Task["feeds:rebrand_verynormal_defaults"].invoke }

    podcast.reload
    assert_equal "PodRead Podcast", podcast.title
    assert_equal "I have customized this description", podcast.description,
      "rake task must not clobber a user-customized description"
  end

  test "is a no-op when neither field matches the stale defaults" do
    podcast = Podcast.create!(
      title: "Already PodRead Podcast",
      description: "Already custom"
    )
    original_updated_at = podcast.updated_at

    capture_io { Rake::Task["feeds:rebrand_verynormal_defaults"].invoke }

    podcast.reload
    assert_equal "Already PodRead Podcast", podcast.title
    assert_equal "Already custom", podcast.description
    assert_equal original_updated_at.to_i, podcast.updated_at.to_i,
      "should not touch rows that don't match the stale defaults"
  end
end
