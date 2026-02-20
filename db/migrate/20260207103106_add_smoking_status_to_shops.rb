class AddSmokingStatusToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :smoking_area, :integer
    add_column :shops, :smoking_type, :integer
  end
end
