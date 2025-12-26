class AddVoicePreferenceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :voice_preference, :string
  end
end
