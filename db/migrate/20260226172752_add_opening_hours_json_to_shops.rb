class AddOpeningHoursJsonToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :opening_hours_json, :json
  end
end
