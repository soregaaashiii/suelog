class AddSourceAndPlaceIdToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :source, :string
    add_column :shops, :place_id, :string
  end
end
