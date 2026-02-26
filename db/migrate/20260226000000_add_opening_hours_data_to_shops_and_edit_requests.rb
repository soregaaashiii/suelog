class AddOpeningHoursDataToShopsAndEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :opening_hours_data, :json, default: {}, null: false
    add_column :shop_edit_requests, :proposed_opening_hours_data, :json, default: {}, null: false
  end
end
