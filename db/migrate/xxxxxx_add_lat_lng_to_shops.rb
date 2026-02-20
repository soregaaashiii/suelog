class AddLatLngToShops < ActiveRecord::Migration[7.1]
def change
add_column :shops, :latitude, :float
add_column :shops, :longitude, :float

add_index :shops, [:latitude, :longitude]
end
end
