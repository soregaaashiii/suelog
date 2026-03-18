# frozen_string_literal: true

class AddSimpleHoursColumnsToShops < ActiveRecord::Migration[8.0]
def change
add_column :shops, :opening_hours_text, :text
add_column :shops, :holiday_hours_text, :text
add_column :shops, :closed_days_text, :string
end
end
