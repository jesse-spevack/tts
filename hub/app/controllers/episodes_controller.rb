class EpisodesController < ApplicationController
  before_action :require_authentication, except: [ :show ]
  before_action :require_can_create_episode, only: [ :new, :create ]
  before_action :load_podcast, except: [ :show ]

  def index
    @pagy, @episodes = pagy(@podcast.episodes.newest_first)
  end

  def show
    @episode = Episode.find_by_prefix_id!(params[:id])
    raise ActiveRecord::RecordNotFound unless @episode.complete?
    @podcast = @episode.podcast
  end

  def new
    @episode = @podcast.episodes.build
  end

  def create
    if params[:url].present?
      create_from_url
    else
      create_from_markdown
    end
  end

  private

  def create_from_url
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: Current.user,
      url: params[:url]
    )

    if result.success?
      RecordEpisodeUsage.call(user: Current.user)
      redirect_to episodes_path, notice: "Processing article from URL..."
    else
      flash.now[:alert] = result.error
      @episode = @podcast.episodes.build
      render :new, status: :unprocessable_entity
    end
  end

  def create_from_markdown
    validation = EpisodeSubmissionValidator.call(user: Current.user)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: Current.user,
      params: episode_params,
      uploaded_file: params[:episode][:content],
      max_characters: validation.max_characters
    )

    if result.success?
      RecordEpisodeUsage.call(user: Current.user)
      redirect_to episodes_path, notice: "Episode created! Processing..."
    else
      @episode = result.episode
      flash.now[:alert] = @episode.error_message if @episode.error_message

      if @episode.errors[:content].any?
        flash.now[:alert] = @episode.errors[:content].first
      end

      render :new, status: :unprocessable_entity
    end
  end

  def require_can_create_episode
    result = CanCreateEpisode.call(user: Current.user)
    return if result.allowed?

    flash[:alert] = "You've used your 2 free episodes this month! " \
                    "Upgrade to Premium for unlimited episodes."
    redirect_to episodes_path
  end

  def load_podcast
    @podcast = Current.user.podcasts.first
    @podcast ||= CreateDefaultPodcast.call(user: Current.user)
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end
end
