class AddOpeningHoursToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :opening_hours, :string
  end
end
