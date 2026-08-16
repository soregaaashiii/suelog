class AddSecondarySmokingConditions < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :smoking_area_2, :integer
    add_column :shops, :smoking_type_2, :integer
    add_column :shop_edit_requests, :proposed_smoking_area_2, :integer
    add_column :shop_edit_requests, :proposed_smoking_type_2, :integer
  end
end
