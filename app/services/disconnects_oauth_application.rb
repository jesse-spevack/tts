# frozen_string_literal: true

class DisconnectsOauthApplication
  include StructuredLogging

  def self.call(user:, application:)
    new(user: user, application: application).call
  end

  def initialize(user:, application:)
    @user = user
    @application = application
  end

  def call
    tokens_revoked = Doorkeeper::AccessToken
      .where(resource_owner_id: @user.id, application_id: @application.id)
      .update_all(revoked_at: Time.current)

    grants_revoked = Doorkeeper::AccessGrant
      .where(resource_owner_id: @user.id, application_id: @application.id)
      .update_all(revoked_at: Time.current)

    log_info "oauth_app_disconnected",
      user_id: @user.id,
      application_id: @application.id,
      application_name: @application.name,
      tokens_revoked: tokens_revoked,
      grants_revoked: grants_revoked
  end
end
