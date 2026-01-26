class AddEmailEpisodeConfirmationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_episode_confirmation, :boolean, default: true, null: false
  end
end
