class CreatePageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :page_views do |t|
      t.string :path, null: false
      t.string :referrer
      t.string :referrer_host
      t.string :visitor_hash, null: false
      t.string :user_agent

      t.timestamps
    end

    add_index :page_views, :created_at
    add_index :page_views, :path
    add_index :page_views, :referrer_host
  end
end
