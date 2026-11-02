class AddBookingButtonVisibilityToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :hide_tabelog_booking_button, :boolean, default: false, null: false
    add_column :shops, :hide_hotpepper_booking_button, :boolean, default: false, null: false
  end
end
