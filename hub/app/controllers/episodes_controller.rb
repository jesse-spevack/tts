class EpisodesController < ApplicationController
  before_action :require_authentication
  before_action :load_podcast

  def index
    @episodes = @podcast.episodes.recent
  end

  def new
    @episode = @podcast.episodes.build
  end

  def create
    @episode = @podcast.episodes.build(episode_params)

    if @episode.save
      # TODO: Enqueue processing job
      redirect_to episodes_path, notice: "Episode created! Processing..."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_podcast
    @podcast = Current.user.podcasts.first
    redirect_to root_path, alert: "No podcast found" unless @podcast
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end
end
