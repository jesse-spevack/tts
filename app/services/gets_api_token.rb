# frozen_string_literal: true

class GetsApiToken
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    # Scoped to source=extension because the only caller
    # (Settings::ExtensionsController) manages the extension connection
    # specifically. Without this filter, a user with both a user-created PAT
    # and an extension token could have the PAT returned by this service and
    # then revoked when they click "Disconnect Extension" — silent data loss.
    @user.api_tokens.active.source_extension.first
  end
end
