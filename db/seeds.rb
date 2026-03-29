# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# --- OAuth Applications ---
# Pre-seeded OAuth clients for MCP and ChatGPT integrations.
# These are the only two clients at launch; no admin UI needed.

# Claude (claude.ai web + Claude Desktop) — public client, PKCE required
Doorkeeper::Application.find_or_create_by!(uid: "claude") do |app|
  app.name = "Claude"
  app.redirect_uri = "https://claude.ai/api/mcp/auth_callback"
  app.scopes = "podread"
  app.confidential = false
  # No secret for public clients — PKCE handles security
end
