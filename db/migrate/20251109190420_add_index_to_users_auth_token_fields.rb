class AddIndexToUsersAuthTokenFields < ActiveRecord::Migration[8.1]
  def change
    # Index for efficient expiration queries
    add_index :users, :auth_token_expires_at

    # Composite index for token lookup + expiration check
    # (already have index on auth_token from create_users migration)
  end
end
