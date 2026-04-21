# frozen_string_literal: true

class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type
      t.datetime :received_at, null: false
      t.json :payload_summary

      t.timestamps
    end

    add_index :webhook_events, [ :provider, :event_id ], unique: true
  end
end
