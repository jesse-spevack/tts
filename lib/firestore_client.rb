require "google/cloud/firestore"

class FirestoreClient
  class UserNotFoundError < StandardError; end
  class PodcastNotFoundError < StandardError; end

  def initialize(project_id = nil)
    @project_id = project_id || ENV.fetch("GOOGLE_CLOUD_PROJECT")
    @firestore = nil
  end

  # Get user's podcast_id from Firestore
  # @param user_id [String] User identifier
  # @return [String] Podcast ID
  # @raise [UserNotFoundError] If user document doesn't exist
  def get_user_podcast_id(user_id)
    doc = firestore.col("users").doc(user_id).get
    raise UserNotFoundError, "User #{user_id} not found" unless doc.exists?

    podcast_id = doc.data[:podcast_id]
    raise UserNotFoundError, "User #{user_id} has no podcast_id" unless podcast_id

    podcast_id
  end

  # Get podcast owner user_id from Firestore
  # @param podcast_id [String] Podcast identifier
  # @return [String] User ID who owns the podcast
  # @raise [PodcastNotFoundError] If podcast document doesn't exist
  def get_podcast_owner(podcast_id)
    doc = firestore.col("podcasts").doc(podcast_id).get
    raise PodcastNotFoundError, "Podcast #{podcast_id} not found" unless doc.exists?

    owner_user_id = doc.data[:owner_user_id]
    raise PodcastNotFoundError, "Podcast #{podcast_id} has no owner" unless owner_user_id

    owner_user_id
  end

  private

  def firestore
    @firestore ||= Google::Cloud::Firestore.new(project_id: @project_id)
  end
end
