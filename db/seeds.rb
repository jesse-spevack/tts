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

# ChatGPT (custom GPT Action) — confidential client, PKCE not required.
# Doorkeeper 5.9's force_pkce only enforces PKCE for non-confidential clients,
# so making this confidential automatically skips PKCE enforcement.
# ChatGPT sends client_secret in token requests (server-side flow).
#
# IMPORTANT: After creating the GPT in ChatGPT's editor, replace CHATGPT_GPT_ID
# with the actual GPT ID (visible in the URL bar, e.g. "g-abc123"). Both domains
# are registered because ChatGPT uses chatgpt.com on web and chat.openai.com on mobile.
chatgpt_gpt_id = ENV.fetch("CHATGPT_GPT_ID", "g-PLACEHOLDER")
Doorkeeper::Application.find_or_create_by!(uid: "chatgpt") do |app|
  app.name = "ChatGPT"
  app.redirect_uri = [
    "https://chatgpt.com/aip/#{chatgpt_gpt_id}/oauth/callback",
    "https://chat.openai.com/aip/#{chatgpt_gpt_id}/oauth/callback"
  ].join("\n")
  app.scopes = "podread"
  app.confidential = true
  app.secret = ENV.fetch("CHATGPT_OAUTH_SECRET") { SecureRandom.hex(32) }
end
