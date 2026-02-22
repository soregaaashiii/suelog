class AddSourceAndPlaceIdToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :source, :string
    add_column :shops, :place_id, :string

    add_index :shops, :source
    add_index :shops, :place_id, unique: true
  end
end
