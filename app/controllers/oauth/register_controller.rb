# frozen_string_literal: true

# Dynamic Client Registration endpoint (RFC 7591).
# MCP clients (like Claude) POST here to register themselves
# before starting the OAuth authorize flow.
module Oauth
  class RegisterController < ActionController::API
    include StructuredLogging

    # POST /oauth/register
    def create
      result = RegistersOauthClient.call(params: registration_params)

      if result.success?
        render json: client_response(result.data), status: :created
      else
        render json: { error: result.error, error_description: result.message }, status: :bad_request
      end
    end

    private

    def registration_params
      params.permit(
        :client_name, :client_uri, :logo_uri, :scope,
        :token_endpoint_auth_method, :software_id, :software_version,
        redirect_uris: [], grant_types: [], response_types: [], contacts: []
      )
    end

    def client_response(app)
      {
        client_id: app.uid,
        client_name: app.name,
        redirect_uris: app.redirect_uri.split("\n"),
        token_endpoint_auth_method: "none",
        grant_types: [ "authorization_code" ],
        response_types: [ "code" ],
        client_id_issued_at: app.created_at.to_i,
        client_secret_expires_at: 0
      }
    end
  end
end
