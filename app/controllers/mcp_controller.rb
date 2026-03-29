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
    @transport ||= MCP::Server::Transports::StreamableHTTPTransport.new(mcp_server, stateless: true)
  end

  def mcp_server
    @mcp_server ||= MCP::Server.new(
      name: "podread",
      version: "1.0.0",
      instructions: "PodRead converts articles and text into podcast episodes. Use these tools to create episodes, check their status, and manage the user's podcast feed.",
      tools: [
        CreateEpisodeFromUrlTool,
        CreateEpisodeFromTextTool,
        ListEpisodesTool,
        GetEpisodeTool,
        DeleteEpisodeTool,
        GetFeedUrlTool,
        ListVoicesTool
      ],
      server_context: { user: current_resource_owner }
    )
  end

  def current_resource_owner
    @current_resource_owner ||= User.find(doorkeeper_token.resource_owner_id)
  end

  def doorkeeper_authorize!
    token = Doorkeeper::OAuth::Token.authenticate(request, *Doorkeeper.config.access_token_methods)

    if token.blank? || token.revoked? || token.expired?
      log_warn "mcp_auth_failed", reason: token.blank? ? "missing" : (token.revoked? ? "revoked" : "expired")

      headers["WWW-Authenticate"] = %(Bearer realm="PodRead", resource_metadata="#{AppConfig::Domain::BASE_URL}/.well-known/oauth-protected-resource")

      render json: { error: "unauthorized" }, status: :unauthorized
      return
    end

    @doorkeeper_token = token
    log_info "mcp_request", user_id: current_resource_owner.id
  end

  attr_reader :doorkeeper_token
end
