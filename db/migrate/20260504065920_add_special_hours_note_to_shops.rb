class AddSpecialHoursNoteToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :special_hours_note, :text
  end
end
