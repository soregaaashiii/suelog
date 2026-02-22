class AddSourceAndPlaceIdToShops < ActiveRecord::Migration[7.1]
def change
unless column_exists?(:shops, :source)
add_column :shops, :source, :string
end

unless column_exists?(:shops, :place_id)
add_column :shops, :place_id, :string
end
end
end