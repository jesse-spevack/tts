class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  rescue_from Pagy::RangeError, with: :redirect_to_last_page

  before_action :redirect_legacy_domain
  before_action :set_action_id

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def redirect_legacy_domain
    return unless request.host == "tts.verynormal.dev"

    redirect_to "https://#{AppConfig::Domain::HOST}#{request.fullpath}", status: :moved_permanently, allow_other_host: true
  end

  def set_action_id
    Current.action_id = request.request_id
  end

  def redirect_to_last_page(exception)
    redirect_to url_for(action: :index, page: exception.pagy.last)
  end
end
