# frozen_string_literal: true

class AddVoiceToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :episodes, :voice, :string
  end
end
