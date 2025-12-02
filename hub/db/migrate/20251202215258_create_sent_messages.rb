class CreateSentMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :sent_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.string :message_type, null: false

      t.timestamps
    end

    add_index :sent_messages, [:user_id, :message_type], unique: true
  end
end
