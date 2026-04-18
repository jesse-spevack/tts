# frozen_string_literal: true

# Atomically rotates a user's extension-sourced API token: revokes every
# currently-active source=extension token for the user, then issues a new
# one. Wrapped in a transaction so if any revoke fails mid-rotation, the
# aborted transaction leaves prior tokens un-revoked rather than producing
# an inconsistent half-revoked-no-new-token state.
#
# Only source=extension tokens are touched — a user's personally-created
# API tokens (source=user, managed from /settings/api_tokens) are preserved
# across a reconnect.
class RotatesExtensionToken
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    ApiToken.transaction do
      @user.api_tokens.active.source_extension.find_each do |token|
        RevokesApiToken.call(token: token)
      end

      GeneratesApiToken.call(user: @user, source: "extension")
    end
  end
end
