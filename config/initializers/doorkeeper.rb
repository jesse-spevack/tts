# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  # --- Grant flows ---
  # OAuth 2.1: authorization_code only (no implicit, no password, no client_credentials)
  grant_flows %w[authorization_code]

  # --- PKCE ---
  # Required for public clients (e.g., Claude). Confidential clients can skip PKCE.
  force_pkce

  # Only allow S256 (no plain challenge method)
  pkce_code_challenge_methods %w[S256]

  # --- Tokens ---
  access_token_expires_in 1.hour
  use_refresh_token
  # Note: Doorkeeper 5.9 doesn't support time-based refresh token expiry.
  # Refresh tokens are invalidated via rotation (old token revoked when new one
  # issued) and explicit revocation (user disconnects from Settings). This is
  # sufficient — Claude's MCP client auto-refreshes, so tokens stay fresh.

  # Authorization codes expire after 10 minutes (default)
  authorization_code_expires_in 10.minutes

  # Revoke the previous token when a new one is issued via authorization code
  revoke_previous_authorization_code_token

  # --- Scopes ---
  # Single scope for all MCP/API access. No granular permissions needed.
  default_scopes :podread

  # --- Resource owner authentication ---
  # PodRead uses magic link auth with cookie-based sessions (not Devise).
  # Current.user is set by the Authentication concern via resume_session.
  # If not logged in, redirect to login page with return_to pointing back here.
  resource_owner_authenticator do
    # Doorkeeper controllers skip require_authentication (see doorkeeper_auth_skip.rb),
    # so we call resume_session to restore Current.session from the cookie.
    # This is defined in the Authentication concern included in ApplicationController.
    resume_session

    Current.user || begin
      session[:return_to_after_authenticating] = request.fullpath
      redirect_to login_path(return_to: request.fullpath)
      nil
    end
  end

  # Doorkeeper controllers inherit from ApplicationController to use the app layout,
  # Tailwind styles, and helper methods. The Authentication concern's
  # require_authentication is skipped via allow_unauthenticated_access (see
  # app/controllers/concerns/doorkeeper_auth_skip.rb).
  base_controller "ApplicationController"

  # --- Security ---
  # Allow localhost redirects in development/test for testing OAuth flows
  force_ssl_in_redirect_uri { |uri| !Rails.env.local? && uri.host != "localhost" }

  # No admin UI for managing OAuth apps — they're pre-seeded
  admin_authenticator do
    head :forbidden
  end

  # WWW-Authenticate realm
  realm "PodRead"
end
