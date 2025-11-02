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
    # Mock Firestore document with podcast_id
    mock_doc = MockFirestoreDocument.new(exists: true, data: { podcast_id: "podcast_abc123def456" })
    mock_collection = MockFirestoreCollection.new(mock_doc)
    mock_firestore = MockFirestore.new(mock_collection)

    @client.instance_variable_set(:@firestore, mock_firestore)

    result = @client.get_user_podcast_id("user_123")

    assert_equal "podcast_abc123def456", result
  end

  def test_get_user_podcast_id_raises_when_user_not_found
    # Mock Firestore document that doesn't exist
    mock_doc = MockFirestoreDocument.new(exists: false)
    mock_collection = MockFirestoreCollection.new(mock_doc)
    mock_firestore = MockFirestore.new(mock_collection)

    @client.instance_variable_set(:@firestore, mock_firestore)

    error = assert_raises(FirestoreClient::UserNotFoundError) do
      @client.get_user_podcast_id("nonexistent_user")
    end

    assert_match(/User nonexistent_user not found/, error.message)
  end

  def test_get_user_podcast_id_raises_when_podcast_id_missing
    # Mock Firestore document that exists but has no podcast_id
    mock_doc = MockFirestoreDocument.new(exists: true, data: { name: "John" })
    mock_collection = MockFirestoreCollection.new(mock_doc)
    mock_firestore = MockFirestore.new(mock_collection)

    @client.instance_variable_set(:@firestore, mock_firestore)

    error = assert_raises(FirestoreClient::UserNotFoundError) do
      @client.get_user_podcast_id("user_123")
    end

    assert_match(/User user_123 has no podcast_id/, error.message)
  end

  def test_get_podcast_owner_returns_owner_user_id
    # Mock Firestore document with owner_user_id
    mock_doc = MockFirestoreDocument.new(exists: true, data: { owner_user_id: "user_789" })
    mock_collection = MockFirestoreCollection.new(mock_doc)
    mock_firestore = MockFirestore.new(mock_collection)

    @client.instance_variable_set(:@firestore, mock_firestore)

    result = @client.get_podcast_owner("podcast_abc123def456")

    assert_equal "user_789", result
  end

  def test_get_podcast_owner_raises_when_podcast_not_found
    # Mock Firestore document that doesn't exist
    mock_doc = MockFirestoreDocument.new(exists: false)
    mock_collection = MockFirestoreCollection.new(mock_doc)
    mock_firestore = MockFirestore.new(mock_collection)

    @client.instance_variable_set(:@firestore, mock_firestore)

    error = assert_raises(FirestoreClient::PodcastNotFoundError) do
      @client.get_podcast_owner("nonexistent_podcast")
    end

    assert_match(/Podcast nonexistent_podcast not found/, error.message)
  end

  def test_get_podcast_owner_raises_when_owner_missing
    # Mock Firestore document that exists but has no owner_user_id
    mock_doc = MockFirestoreDocument.new(exists: true, data: { title: "My Podcast" })
    mock_collection = MockFirestoreCollection.new(mock_doc)
    mock_firestore = MockFirestore.new(mock_collection)

    @client.instance_variable_set(:@firestore, mock_firestore)

    error = assert_raises(FirestoreClient::PodcastNotFoundError) do
      @client.get_podcast_owner("podcast_abc123def456")
    end

    assert_match(/Podcast podcast_abc123def456 has no owner/, error.message)
  end
end

# Mock classes for Firestore testing
class MockFirestoreDocument
  attr_reader :data

  def initialize(exists:, data: {})
    @exists = exists
    @data = data
  end

  def exists?
    @exists
  end
end

class MockFirestoreCollection
  def initialize(document)
    @document = document
  end

  def doc(_doc_id)
    self
  end

  def get
    @document
  end
end

class MockFirestore
  def initialize(collection)
    @collection = collection
  end

  def col(_collection_name)
    @collection
  end
end
