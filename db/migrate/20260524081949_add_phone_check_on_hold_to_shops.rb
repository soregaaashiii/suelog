class AddPhoneCheckOnHoldToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :phone_check_on_hold, :boolean, null: false, default: false
    add_index :shops, :phone_check_on_hold
  end
end
