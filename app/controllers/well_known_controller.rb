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
    expires_in 1.day, public: true

    render json: {
      resource: base_url,
      authorization_servers: [ base_url ],
      scopes_supported: doorkeeper_scopes,
      bearer_methods_supported: [ "header" ]
    }
  end

  # GET /.well-known/oauth-authorization-server
  # RFC 8414 — describes OAuth server capabilities and endpoints
  def oauth_authorization_server
    expires_in 1.day, public: true

    render json: {
      issuer: base_url,
      authorization_endpoint: "#{base_url}/oauth/authorize",
      token_endpoint: "#{base_url}/oauth/token",
      registration_endpoint: "#{base_url}/oauth/register",
      revocation_endpoint: "#{base_url}/oauth/revoke",
      introspection_endpoint: "#{base_url}/oauth/introspect",
      scopes_supported: doorkeeper_scopes,
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      token_endpoint_auth_methods_supported: [ "none" ],
      code_challenge_methods_supported: Doorkeeper.config.pkce_code_challenge_methods,
      service_documentation: "#{base_url}/help/claude"
    }
  end

  private

  def base_url
    AppConfig::Domain::BASE_URL
  end

  def doorkeeper_scopes
    Doorkeeper.config.default_scopes.to_a
  end
end
