class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  before_action :set_action_id

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def set_action_id
    Current.action_id = request.request_id
  end
end
