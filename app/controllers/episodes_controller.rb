class EpisodesController < ApplicationController
  layout :determine_layout

  before_action :require_authentication, except: [ :show ]
  before_action :require_can_view_new, only: [ :new ]
  before_action :require_can_create_episode, only: [ :create ]
  before_action :load_podcast, except: [ :show ]

  def index
    @query = search_query
    episodes = SearchesEpisodes.call(podcast: @podcast, query: @query)
    @pagy, @episodes = pagy(:offset, episodes)
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
    result = CreatesEpisode.call(
      user: Current.user,
      podcast: @podcast,
      source_type: submission_source_type,
      params: facade_params,
      cost_in_credits: anticipated_cost
    )

    if result.success?
      redirect_to episodes_path, notice: success_notice_for(submission_source_type)
    else
      flash.now[:alert] = result.error
      @episode = @podcast.episodes.build
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @episode = Current.user.episodes.find_by_prefix_id!(params[:id])
    DeleteEpisodeJob.perform_later(episode_id: @episode.id, action_id: Current.action_id)

    respond_to do |format|
      format.turbo_stream do
        if params[:redirect]
          redirect_to episodes_path, notice: "Episode deleted."
        else
          flash.now[:notice] = "Episode deleted."
        end
      end
      format.html { redirect_to episodes_path, notice: "Episode deleted." }
    end
  end

  private

  # Shape the HTTP request into the flat params hash the CreatesEpisode
  # facade expects. Each source_type only needs a subset — unused keys are
  # simply ignored by the corresponding per-source creator.
  def facade_params
    case submission_source_type
    when "url"
      { url: params[:url] }
    when "text"
      {
        text: params[:text],
        title: params[:title],
        author: params[:author],
        source_url: params[:source_url]
      }
    when "file"
      {
        title: episode_params[:title],
        author: episode_params[:author],
        description: episode_params[:description],
        content: read_uploaded_content
      }
    else
      {}
    end
  end

  def success_notice_for(source_type)
    case source_type
    when "url"  then "Processing article from URL..."
    when "text" then "Processing pasted text..."
    when "file" then "Episode created! Processing..."
    end
  end

  def read_uploaded_content
    return @read_uploaded_content if defined?(@read_uploaded_content)

    @read_uploaded_content = if params.dig(:episode, :content)&.respond_to?(:read)
      params[:episode][:content].read
    end
  end

  FREE_LIMIT_REACHED_FLASH = "You've used your #{AppConfig::Tiers::FREE_MONTHLY_EPISODES} free episodes this month. " \
                             "Buy a credit pack to create more."

  def require_can_view_new
    result = ChecksEpisodeCreationPermission.call(user: Current.user)
    return if result.success?

    flash[:alert] = FREE_LIMIT_REACHED_FLASH
    redirect_to episodes_path
  end

  def require_can_create_episode
    result = ChecksEpisodeCreationPermission.call(
      user: Current.user,
      anticipated_cost: anticipated_cost
    )
    return if result.success?

    flash[:alert] = flash_for_permission_failure(result)
    redirect_to episodes_path
  end

  def flash_for_permission_failure(result)
    case result.code
    when :insufficient_credits
      "You don't have enough credits for this episode. Buy a credit pack to continue."
    else
      FREE_LIMIT_REACHED_FLASH
    end
  end

  def anticipated_cost
    @anticipated_cost ||= CalculatesAnticipatedEpisodeCost.call(
      EpisodeCostRequest.new(
        user: Current.user,
        source_type: submission_source_type,
        text: params[:text],
        url: params[:url],
        upload: read_uploaded_content
      )
    ).data.credits
  end

  def submission_source_type
    if params[:url].present?
      "url"
    elsif params.key?(:text)
      "text"
    else
      "file"
    end
  end

  def load_podcast
    @podcast = GetsDefaultPodcastForUser.call(user: Current.user)
  end

  def search_query
    params[:q]
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end

  def determine_layout
    if action_name == "show" && !authenticated?
      "marketing"
    else
      "application"
    end
  end
end
