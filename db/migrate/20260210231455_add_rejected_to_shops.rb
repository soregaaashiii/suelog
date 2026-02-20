class AddRejectedToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :rejected, :boolean
  end
end
