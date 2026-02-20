class ChangeOpeningHoursToText < ActiveRecord::Migration[8.1]
  def change
    change_column :shops, :opening_hours, :text
    change_column :shop_edit_requests, :proposed_opening_hours, :text
  end
end

