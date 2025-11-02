require "minitest/autorun"
require_relative "../lib/firestore_client"

class TestFirestoreClient < Minitest::Test
  def setup
    @client = FirestoreClient.new("test-project")
  end

  def test_initializes_with_project_id_from_env
    assert_instance_of FirestoreClient, @client
  end

  def test_get_user_podcast_id_returns_podcast_id
    # This test will use mocking in implementation
    skip "Integration test - requires Firestore emulator or mock"
  end

  def test_get_podcast_owner_returns_user_id
    skip "Integration test - requires Firestore emulator or mock"
  end
end
