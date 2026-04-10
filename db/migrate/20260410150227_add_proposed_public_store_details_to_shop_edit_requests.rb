class AddProposedPublicStoreDetailsToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_public_store_details, :text
  end
end
