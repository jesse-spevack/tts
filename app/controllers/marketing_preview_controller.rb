class MarketingPreviewController < ApplicationController
  allow_unauthenticated_access
  layout "marketing"

  # GET /marketing-preview/icons
  def icons
    icon_dir = Rails.root.join("app/views/shared/marketing/icons")
    @icon_names = Dir.glob(icon_dir.join("_*.html.erb")).map { |f|
      File.basename(f, ".html.erb").delete_prefix("_")
    }.sort
  end
end
