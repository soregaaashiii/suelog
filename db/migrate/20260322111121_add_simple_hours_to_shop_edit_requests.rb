class AddSimpleHoursToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_opening_hours_text, :text
    add_column :shop_edit_requests, :proposed_holiday_hours_text, :text
    add_column :shop_edit_requests, :proposed_closed_days_text, :string
  end
end
