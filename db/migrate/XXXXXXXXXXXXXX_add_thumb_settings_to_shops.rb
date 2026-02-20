class AddThumbSettingsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :thumb_source, :string
    add_column :shops, :thumb_index, :integer, default: 0, null: false

    add_index :shops, :thumb_source
  end
end

