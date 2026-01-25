class RemoveTokenPrefixFromApiTokens < ActiveRecord::Migration[8.1]
  def change
    remove_column :api_tokens, :token_prefix, :string
  end
end
