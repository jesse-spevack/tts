# frozen_string_literal: true

class CreateNarrations < ActiveRecord::Migration[8.1]
  def change
    create_table :narrations do |t|
      t.string :public_id, null: false
      t.string :title, null: false
      t.string :author
      t.text :description
      t.string :source_url
      t.text :source_text
      t.integer :source_type, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.string :gcs_episode_id
      t.integer :duration_seconds
      t.integer :audio_size_bytes
      t.string :voice
      t.datetime :processing_started_at
      t.datetime :processing_completed_at
      t.datetime :expires_at, null: false
      t.references :mpp_payment, null: false, foreign_key: true

      t.timestamps
    end

    add_index :narrations, :public_id, unique: true
    add_index :narrations, :status
    add_index :narrations, :expires_at
  end
end
