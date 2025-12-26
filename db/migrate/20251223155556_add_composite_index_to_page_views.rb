class AddCompositeIndexToPageViews < ActiveRecord::Migration[8.1]
  def change
    add_index :page_views, [ :created_at, :visitor_hash ]
  end
end
