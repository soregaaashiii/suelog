class CreateShopBusinessHourWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_business_hour_windows do |t|
      t.references :shop, null: false, foreign_key: true
      t.integer :weekday, null: false
      t.integer :opens_at_minute, null: false
      t.integer :closes_at_minute, null: false
    end

    add_index :shop_business_hour_windows,
              %i[shop_id weekday opens_at_minute closes_at_minute],
              unique: true,
              name: "index_shop_hours_on_shop_day_and_range"
    add_check_constraint :shop_business_hour_windows,
                         "weekday BETWEEN 0 AND 6",
                         name: "shop_hours_weekday_range"
    add_check_constraint :shop_business_hour_windows,
                         "opens_at_minute >= 0 AND closes_at_minute <= 1440 AND opens_at_minute < closes_at_minute",
                         name: "shop_hours_minute_range"
  end
end
