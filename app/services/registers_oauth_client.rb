# frozen_string_literal: true

# Dynamic Client Registration (RFC 7591) for MCP clients.
# Creates a new Doorkeeper::Application from client metadata.
class RegistersOauthClient
  include StructuredLogging

  def self.call(params:)
    new(params: params).call
  end

  def initialize(params:)
    @params = params
  end

  def call
    redirect_uris = @params[:redirect_uris]
    return error_result("invalid_client_metadata", "redirect_uris is required") if redirect_uris.blank?
    return error_result("invalid_client_metadata", "redirect_uris must be an array") unless redirect_uris.is_a?(Array)

    app = Doorkeeper::Application.create!(
      name: @params[:client_name].presence || "MCP Client",
      redirect_uri: redirect_uris.join("\n"),
      scopes: Doorkeeper.config.default_scopes.to_s,
      confidential: false
    )

    log_info "oauth_client_registered",
      client_id: app.uid,
      client_name: app.name,
      redirect_uris: redirect_uris

    Result.success(app)
  rescue ActiveRecord::RecordInvalid => e
    log_warn "oauth_client_registration_failed", error: e.message
    error_result("invalid_client_metadata", e.message)
  end

  private

  def error_result(error, description)
    Result.failure(error, message: description)
  end
end
