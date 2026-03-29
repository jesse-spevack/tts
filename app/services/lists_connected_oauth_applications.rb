# frozen_string_literal: true

class ListsConnectedOauthApplications
  def self.call(user:)
    # Find OAuth apps with non-revoked tokens for this user.
    # Filter expired tokens in Ruby since SQLite datetime arithmetic is non-standard.
    tokens = Doorkeeper::AccessToken
      .where(resource_owner_id: user.id)
      .where(revoked_at: nil)
      .includes(:application)
      .order(created_at: :desc)

    tokens
      .reject(&:expired?)
      .group_by(&:application)
      .map do |app, app_tokens|
        {
          app: app,
          authorized_at: app_tokens.first&.created_at
        }
      end
  end
end
