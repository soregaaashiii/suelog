class CreateShopClicks < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_clicks do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :kind, null: false

      t.timestamps
    end

    add_index :shop_clicks, :kind
    add_index :shop_clicks, :created_at
  end
end