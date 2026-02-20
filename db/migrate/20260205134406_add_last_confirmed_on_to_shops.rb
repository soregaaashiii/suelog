class AddLastConfirmedOnToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :last_confirmed_on, :date
  end
end
