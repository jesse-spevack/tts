class PagesController < ApplicationController
  include Trackable
  allow_unauthenticated_access

  layout "marketing", only: %i[home terms privacy about_02]

  def home
    redirect_to new_episode_path if authenticated?
    @episode_count = Episode.count
    @user_count = User.count
  end

  def how_it_sounds
  end

  def terms
  end

  def privacy
  end

  def add_rss_feed
  end

  def extension_help
  end

  def about_02
  end
end
