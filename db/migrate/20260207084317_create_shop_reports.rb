class CreateShopReports < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_reports do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :reporter_name
      t.string :reason
      t.text :detail
      t.integer :status, null: false, default: 0
      t.timestamps
    end
  end
end
