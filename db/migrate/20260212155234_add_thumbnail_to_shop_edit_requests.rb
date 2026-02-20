class AddThumbnailToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_thumbnail_kind, :string
    add_column :shop_edit_requests, :proposed_thumbnail_index, :integer
  end
end
