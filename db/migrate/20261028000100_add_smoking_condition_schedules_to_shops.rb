class AddSmokingConditionSchedulesToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :smoking_condition_schedules, :json, default: {}, null: false
  end
end
