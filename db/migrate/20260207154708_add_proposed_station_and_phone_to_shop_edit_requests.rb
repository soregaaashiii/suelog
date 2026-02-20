class AddProposedStationAndPhoneToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_nearest_station, :string
    add_column :shop_edit_requests, :proposed_phone, :string
  end
end
