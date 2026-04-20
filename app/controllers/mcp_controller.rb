# frozen_string_literal: true

class McpController < ActionController::API
  include StructuredLogging

  before_action :doorkeeper_authorize!

  # POST/GET/DELETE /mcp
  def handle
    response = transport.handle_request(request)

    status, headers, body = response
    headers.each { |key, value| self.response.headers[key] = value }
    render body: body.first, status: status, content_type: headers["Content-Type"] || "application/json"
  end

  private

  def transport
    @transport ||= MCP::Server::Transports::StreamableHTTPTransport.new(
      BuildsMcpServer.call(user: current_resource_owner),
      stateless: true
    )
  end

  def current_resource_owner
    return @current_resource_owner if defined?(@current_resource_owner)

    user = User.find_by(id: doorkeeper_token.resource_owner_id)
    @current_resource_owner = user&.deactivated? ? nil : user
  end

  def doorkeeper_authorize!
    token = Doorkeeper::OAuth::Token.authenticate(request, *Doorkeeper.config.access_token_methods)

    if token.blank? || token.revoked? || token.expired?
      log_warn "mcp_auth_failed", reason: token.blank? ? "missing" : (token.revoked? ? "revoked" : "expired")
      render_unauthorized
      return
    end

    @doorkeeper_token = token

    unless current_resource_owner
      log_warn "mcp_auth_failed", reason: "user_not_found_or_deactivated", resource_owner_id: token.resource_owner_id
      render_unauthorized
      return
    end

    log_info "mcp_request", user_id: current_resource_owner.id
  end

  def render_unauthorized
    headers["WWW-Authenticate"] = %(Bearer realm="PodRead", resource_metadata="#{AppConfig::Domain::BASE_URL}/.well-known/oauth-protected-resource")
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  attr_reader :doorkeeper_token
end
