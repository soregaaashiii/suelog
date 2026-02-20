class AddProposedOpeningHoursToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_opening_hours, :string
  end
end
