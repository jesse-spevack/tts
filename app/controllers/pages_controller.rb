class PagesController < ApplicationController
  include Trackable
  allow_unauthenticated_access

  def home
    redirect_to new_episode_path if authenticated?
  end

  def how_it_sounds
  end

  def terms
  end

  def privacy
  end

  def add_rss_feed
  end
end
