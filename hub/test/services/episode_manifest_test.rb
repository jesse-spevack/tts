require "test_helper"

class EpisodeManifestTest < ActiveSupport::TestCase
  test "remove_episode removes episode by id" do
    manifest = EpisodeManifest.new(nil)
    manifest.instance_variable_set(:@episodes, [
      { "id" => "ep1", "title" => "First" },
      { "id" => "ep2", "title" => "Second" }
    ])

    manifest.remove_episode("ep1")

    assert_equal 1, manifest.episodes.size
    assert_equal "ep2", manifest.episodes.first["id"]
  end

  test "remove_episode does nothing if episode not found" do
    manifest = EpisodeManifest.new(nil)
    manifest.instance_variable_set(:@episodes, [
      { "id" => "ep1", "title" => "First" }
    ])

    manifest.remove_episode("nonexistent")

    assert_equal 1, manifest.episodes.size
  end
end
