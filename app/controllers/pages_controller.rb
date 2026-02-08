class PagesController < ApplicationController
  include Trackable
  allow_unauthenticated_access

  layout "marketing", only: %i[home terms privacy privacy_01 privacy_02 error_404_01 error_404_02 home_01 home_02 home_03 pricing_01 pricing_02 pricing_03 about_01 about_02 about_03]

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

  def extension_help
  end

  def privacy_01
  end

  def privacy_02
  end

  def error_404_01
  end

  def error_404_02
  end

  def home_01
  end

  def home_02
  end

  def home_03
  end

  def pricing_01
  end

  def pricing_02
  end

  def pricing_03
  end

  def about_01
  end

  def about_02
  end

  def about_03
  end
end
