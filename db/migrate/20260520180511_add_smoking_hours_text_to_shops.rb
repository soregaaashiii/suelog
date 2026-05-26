class AddSmokingHoursTextToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :smoking_hours_text, :string
  end
end
