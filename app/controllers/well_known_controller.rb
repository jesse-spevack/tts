# frozen_string_literal: true

# Serves OAuth metadata documents required by the MCP spec.
#
# RFC 9728 — Protected Resource Metadata (mandatory for MCP)
# RFC 8414 — Authorization Server Metadata
#
# These are static JSON documents that help MCP clients (like Claude)
# discover how to authenticate with PodRead's OAuth server.
class WellKnownController < ActionController::API
  # GET /.well-known/oauth-protected-resource
  # RFC 9728 — tells MCP clients where to find the authorization server
  def oauth_protected_resource
    render json: {
      resource: base_url,
      authorization_servers: [ base_url ],
      scopes_supported: [ "podread" ],
      bearer_methods_supported: [ "header" ]
    }
  end

  # GET /.well-known/oauth-authorization-server
  # RFC 8414 — describes OAuth server capabilities and endpoints
  def oauth_authorization_server
    render json: {
      issuer: base_url,
      authorization_endpoint: "#{base_url}/oauth/authorize",
      token_endpoint: "#{base_url}/oauth/token",
      revocation_endpoint: "#{base_url}/oauth/revoke",
      introspection_endpoint: "#{base_url}/oauth/introspect",
      scopes_supported: [ "podread" ],
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      token_endpoint_auth_methods_supported: [ "none" ],
      code_challenge_methods_supported: [ "S256" ],
      service_documentation: "#{base_url}/help/claude"
    }
  end

  private

  def base_url
    AppConfig::Domain::BASE_URL
  end
end
