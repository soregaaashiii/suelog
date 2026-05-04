class AddProposedSpecialHoursNoteToShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_edit_requests, :proposed_special_hours_note, :text
  end
end