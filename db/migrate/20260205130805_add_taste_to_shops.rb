class AddTasteToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :taste, :integer
  end
end
