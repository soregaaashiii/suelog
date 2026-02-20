class AddLatLngToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :latitude, :float
    add_column :shops, :longitude, :float
  end
end
