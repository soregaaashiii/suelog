# /Users/kawamuratakuya/dev/suelog/db/migrate/20260410XXXXXX_add_public_store_details_to_shops.rb
class AddPublicStoreDetailsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :public_store_details, :text
  end
end
