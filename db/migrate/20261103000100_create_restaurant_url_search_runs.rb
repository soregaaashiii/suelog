class CreateRestaurantUrlSearchRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :restaurant_url_search_runs do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :state, null: false, default: "pending"
      t.string :run_token
      t.string :input_digest
      t.text :payload
      t.timestamps
    end
    add_index :restaurant_url_search_runs, [:shop_id, :provider], unique: true
  end
end
