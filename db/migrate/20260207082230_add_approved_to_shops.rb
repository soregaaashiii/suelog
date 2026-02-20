class AddApprovedToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :approved, :boolean, null: false, default: false
  end
end
