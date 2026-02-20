class AddProposedSmokingToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_smoking_area, :integer
    add_column :shop_edit_requests, :proposed_smoking_type, :integer
  end
end
