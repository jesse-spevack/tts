class EpisodesController < ApplicationController
  before_action :require_authentication
  before_action :load_podcast

  def index
    @episodes = @podcast.episodes.newest_first
  end

  def new
    @episode = @podcast.episodes.build
  end

  def create
    @episode = @podcast.episodes.build(episode_params.except(:content))

    if @episode.save
      # Upload to GCS staging
      content = params[:episode][:content].read
      filename = "#{@episode.id}-#{Time.now.to_i}.md"

      uploader = GcsUploader.new(
        ENV.fetch("GOOGLE_CLOUD_BUCKET"),
        podcast_id: @podcast.podcast_id
      )
      staging_path = uploader.upload_staging_file(content: content, filename: filename)

      # Enqueue processing
      CloudTasksEnqueuer.new.enqueue_episode_processing(
        episode_id: @episode.id,
        podcast_id: @podcast.podcast_id,
        staging_path: staging_path,
        metadata: {
          title: @episode.title,
          author: @episode.author,
          description: @episode.description
        }
      )

      redirect_to episodes_path, notice: "Episode created! Processing..."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_podcast
    @podcast = Current.user.podcasts.first
    @podcast ||= CreateDefaultPodcast.call(user: Current.user)
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end
end
