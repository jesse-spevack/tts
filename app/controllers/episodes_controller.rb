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
      text: params[:text],
      title: params[:title],
      author: params[:author],
      source_url: params[:source_url]
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
      deduct_credit_if_needed(result.data)
      redirect_to episodes_path, notice: success_notice
    else
      flash.now[:alert] = result.error
      @episode = @podcast.episodes.build
      render :new, status: :unprocessable_entity
    end
  end

  def deduct_credit_if_needed(episode)
    return if Current.user.complimentary? || Current.user.unlimited?

    DeductsCredit.call(user: Current.user, episode: episode, cost_in_credits: anticipated_cost)
  end

  def read_uploaded_content
    return @read_uploaded_content if defined?(@read_uploaded_content)

    @read_uploaded_content = if params.dig(:episode, :content)&.respond_to?(:read)
      params[:episode][:content].read
    end
  end

  def require_can_view_new
    result = ChecksEpisodeCreationPermission.call(user: Current.user)
    return if result.success?

    flash[:alert] = "You've used your 2 free episodes this month! " \
                    "Upgrade to Premium for unlimited episodes, or buy a credit pack."
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
      "You've used your 2 free episodes this month! " \
      "Upgrade to Premium for unlimited episodes, or buy a credit pack."
    end
  end

  def anticipated_cost
    @anticipated_cost ||= CalculatesEpisodeCreditCost.call(
      source_text_length: source_text_length_for_cost,
      voice: voice_for_cost
    )
  end

  def source_text_length_for_cost
    if params[:url].present?
      1
    elsif params.key?(:text)
      params[:text].to_s.length
    else
      read_uploaded_content&.length || 0
    end
  end

  def voice_for_cost
    Voice.find(Current.user.voice_preference) || Voice.find(Voice::DEFAULT_KEY)
  end

  def load_podcast
    @podcast = Current.user.podcasts.first
    @podcast ||= CreatesDefaultPodcast.call(user: Current.user)
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
