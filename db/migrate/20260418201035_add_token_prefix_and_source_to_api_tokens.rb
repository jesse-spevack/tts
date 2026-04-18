class AddTokenPrefixAndSourceToApiTokens < ActiveRecord::Migration[8.1]
  # Adds two columns used by the self-serve API-key UI (epic agent-team-q8y):
  #
  # - token_prefix: stores prefix + first few random chars (e.g. "sk_live_aBcD")
  #   so the Settings UI and structured logs can identify which token is which
  #   without storing or exposing the plaintext. Nullable so pre-existing
  #   tokens (created before this column existed) display as "Legacy" in the UI.
  #
  # - source: distinguishes tokens issued by the Chrome extension flow from
  #   tokens created directly by the user in /settings. Existing tokens are
  #   all extension-sourced (the only caller path today); new tokens default
  #   to "user" so the Settings UI creates user-sourced tokens by default.
  def change
    add_column :api_tokens, :token_prefix, :string

    # Add column defaulting to "extension" so existing rows get backfilled
    # to the correct historical value, then flip the default to "user" for
    # any rows created from this point forward.
    add_column :api_tokens, :source, :string, null: false, default: "extension"
    change_column_default :api_tokens, :source, from: "extension", to: "user"

    add_index :api_tokens, [ :user_id, :source, :revoked_at ]
  end
end
