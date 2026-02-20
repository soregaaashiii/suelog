class AddGenreToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :genre, :string
    add_column :shop_edit_requests, :genre_other, :string
  end
end
