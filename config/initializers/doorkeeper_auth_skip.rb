# frozen_string_literal: true

# Doorkeeper::AuthorizationsController inherits from our ApplicationController
# (via base_controller config), which includes the Authentication concern with
# a before_action :require_authentication.
#
# Doorkeeper handles its own auth via resource_owner_authenticator, so we skip
# the Authentication concern's before_action on the authorizations controller.
#
# TokensController and TokenInfoController use ApplicationMetalController
# (inherits from ActionController::API), so they don't have this callback.
Rails.application.config.to_prepare do
  Doorkeeper::AuthorizationsController.allow_unauthenticated_access
end
