class AddPlaceIdAndSourceToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :place_id, :string
    add_column :shops, :source, :string

    add_index :shops, :place_id, unique: true
    add_index :shops, :source
  end
end