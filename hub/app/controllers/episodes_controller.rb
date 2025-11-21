class EpisodesController < ApplicationController
  before_action :require_authentication
  before_action :require_submission_access, only: [ :new, :create ]
  before_action :load_podcast

  def index
    @episodes = @podcast.episodes.newest_first
  end

  def new
    @episode = @podcast.episodes.build
  end

  def create
    validation = EpisodeSubmissionValidator.call(user: Current.user)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      params: episode_params,
      uploaded_file: params[:episode][:content],
      max_characters: validation.max_characters,
      voice_name: Current.user.voice_name
    )

    if result.success?
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

  private

  def require_submission_access
    unless Current.user.submissions_enabled?
      flash[:alert] = "Episode submission is only available for unlimited tier members. Please upgrade to submit episodes."
      redirect_to episodes_path
    end
  end

  def load_podcast
    @podcast = Current.user.podcasts.first
    @podcast ||= CreateDefaultPodcast.call(user: Current.user)
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end
end
