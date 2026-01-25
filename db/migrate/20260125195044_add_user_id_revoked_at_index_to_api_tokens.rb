class AddUserIdRevokedAtIndexToApiTokens < ActiveRecord::Migration[8.1]
  def change
    # Composite index to optimize active_token_for(user) queries
    # which filter by user_id and revoked_at: nil
    add_index :api_tokens, [:user_id, :revoked_at], name: "index_api_tokens_on_user_id_and_revoked_at"
  end
end
