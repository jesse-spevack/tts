class GenerateEpisodeDownloadUrl
  def self.call(episode)
    new(episode).call
  end

  def initialize(episode)
    @episode = episode
  end

  def call
    return nil unless @episode.complete? && @episode.gcs_episode_id.present?

    file.signed_url(
      method: "GET",
      expires: 300,
      query: {
        "response-content-disposition" => "attachment; filename=\"#{filename}\""
      }
    )
  end

  private

  def file
    bucket.file(file_path)
  end

  def bucket
    storage.bucket(bucket_name)
  end

  def storage
    Google::Cloud::Storage.new(project_id: ENV["GOOGLE_CLOUD_PROJECT"])
  end

  def bucket_name
    ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
  end

  def file_path
    "podcasts/#{@episode.podcast.podcast_id}/episodes/#{@episode.gcs_episode_id}.mp3"
  end

  def filename
    "#{@episode.title.parameterize}.mp3"
  end
end
