class EpisodesController < ApplicationController
  before_action :require_authentication, except: [ :show ]
  before_action :require_can_create_episode, only: [ :new, :create ]
  before_action :load_podcast, except: [ :show ]

  def index
    @pagy, @episodes = pagy(:offset, @podcast.episodes.newest_first)
  end

  def show
    @episode = Episode.find_by_prefix_id!(params[:id])
    raise ActiveRecord::RecordNotFound unless @episode.complete?

    respond_to do |format|
      format.html { @podcast = @episode.podcast }
      format.mp3 { redirect_to @episode.download_url, allow_other_host: true }
    end
  end

  def new
    @episode = @podcast.episodes.build
  end

  def create
    if params[:url].present?
      create_from_url
    elsif params.key?(:text)
      create_from_paste
    else
      create_from_file
    end
  end

  def destroy
    @episode = Current.user.episodes.find_by_prefix_id!(params[:id])
    DeleteEpisodeJob.perform_later(episode_id: @episode.id, action_id: Current.action_id)

    respond_to do |format|
      format.turbo_stream do
        @pagy, @episodes = pagy(:offset, @podcast.episodes.newest_first, page: params[:page])
        flash.now[:notice] = "Episode deleted."
      end
      format.html { redirect_to episodes_path(page: params[:page]), notice: "Episode deleted." }
    end
  end

  private

  def create_from_url
    result = CreatesUrlEpisode.call(
      podcast: @podcast,
      user: Current.user,
      url: params[:url]
    )
    handle_create_result(result, "Processing article from URL...")
  end

  def create_from_paste
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: Current.user,
      text: params[:text]
    )
    handle_create_result(result, "Processing pasted text...")
  end

  def create_from_file
    result = CreatesFileEpisode.call(
      podcast: @podcast,
      user: Current.user,
      title: episode_params[:title],
      author: episode_params[:author],
      description: episode_params[:description],
      content: read_uploaded_content
    )
    handle_create_result(result, "Episode created! Processing...")
  end

  def handle_create_result(result, success_notice)
    if result.success?
      RecordsEpisodeUsage.call(user: Current.user)
      redirect_to episodes_path, notice: success_notice
    else
      flash.now[:alert] = result.error
      @episode = @podcast.episodes.build
      render :new, status: :unprocessable_entity
    end
  end

  def read_uploaded_content
    return nil unless params.dig(:episode, :content)&.respond_to?(:read)

    params[:episode][:content].read
  end

  def require_can_create_episode
    result = ChecksEpisodeCreationPermission.call(user: Current.user)
    return if result.success?

    flash[:alert] = "You've used your 2 free episodes this month! " \
                    "Upgrade to Premium for unlimited episodes."
    redirect_to episodes_path
  end

  def load_podcast
    @podcast = Current.user.podcasts.first
    @podcast ||= CreatesDefaultPodcast.call(user: Current.user)
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end
end
