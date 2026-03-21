class PagesController < ApplicationController
  include Trackable
  allow_unauthenticated_access

  layout "marketing", only: %i[home marketing_home terms privacy about]

  def home
    return redirect_to new_episode_path if authenticated?
    load_home_stats
  end

  def marketing_home
    load_home_stats
    render :home
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

  def about
  end

  private

  def load_home_stats
    @episode_count = Rails.cache.fetch("home/episode_count", expires_in: 5.minutes) { Episode.count }
    @user_count = Rails.cache.fetch("home/user_count", expires_in: 5.minutes) { User.count }
  end
end
