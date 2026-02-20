class AddThumbnailToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :thumbnail_kind, :string, default: "auto", null: false
    add_column :shops, :thumbnail_index, :integer, default: 1, null: false
  end
end
