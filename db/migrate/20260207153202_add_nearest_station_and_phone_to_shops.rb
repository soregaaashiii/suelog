class AddNearestStationAndPhoneToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :nearest_station, :string
    add_column :shops, :phone, :string
  end
end
