class AddTabelogColumnsToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :tabelog_affiliate_url, :string
    add_column :shops, :tabelog_matched_at, :datetime
    add_column :shops, :tabelog_match_method, :string
  end
end